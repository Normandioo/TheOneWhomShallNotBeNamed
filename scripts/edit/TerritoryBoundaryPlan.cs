using System;
using Godot;

namespace Evron;

/// Uma divisão calculada para uma versão específica da camada política.
public partial class TerritoryBoundaryPlan : RefCounted
{
    internal Territory? Map;
    internal long Version;
    internal TerritoryBoundary? Previous;
    internal TerritoryBoundary Next = new(0, 0, 0, Array.Empty<Vector3>(), Array.Empty<int>());

    public int PathId => Next.Id;
    public int SourceOwner => Next.Source;
}
