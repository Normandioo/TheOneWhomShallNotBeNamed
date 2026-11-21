using System;
using System.Collections.Generic;
using System.Linq;
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
    private (Territory Map, TerritoryBoundary? Old, TerritoryBoundary New)? _parentBoundary;
    private int _depth;
    private readonly List<TerritoryEdit> _subdivisions = new();

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

    public long Bytes => _idx.Length * 8L + (_oldBoundary?.Bytes ?? 0) + (_newBoundary?.Bytes ?? 0) + _subdivisions.Sum(edit => edit.Bytes);

    public bool TouchesOwner(int owner) =>
        _oldBoundary?.Source == owner || _oldBoundary?.Target == owner ||
        _newBoundary?.Source == owner || _newBoundary?.Target == owner ||
        Array.IndexOf(_before, (ushort)owner) >= 0 || Array.IndexOf(_after, (ushort)owner) >= 0 || _subdivisions.Exists(edit => edit.TouchesOwner(owner));

    public void Undo()
    {
        for (int i = _subdivisions.Count - 1; i >= 0; i--) _subdivisions[i].Undo();
        Write(_before, _oldBoundary);
    }

    public void Redo()
    {
        Write(_after, _newBoundary);
        foreach (var edit in _subdivisions) edit.Redo();
    }

    /// Ajusta os filhos nas células alteradas pelo pai, respeitando a ocupação e os vínculos atuais.
    public TerritoryEdit? TrimSubdivisions(Territory child, Registry registry)
    {
        if (_territory == null || child.Size != _territory.Size) return null;
        var boundary = _parentBoundary;
        if (_newBoundary != null) boundary = (_territory, _oldBoundary, _newBoundary);
        var oldClipped = boundary?.Old?.Subdivisions[_depth];
        var newClipped = boundary?.New.Subdivisions[_depth];
        bool recorded = false;
        var parents = new Dictionary<int, long>();
        var pixels = new List<int>();
        var previous = new List<ushort>();

        long ParentOf(int owner)
        {
            if (!parents.TryGetValue(owner, out long parent))
                parents[owner] = parent = registry.TerritoryParent(owner);
            return parent;
        }

        for (int i = 0; i < _idx.Length; i++)
        {
            if (_before[i] == _after[i]) continue;
            int p = _idx[i], owner = child.Get(p);
            int replacement;
            if (owner != 0 && _before[i] != 0 && ParentOf(owner) == _before[i])
            {
                if (boundary is { } path && Array.BinarySearch(path.New.Pixels, p) >= 0)
                {
                    newClipped![p] = (ushort)owner;
                    recorded = true;
                }
                replacement = 0;
            }
            else if (owner == 0 && _after[i] != 0 && oldClipped != null &&
                     oldClipped.TryGetValue(p, out ushort clipped) && ParentOf(clipped) == _after[i])
            {
                replacement = clipped;
            }
            else continue;

            pixels.Add(p);
            previous.Add((ushort)owner);
            child.Put(p, replacement);
        }
        if (pixels.Count == 0) return null;
        if (recorded && boundary is { } changed) changed.Map.SetBoundary(changed.New.Id, changed.New);
        child.Touch();
        var edit = new TerritoryEdit(child, pixels.ToArray(), previous.ToArray())
        {
            _parentBoundary = boundary,
            _depth = _depth + 1
        };
        _subdivisions.Add(edit);
        return edit;
    }

    private void Write(ushort[] owners, TerritoryBoundary? boundary)
    {
        var t = _territory!;
        for (int i = 0; i < _idx.Length; i++) t.Put(_idx[i], owners[i]);
        if (_newBoundary != null) t.SetBoundary(_newBoundary.Id, boundary);
        t.Touch();
    }
}
