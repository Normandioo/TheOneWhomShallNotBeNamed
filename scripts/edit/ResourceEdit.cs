using System.Collections.Generic;
using Godot;

namespace Evron;

/// Uma operação no catálogo de recursos ou numa ocorrência como DADO: a linha inteira antes e depois (null = não existia).
/// Já nasce aplicada; vai na mesma pilha de desfazer do terreno e do território (command_stack.gd).
public partial class ResourceEdit : RefCounted
{
    WorldDb _db = null!;
    string _table = "";
    string[] _columns = [];
    object?[]? _before, _after;

    public long Id { get; private set; }

    /// Memória aproximada no histórico, em bytes.
    public long Bytes { get; private set; }

    internal static ResourceEdit Done(WorldDb db, string table, string[] columns, long id, object?[]? before, object?[]? after)
    {
        long bytes = 128;
        foreach (var row in new[] { before, after })
            foreach (var v in row ?? [])
                bytes += v is string s ? 2 * s.Length : 8;
        return new ResourceEdit { _db = db, _table = table, _columns = columns, Id = id, _before = before, _after = after, Bytes = bytes };
    }

    public void Undo() => Restore(_before);

    public void Redo() => Restore(_after);

    // table e columns são constantes do RegistryResources, nunca texto do usuário; os valores vão como parâmetros.
    void Restore(object?[]? row)
    {
        if (row == null)
        {
            _db.Run($"delete from {_table} where id = @0", Id);
            return;
        }
        var args = new List<object?>(row) { Id };
        var names = new List<string>();
        var set = new List<string>();
        for (int i = 0; i < _columns.Length; i++)
        {
            names.Add("@" + i);
            set.Add($"{_columns[i]} = excluded.{_columns[i]}");
        }
        names.Add("@" + _columns.Length);
        // upsert, não "insert or replace": apagar a linha antiga quebraria a chave estrangeira das ocorrências de um tipo.
        _db.Run($"insert into {_table}({string.Join(", ", _columns)}, id) values ({string.Join(", ", names)}) " +
            $"on conflict(id) do update set {string.Join(", ", set)}", args.ToArray());
    }
}
