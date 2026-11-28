using System;
using System.Collections.Generic;
using System.Linq;

namespace Evron;

/// Desfazer dos cadastros: entre BeginRecord e EndRecord, gatilhos temporários anotam cada linha inserida, alterada ou apagada (com os
/// valores antigos, sem converter: o REAL volta bit a bit). EndRecord devolve um RecordEdit com isso, que vai na pilha comum (command_stack.gd).
/// Vale para qualquer tabela de cadastro, então editar, duplicar e excluir (com tudo o que vai junto) desfazem sem um comando por tabela.
/// Ficam de fora as tabelas de pixels, que têm comando próprio (TerrainEdit, TerritoryEdit).
public partial class Registry
{
    static readonly HashSet<string> NotRecorded = ["terrain_tile", "territory_layer", "territory_tile", "sqlite_sequence"];

    int _recording;          // BeginRecord aninhado: só o de fora liga e desliga
    long _recordStart;       // primeiro seq do registro aberto
    readonly HashSet<string> _hasRowidAlias = [];  // tabelas com "integer primary key": o id já é o rowid e não se escreve duas vezes

    void CreateUndoTriggers()
    {
        _recording = 0;
        _db.Run("""
            create temp table if not exists undo_state(on_ integer not null);
            create temp table if not exists undo_log(seq integer primary key, op text not null, tbl text not null, rid integer not null);
            create temp table if not exists undo_val(seq integer not null, col text not null, val);
            delete from undo_state; insert into undo_state values (0);
            delete from undo_log; delete from undo_val;
            """);
        foreach (var r in _db.Rows("select name from sqlite_schema where type = 'table'"))
        {
            string t = Str(r[0]);
            if (NotRecorded.Contains(t) || t.StartsWith("sqlite_")) continue;
            var info = _db.Rows($"pragma table_info(\"{t}\")");
            var cols = info.Select(c => Str(c[1])).ToArray();
            var pk = info.Where(c => Convert.ToInt64(c[5]) > 0).ToList();
            if (pk.Count == 1 && Str(pk[0][2]).Equals("integer", StringComparison.OrdinalIgnoreCase)) _hasRowidAlias.Add(t);
            string Vals(string row) => string.Join(", ", cols.Select(c => $"((select max(seq) from undo_log), '{c}', {row}.\"{c}\")"));
            const string On = "when (select on_ from undo_state) = 1";
            _db.Run($"""
                create temp trigger if not exists "undo_i_{t}" after insert on main."{t}" {On} begin
                  insert into undo_log(op, tbl, rid) values ('i', '{t}', new.rowid); end;
                create temp trigger if not exists "undo_d_{t}" after delete on main."{t}" {On} begin
                  insert into undo_log(op, tbl, rid) values ('d', '{t}', old.rowid);
                  insert into undo_val(seq, col, val) values {Vals("old")}; end;
                create temp trigger if not exists "undo_u_{t}" after update on main."{t}" {On} begin
                  insert into undo_log(op, tbl, rid) values ('u', '{t}', new.rowid);
                  insert into undo_val(seq, col, val) values {Vals("old")}; end;
                """);
        }
    }

    /// Começa a anotar as mudanças nos cadastros. Aninha: só o EndRecord de fora fecha.
    public void BeginRecord()
    {
        if (_recording++ > 0) return;
        _recordStart = Convert.ToInt64(_db.Scalar("select coalesce(max(seq), 0) + 1 from temp.undo_log"));
        _db.Run("update temp.undo_state set on_ = 1");
    }

    /// Fecha o registro: o comando com o que mudou desde BeginRecord, ou null se nada mudou.
    public RecordEdit? EndRecord()
    {
        if (_recording == 0 || --_recording > 0) return null;
        var changes = TakeChanges(_recordStart);
        return changes.Count == 0 ? null : new RecordEdit(this, changes);
    }

    List<RecordEdit.Change> TakeChanges(long start)
    {
        _db.Run("update temp.undo_state set on_ = 0");
        var vals = new System.Collections.Generic.Dictionary<long, List<(string, object?)>>();
        foreach (var v in _db.Rows("select seq, col, val from temp.undo_val where seq >= @0 order by rowid", start))
        {
            long seq = Convert.ToInt64(v[0]);
            if (!vals.TryGetValue(seq, out var list)) vals[seq] = list = [];
            list.Add((Str(v[1]), v[2]));
        }
        var changes = _db.Rows("select seq, op, tbl, rid from temp.undo_log where seq >= @0 order by seq", start).Select(r =>
        {
            vals.TryGetValue(Convert.ToInt64(r[0]), out var list);
            return new RecordEdit.Change(Str(r[1]), Str(r[2]), Convert.ToInt64(r[3]), list?.Select(x => x.Item1).ToArray() ?? [],
                list?.Select(x => x.Item2).ToArray() ?? []);
        }).ToList();
        _db.Run("delete from temp.undo_log where seq >= @0; delete from temp.undo_val where seq >= @0", start);
        return changes;
    }

    /// Aplica o inverso de cada mudança, da última para a primeira, numa transação; devolve as mudanças que isso fez (o inverso do inverso).
    internal List<RecordEdit.Change> Revert(List<RecordEdit.Change> changes)
    {
        _layerOf = null;
        return _db.Tx(() =>
        {
            long start = Convert.ToInt64(_db.Scalar("select coalesce(max(seq), 0) + 1 from temp.undo_log"));
            _db.Run("update temp.undo_state set on_ = 1");
            try
            {
                for (int i = changes.Count - 1; i >= 0; i--)
                {
                    var c = changes[i];
                    // tbl e col vêm do esquema (sqlite_schema/table_info), nunca do usuário; os valores vão como parâmetros.
                    if (c.Op == "i") _db.Run($"delete from \"{c.Table}\" where rowid = @0", c.RowId);
                    else if (c.Op == "d")
                    {
                        string rowid = _hasRowidAlias.Contains(c.Table) ? "" : "rowid, ";
                        _db.Run($"insert into \"{c.Table}\"({rowid}{string.Join(", ", c.Columns.Select(n => $"\"{n}\""))}) values ({(rowid == "" ? "" : "@0, ")}" +
                            string.Join(", ", c.Columns.Select((_, k) => "@" + (k + 1))) + ")", [c.RowId, .. c.Values]);
                    }
                    else
                        _db.Run($"update \"{c.Table}\" set {string.Join(", ", c.Columns.Select((n, k) => $"\"{n}\" = @{k + 1}"))} where rowid = @0",
                            [c.RowId, .. c.Values]);
                }
            }
            catch { _db.Run("update temp.undo_state set on_ = 0"); throw; }
            return TakeChanges(start);
        });
    }
}
