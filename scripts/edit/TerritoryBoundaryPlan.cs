using System;
using Godot;

namespace Evron;

/// Uma divisão calculada para uma versão específica da camada política.
public partial class TerritoryBoundaryPlan : RefCounted
{
    internal Territory? Map;
    public long Version { get; internal set; }
    internal TerritoryBoundary? Previous;
    internal TerritoryBoundary Next = new(0, 0, 0, Array.Empty<Vector3>(), Array.Empty<int>());
    internal int[][] Choices = Array.Empty<int[]>();  // os pedaços separados que encostam no selecionado

    public int PathId => Next.Id;
    public int SourceOwner => Next.Source;
    public int TargetOwner => Next.Target;
    public int ChoiceCount => Choices.Length;
    public int Choice { get; private set; }

    /// Escolhe qual dos pedaços separados passa para o selecionado.
    public void Choose(int i)
    {
        if (i < 0 || i >= Choices.Length) throw new ArgumentOutOfRangeException(nameof(i));
        Choice = i;
        Next = Next with { Pixels = Choices[i] };
    }
}
