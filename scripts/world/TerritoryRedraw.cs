using System;
using System.Collections.Generic;
using System.Linq;
using Godot;

namespace Evron;

/// "O traço vira a fronteira": uma linha aberta que começa e termina no território passa a ser a borda dele naquele trecho. O que faltava
/// entre o território e o traço entra (todos os bolsões, não um só); o que o território tinha do outro lado do traço sai e fica sem
/// dono. Vizinhos protegidos ("Não invadir") não são tocados. Trabalha na grade da pintura (centros dos pixels em coordenadas inteiras).
public partial class Territory
{
    private const double EndReach = 3.0;      // pixels do mapa: o quanto uma ponta do traço pode estar fora do território
    private const double CapReach = 4.0;      // uma ponta a até isto (~40 km) da borda é completada até ela; mais para dentro, o traço corta onde cruza
    private const int PocketMargin = 40;      // um bolsão que passa disto em volta do traço é o resto do mundo, não um bolsão

    /// O plano de um traço do pincel de fronteira, aberto ou remodelado: redesenhar a borda quando ele começa e termina no próprio
    /// território; senão, o corte de um vizinho ou o bolsão de terra livre (PlanBoundaryClaimOn). Com "Não invadir" desligado, um traço
    /// que passa por um vizinho continua sendo o corte dele (conquista).
    public Godot.Collections.Dictionary PlanStroke(int target, Vector3[] controls, int id, bool landOnly)
    {
        if (_stroke == null && ValidOwner(target) && ValidBoundaryPoints(controls) && !controls[0].IsEqualApprox(controls[^1]))
        {
            _boundaries.TryGetValue(id, out var stored);
            if (id == 0 || (stored != null && stored.Target == target && stored.Source == 0))
            {
                var redraw = PlanRedraw(target, controls, id, landOnly);
                if (redraw != null) return redraw;
            }
        }
        return PlanBoundaryClaimOn(target, controls, id, landOnly);
    }

    /// null = o traço não é um redesenho de borda (as pontas não estão no território, ou ele atravessa um vizinho sem proteção).
    private Godot.Collections.Dictionary? PlanRedraw(int target, Vector3[] controls, int id, bool landOnly)
    {
        // A curva na grade, sem saltar na longitude 180°, em passos de até meio pixel.
        var curve = SmoothBoundary(controls);
        var path = new List<(double X, double Y)> { BoundaryGrid(curve[0]) };
        for (int i = 1; i < curve.Length; i++)
        {
            var from = path[^1];
            var to = BoundaryGrid(curve[i]);
            to.X -= Size.X * Math.Round((to.X - from.X) / Size.X);
            int steps = Math.Max(1, (int)Math.Ceiling(2 * Math.Max(Math.Abs(to.X - from.X), Math.Abs(to.Y - from.Y))));
            for (int s = 1; s <= steps; s++)
                path.Add((from.X + (to.X - from.X) * s / steps, from.Y + (to.Y - from.Y) * s / steps));
        }
        int PixelAt(double x, double y) => BoundaryIndex((int)Math.Round(x), Math.Clamp((int)Math.Round(y), 0, Size.Y - 1));
        bool Owned(double x, double y) => Get(PixelAt(x, y)) == target;
        bool NearOwned((double X, double Y) p)
        {
            int reach = (int)Math.Ceiling(EndReach);
            for (int dy = -reach; dy <= reach; dy++)
            for (int dx = -reach; dx <= reach; dx++)
                if (dx * dx + dy * dy <= EndReach * EndReach && Owned(p.X + dx, p.Y + dy)) return true;
            return false;
        }
        if (!NearOwned(path[0]) || !NearOwned(path[^1])) return null;
        if (_takenLayer == null && path.Any(p => Get(PixelAt(p.X, p.Y)) is var owner && owner != 0 && owner != target)) return null;

        (double X, double Y) Direction(int i, int span)
        {
            var a = path[Math.Max(0, i - span)];
            var b = path[Math.Min(path.Count - 1, i + span)];
            double length = Math.Sqrt((b.X - a.X) * (b.X - a.X) + (b.Y - a.Y) * (b.Y - a.Y));
            return length < 1e-9 ? (0, 0) : ((b.X - a.X) / length, (b.Y - a.Y) / length);
        }

        // As linhas da grade que o traço cruza, e de que lado dele fica cada pixel encostado (+1 = o lado de (-ty, tx)).
        var edges = new HashSet<long>();
        var sides = new Dictionary<int, int>();
        for (int i = 0; i + 1 < path.Count; i++)
        {
            var (a, b) = (path[i], path[i + 1]);
            CrossedPairs(a, b, (p, px, py, q, qx, qy) =>
            {
                edges.Add(BoundaryEdge(p, q));
                foreach (var (pixel, x, y) in new[] { (p, px, py), (q, qx, qy) })
                {
                    double cross = (b.X - a.X) * (y - a.Y) - (b.Y - a.Y) * (x - a.X);
                    sides[pixel] = sides.GetValueOrDefault(pixel) + (cross > 0 ? 1 : -1);
                }
            });
        }
        var bounds = (Left: path.Min(p => p.X), Right: path.Max(p => p.X), Top: path.Min(p => p.Y), Bottom: path.Max(p => p.Y));
        var heights = _boundaryHeights ?? _terrain!.H;

        // De que lado fica o território: do lado em que a terra livre forma bolsões fechados contra ele (do outro, ela se abre para o
        // resto do mundo). Sem bolsão nenhum, o traço só recorta: decide o corte, e fica o pedaço maior.
        var pockets = new[] { Pockets(target, edges, sides, 1, landOnly, heights, bounds), Pockets(target, edges, sides, -1, landOnly, heights, bounds) };
        double[] pocketArea = pockets.Select(p => p.Sum(PixelKm2)).ToArray();
        int known = pocketArea[0] > pocketArea[1] ? 1 : pocketArea[1] > pocketArea[0] ? -1 : 0;

        // As pontas se fecham na borda mais perto (do lado de fora, quando se sabe qual é): assim o corte separa de verdade o que passa.
        var cut = new HashSet<long>(edges);
        CapEnd(target, path[0], Direction(0, 8), known, PixelAt, cut);
        CapEnd(target, path[^1], Direction(path.Count - 1, 8), known, PixelAt, cut);
        var (parts, balance) = CutOwned(target, cut, sides);
        int body = parts.Count == 0 ? -1 : Enumerable.Range(0, parts.Count).MaxBy(i => parts[i].Area);
        int side = known;
        if (side == 0)
        {
            double lean = Enumerable.Range(0, parts.Count).Where(i => i != body).Sum(i => -Math.Sign(balance[i]) * parts[i].Area);
            side = lean < 0 ? -1 : 1;
        }

        // O que sai: os pedaços que o corte separou do corpo e que estão do lado de fora.
        var freed = Enumerable.Range(0, parts.Count).Where(i => i != body && balance[i] * side < 0).SelectMany(i => parts[i].Pixels).ToList();
        var gone = freed.ToHashSet();
        var added = pockets[side > 0 ? 0 : 1].Where(p => !gone.Contains(p)).OrderBy(p => p).ToArray();
        freed.Sort();
        if (added.Length == 0 && freed.Count == 0) return RefuseBoundary("O traço já é a borda: não há o que mudar." + TakenHint);
        var choices = new List<(int[] Added, int[] Freed)> { (added, freed.ToArray()) };
        // "Outro lado": quando o traço só separou o território em dois, dá para trocar qual dos dois fica.
        if (added.Length == 0 && body >= 0)
            choices.Add((System.Array.Empty<int>(), parts[body].Pixels.OrderBy(p => p).ToArray()));

        _boundaries.TryGetValue(id, out var stored);
        var plan = new TerritoryBoundaryPlan
        {
            Map = this,
            Version = Version,
            IsRedraw = true,
            Choices = choices.Select(c => c.Added).ToArray(),
            FreedChoices = choices.Select(c => c.Freed).ToArray(),
            Next = new TerritoryBoundary(stored == null ? _nextBoundary : id, 0, target, controls.ToArray(), choices[0].Added)
        };
        return new Godot.Collections.Dictionary { ["plan"] = plan };
    }

    private double PixelKm2(int pixel) => RowCellKm2(pixel / Size.X, Size.X, Size.Y);

    /// Uma ponta que começa encostada na borda ganha um corte reto até o pixel de fora mais perto (do lado de fora, se known != 0). Longe
    /// dela não: um corte inventado separaria um pedaço legítimo do território.
    private void CapEnd(int target, (double X, double Y) end, (double X, double Y) along, int known, Func<double, double, int> pixelAt, HashSet<long> cut)
    {
        if (Get(pixelAt(end.X, end.Y)) != target) return;  // a ponta já está fora
        double farX = along.Y * known, farY = -along.X * known;
        (double X, double Y)? best = null;
        double nearest = CapReach * CapReach;
        for (int y = (int)Math.Ceiling(end.Y - CapReach); y <= (int)Math.Floor(end.Y + CapReach); y++)
        {
            if (y < 0 || y >= Size.Y) continue;
            for (int x = (int)Math.Ceiling(end.X - CapReach); x <= (int)Math.Floor(end.X + CapReach); x++)
            {
                double dx = x - end.X, dy = y - end.Y, d = dx * dx + dy * dy;
                if (d >= nearest || (known != 0 && dx * farX + dy * farY < -0.3 * Math.Sqrt(d)) || Get(BoundaryIndex(x, y)) == target) continue;
                (nearest, best) = (d, (x, y));
            }
        }
        if (best is not { } outside) return;
        double length = Math.Max(Math.Sqrt(nearest), 1e-6);
        var past = (X: outside.X + 0.6 * (outside.X - end.X) / length, Y: outside.Y + 0.6 * (outside.Y - end.Y) / length);
        var from = end;
        int steps = Math.Max(1, (int)Math.Ceiling(2 * length)) + 2;
        for (int s = 1; s <= steps; s++)
        {
            double t = (double)s / steps;
            var to = (end.X + (past.X - end.X) * t, end.Y + (past.Y - end.Y) * t);
            CrossedPairs(from, to, (p, _, _, q, _, _) => cut.Add(BoundaryEdge(p, q)));
            from = to;
        }
    }

    /// O território que o traço toca, repartido pelo corte: cada pedaço e de que lado do traço ele está (o saldo dos pixels encostados).
    private (List<(List<int> Pixels, double Area)> Parts, int[] Balance) CutOwned(int target, HashSet<long> cut, Dictionary<int, int> sides)
    {
        var onCut = Ends(cut);
        var label = new Dictionary<int, int>();
        var parts = new List<(List<int> Pixels, double Area)>();
        foreach (int seed in onCut)
        {
            if (Get(seed) != target || label.ContainsKey(seed)) continue;
            var pixels = new List<int> { seed };
            label[seed] = parts.Count;
            double area = 0;
            for (int i = 0; i < pixels.Count; i++)
            {
                int p = pixels[i];
                area += PixelKm2(p);
                foreach (var (x, y) in BoundaryNeighbors)
                {
                    int q = _terrain!.Neighbor(p, x, y);
                    if (q < 0 || label.ContainsKey(q) || Get(q) != target || (onCut.Contains(p) && cut.Contains(BoundaryEdge(p, q)))) continue;
                    label[q] = parts.Count;
                    pixels.Add(q);
                }
            }
            parts.Add((pixels, area));
        }
        var balance = new int[parts.Count];
        foreach (var (pixel, sum) in sides)
            if (label.TryGetValue(pixel, out int part)) balance[part] += Math.Sign(sum);
        return (parts, balance);
    }

    private static HashSet<int> Ends(HashSet<long> edges)
    {
        var pixels = new HashSet<int>();
        foreach (long edge in edges)
        {
            pixels.Add((int)(edge >> 32));
            pixels.Add((int)edge);
        }
        return pixels;
    }

    /// Os bolsões de um lado do traço: terra que pode ser tomada, encostada nele desse lado, fechada entre o traço e o território.
    private HashSet<int> Pockets(int target, HashSet<long> edges, Dictionary<int, int> sides, int keep, bool landOnly, float[] heights,
        (double Left, double Right, double Top, double Bottom) bounds)
    {
        var onCut = Ends(edges);
        double wide = bounds.Right - bounds.Left, tall = bounds.Bottom - bounds.Top;
        double margin = Math.Max(PocketMargin, 0.5 * Math.Max(wide, tall));
        double middle = (bounds.Left + bounds.Right) / 2;
        bool Inside(int p)
        {
            double x = p % Size.X, y = p / Size.X;
            x -= Size.X * Math.Round((x - middle) / Size.X);
            return x >= bounds.Left - margin && x <= bounds.Right + margin && y >= bounds.Top - margin && y <= bounds.Bottom + margin;
        }
        bool Free(int p) => Get(p) != target && Allowed(p) && (!landOnly || heights[p] >= 0f);
        var seen = new HashSet<int>();
        var added = new HashSet<int>();
        foreach (var (seed, sum) in sides)
        {
            if (sum * keep <= 0 || !Free(seed) || !seen.Add(seed)) continue;
            var pixels = new List<int> { seed };
            bool open = false, touches = false;
            for (int i = 0; i < pixels.Count && !open; i++)
            {
                int p = pixels[i];
                if (!Inside(p)) { open = true; break; }
                foreach (var (x, y) in BoundaryNeighbors)
                {
                    int q = _terrain!.Neighbor(p, x, y);
                    if (q < 0 || (onCut.Contains(p) && edges.Contains(BoundaryEdge(p, q)))) continue;
                    if (Get(q) == target) { touches = true; continue; }
                    if (!seen.Contains(q) && Free(q)) { seen.Add(q); pixels.Add(q); }
                }
            }
            // O que um pedaço aberto já visitou continua marcado: outra semente do mesmo pedaço não o toma por fechado.
            if (!open && touches) added.UnionWith(pixels);
        }
        return added;
    }

    /// Os pares de pixels vizinhos que o segmento a-b (na grade) separa: (índice, x, y) de cada um.
    private void CrossedPairs((double X, double Y) a, (double X, double Y) b, Action<int, int, int, int, int, int> pair)
    {
        for (int x = (int)Math.Ceiling(Math.Min(a.X, b.X)); x < Math.Max(a.X, b.X); x++)
        {
            int y = (int)Math.Floor(a.Y + (b.Y - a.Y) * (x - a.X) / (b.X - a.X));
            if (y >= 0 && y < Size.Y - 1) pair(BoundaryIndex(x, y), x, y, BoundaryIndex(x, y + 1), x, y + 1);
        }
        for (int y = (int)Math.Ceiling(Math.Min(a.Y, b.Y)); y < Math.Max(a.Y, b.Y); y++)
        {
            int x = (int)Math.Floor(a.X + (b.X - a.X) * (y - a.Y) / (b.Y - a.Y));
            if (y >= 0 && y < Size.Y) pair(BoundaryIndex(x, y), x, y, BoundaryIndex(x + 1, y), x + 1, y);
        }
    }

    /// A área (km²) que o plano tira do selecionado (só num redesenho de borda).
    public double PlanFreedKm2(TerritoryBoundaryPlan plan) => plan.Freed.Sum(p => RowCellKm2(p / Size.X, Size.X, Size.Y));
}
