using System;
using Godot;

namespace Evron;

/// Uma edição do terreno como DADO: os pixels mexidos com a altura antes e depois (e o mesmo para os rios).
/// Vai para a CommandStack (Undo/Redo/Bytes) e, quando houver persistência, pode ser gravada como está (só arrays).
/// 12 bytes por pixel de altura e 6 por pixel de rio (os dois Dictionary do GDScript gastavam bem mais).
public partial class TerrainEdit : RefCounted
{
    private Terrain? _terrain;
    private int[] _idx = Array.Empty<int>();
    private float[] _before = Array.Empty<float>();
    private float[] _after = Array.Empty<float>();
    private int[] _ridx = Array.Empty<int>();
    private byte[] _rbefore = Array.Empty<byte>();
    private byte[] _rafter = Array.Empty<byte>();

    public TerrainEdit() { }  // o Godot exige um construtor sem argumentos

    internal TerrainEdit(Terrain terrain, int[] idx, float[] before, int[] ridx, byte[] rbefore)
    {
        _terrain = terrain;
        _idx = idx;
        _before = before;
        _after = Array.ConvertAll(idx, i => terrain.H[i]);
        _ridx = ridx;
        _rbefore = rbefore;
        _rafter = Array.ConvertAll(ridx, i => terrain.R[i]);
    }

    /// Quantos pixels de altura a edição mudou.
    public int Count => _idx.Length;

    /// Memória ocupada (para a pilha limitar por tamanho, não por contagem).
    public long Bytes => _idx.Length * 12L + _ridx.Length * 6L;

    public void Undo() => Write(_before, _rbefore);

    public void Redo() => Write(_after, _rafter);

    private void Write(float[] heights, byte[] rivers)
    {
        var t = _terrain!;
        for (int i = 0; i < _idx.Length; i++)
            t.SetH(_idx[i], heights[i]);
        for (int i = 0; i < _ridx.Length; i++)
            t.R[_ridx[i]] = rivers[i];
        t.RiversDirty |= _ridx.Length > 0;
    }
}
