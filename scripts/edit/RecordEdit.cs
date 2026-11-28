using System.Collections.Generic;
using Godot;

namespace Evron;

/// Uma operação nos cadastros como DADO: as linhas que ela inseriu, alterou ou apagou, com os valores de antes (Registry.BeginRecord/EndRecord).
/// Já nasce aplicada; vai na mesma pilha de desfazer do terreno e do território (command_stack.gd).
public partial class RecordEdit : RefCounted
{
    internal record Change(string Op, string Table, long RowId, string[] Columns, object?[] Values);

    Registry _registry = null!;
    List<Change> _undo = [];  // o que desfaz aplica (o inverso disto)
    List<Change> _redo = [];

    /// Memória aproximada no histórico, em bytes.
    public long Bytes { get; private set; }

    /// Tabelas tocadas (para quem precisa saber o que recarregar).
    public string[] Tables() => [.. new SortedSet<string>(_undo.ConvertAll(c => c.Table))];

    public RecordEdit() { }  // o Godot exige um construtor sem parâmetros

    internal RecordEdit(Registry registry, List<Change> changes)
    {
        _registry = registry;
        _undo = changes;
        foreach (var c in changes)
        {
            Bytes += 64;
            foreach (var v in c.Values) Bytes += v is string s ? 2 * s.Length : v is byte[] b ? b.Length : 8;
        }
    }

    public void Undo() => _redo = _registry.Revert(_undo);

    public void Redo() => _undo = _registry.Revert(_redo);
}
