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
    internal int[][] FreedChoices = Array.Empty<int[]>();  // num redesenho de borda, o que sai do selecionado em cada escolha
    internal int[] Freed => Choice < FreedChoices.Length ? FreedChoices[Choice] : Array.Empty<int>();
    /// O traço vira a borda: além de ganhar área, o selecionado pode perder a que passa do traço.
    public bool IsRedraw { get; internal set; }

    public int PathId => Next.Id;
    public int SourceOwner => Next.Source;
    public int TargetOwner => Next.Target;
    public int ChoiceCount => Choices.Length;
    public int Choice { get; private set; }
    /// Quem fica com o que o traço tira do selecionado: 0 = ninguém (redesenhar a borda); outro dono = DIVIDIR (o lado que sai vira dele).
    public int FreedOwner { get; set; }
    /// Quantos pixels o traço tira do selecionado na escolha atual.
    public int FreedCount => Freed.Length;

    /// Escolhe qual dos pedaços separados passa para o selecionado.
    public void Choose(int i)
    {
        if (i < 0 || i >= Choices.Length) throw new ArgumentOutOfRangeException(nameof(i));
        Choice = i;
        Next = Next with { Pixels = Choices[i] };
    }
}
