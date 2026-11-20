using System;
using Godot;

namespace Evron;

/// Uma edição do território como DADO: os pixels mexidos com o dono antes e depois. Vai para a CommandStack (Undo/Redo/Bytes), como a TerrainEdit.
/// 8 bytes por pixel.
public partial class TerritoryEdit : RefCounted
{
    private Territory? _territory;
    private int[] _idx = Array.Empty<int>();
    private ushort[] _before = Array.Empty<ushort>();
    private ushort[] _after = Array.Empty<ushort>();
    private TerritoryBoundary? _oldBoundary;
    private TerritoryBoundary? _newBoundary;

    public TerritoryEdit() { }  // o Godot exige um construtor sem argumentos

    internal TerritoryEdit(Territory territory, int[] idx, ushort[] before,
        TerritoryBoundary? oldBoundary = null, TerritoryBoundary? newBoundary = null)
    {
        _territory = territory;
        _idx = idx;
        _before = before;
        _after = Array.ConvertAll(idx, i => (ushort)territory.Get(i));
        _oldBoundary = oldBoundary;
        _newBoundary = newBoundary;
    }

    /// Quantos pixels a edição mudou.
    public int Count => _idx.Length;

    public long Bytes => _idx.Length * 8L + (_oldBoundary?.Bytes ?? 0) + (_newBoundary?.Bytes ?? 0);

    public bool TouchesOwner(int owner) =>
        _oldBoundary?.Source == owner || _oldBoundary?.Target == owner ||
        _newBoundary?.Source == owner || _newBoundary?.Target == owner ||
        Array.IndexOf(_before, (ushort)owner) >= 0 || Array.IndexOf(_after, (ushort)owner) >= 0;

    public void Undo() => Write(_before, _oldBoundary);

    public void Redo() => Write(_after, _newBoundary);

    private void Write(ushort[] owners, TerritoryBoundary? boundary)
    {
        var t = _territory!;
        for (int i = 0; i < _idx.Length; i++) t.Put(_idx[i], owners[i]);
        if (_newBoundary != null) t.SetBoundary(_newBoundary.Id, boundary);
        t.Touch();
    }
}
