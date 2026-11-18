using System;
using System.Collections.Generic;
using Godot;
using Microsoft.Data.Sqlite;

namespace Evron;

/// Acesso ao banco do mundo (SQLite): abrir, migrar e consultar com parâmetros. Não conhece os cadastros (isso é do Registry).
public partial class WorldDb : RefCounted
{
    SqliteConnection? _db;

    /// Abre (ou cria) o arquivo; ":memory:" para testes. Chaves estrangeiras ligadas.
    public void Open(string path)
    {
        Close();
        // O builder escapa o caminho (um ';' ou aspas no nome da pasta quebraria a string montada à mão). Sem pool: com ele, o arquivo fica aberto
        // depois do Close e, no Windows, não dá para apagá-lo (os testes reabriam o banco da rodada anterior).
        _db = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path, Pooling = false }.ToString());
        try
        {
            _db.Open();
            Execute("PRAGMA foreign_keys = ON");
        }
        catch { Close(); throw; }
    }

    public void Close() { _db?.Dispose(); _db = null; }

    public bool IsOpen() => _db != null;

    public void Execute(string sql) => Run(sql);

    /// Primeiro valor da primeira linha como inteiro de 64 bits (contagens, ids, instantes).
    public long QueryLong(string sql) => Convert.ToInt64(Scalar(sql));

    public string QueryText(string sql) => Scalar(sql)?.ToString() ?? "";

    public string Version() => QueryText("select sqlite_version()");

    /// Versão do esquema (PRAGMA user_version); 0 = banco novo.
    public long SchemaVersion() => QueryLong("PRAGMA user_version");

    /// Aplica as migrações que faltam, cada uma numa transação; quem falha desfaz e deixa a versão anterior.
    internal void Migrate(string[] steps)
    {
        long current = SchemaVersion();
        if (current > steps.Length)  // banco criado por uma versão mais nova: escrever nele com um esquema que não se conhece o corromperia
            throw new InvalidOperationException($"o banco é da versão {current} do esquema e este programa só conhece até a {steps.Length}");
        for (long v = current; v < steps.Length; v++)
        {
            long i = v;
            Tx(() => { Run(steps[i]); Run($"PRAGMA user_version = {i + 1}"); return 0; });
        }
    }

    internal object? Scalar(string sql, params object?[] args)
    {
        using var cmd = Cmd(sql, args);
        return cmd.ExecuteScalar();
    }

    internal int Run(string sql, params object?[] args)
    {
        using var cmd = Cmd(sql, args);
        return cmd.ExecuteNonQuery();
    }

    /// INSERT e devolve o id da linha.
    internal long Insert(string sql, params object?[] args)
    {
        Run(sql, args);
        return Convert.ToInt64(Scalar("select last_insert_rowid()"));
    }

    internal List<object?[]> Rows(string sql, params object?[] args)
    {
        using var cmd = Cmd(sql, args);
        using var r = cmd.ExecuteReader();
        var rows = new List<object?[]>();
        while (r.Read())
        {
            var row = new object?[r.FieldCount];
            for (int i = 0; i < row.Length; i++) row[i] = r.IsDBNull(i) ? null : r.GetValue(i);
            rows.Add(row);
        }
        return rows;
    }

    int _txDepth;

    /// Tudo ou nada: uma falha desfaz o que a função já gravou. Reentrante: só a transação de fora começa e termina.
    internal T Tx<T>(Func<T> f)
    {
        if (_txDepth > 0) return f();
        Run("BEGIN");
        _txDepth = 1;
        try { var r = f(); Run("COMMIT"); return r; }
        catch { Run("ROLLBACK"); throw; }
        finally { _txDepth = 0; }
    }

    SqliteCommand Cmd(string sql, object?[] args)
    {
        var cmd = _db!.CreateCommand();
        cmd.CommandText = sql;
        for (int i = 0; i < args.Length; i++) cmd.Parameters.AddWithValue("@" + i, args[i] ?? DBNull.Value);
        return cmd;
    }
}
