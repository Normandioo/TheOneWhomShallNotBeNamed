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

    public TerritoryEdit() { }  // o Godot exige um construtor sem argumentos

    internal TerritoryEdit(Territory territory, int[] idx, ushort[] before)
    {
        _territory = territory;
        _idx = idx;
        _before = before;
        _after = Array.ConvertAll(idx, i => (ushort)territory.Get(i));
    }

    /// Quantos pixels a edição mudou.
    public int Count => _idx.Length;

    public long Bytes => _idx.Length * 8L;

    public void Undo() => Write(_before);

    public void Redo() => Write(_after);

    private void Write(ushort[] owners)
    {
        var t = _territory!;
        for (int i = 0; i < _idx.Length; i++) t.Put(_idx[i], owners[i]);
        t.Touch();
    }
}
