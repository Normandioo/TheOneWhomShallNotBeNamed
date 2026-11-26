using System;
using System.Collections.Generic;
using System.Linq;
using Godot;

namespace Evron;

/// As linhas do pincel de fronteira como a TELA as usa: perto de uma delas, cada ponto da tela só olha os pixels do mapa do mesmo lado
/// (shaders/political.gdshaderinc), então a borda aparece em cima da linha desenhada, mais fina que o pixel do mapa. Vale só o trecho
/// que HOJE ainda separa o dono da linha de outro: pintar por cima, apagar ou desfazer tiram a linha dali sem ninguém precisar avisar.
public partial class Territory
{
    private const int WallCell = 4;          // pixels do mapa por célula do índice (as mesmas 1024×512 células no mapa de 4096×2048)
    private const float WallPad = 2.0f;      // um ponto olha pixels do mapa a até 2 de distância: a célula lista as linhas até aí
    private const float WallTolerance = 0.03f;  // pixels do mapa (~300 m): o quanto a linha enviada pode se afastar da curva
    private const double WallReach = 1.5;    // pixels do mapa em volta de um trecho que dizem se ele ainda vale

    /// layers: as camadas mostradas. pending: o plano do pincel de fronteira que está na prévia (vale como já aplicado), ou null.
    /// Devolve {count} e, se count > 0, {index: Image RGF (início, quantidade), segments: Image RGBAF de 1024 de largura (x0, y0, x1, y1
    /// em pixels do mapa, o centro do pixel i em i + 0,5)}.
    public static Godot.Collections.Dictionary Walls(Godot.Collections.Array layers, TerritoryBoundaryPlan? pending)
    {
        var segments = new List<(Vector2 A, Vector2 B)>();
        Vector2I size = Vector2I.Zero;
        // Duas linhas correndo juntas se anulariam na tela (cruzar as duas = não cruzar nenhuma): ali vale só a mais nova. A prévia vai
        // primeiro, depois as camadas na ordem recebida e, em cada uma, do traço mais novo para o mais antigo.
        var taken = new WallPieces();
        var shown = layers.Select(v => v.As<Territory>()).Where(l => l != null)
            .OrderBy(l => pending != null && pending.Map == l ? 0 : 1).ToArray();
        foreach (var layer in shown)
        {
            size = layer.Size;
            var plan = pending != null && pending.Map == layer ? pending : null;
            HashSet<int>? claimed = plan == null ? null : plan.Next.Pixels.ToHashSet();
            HashSet<int>? freed = plan?.Previous?.Pixels.ToHashSet();
            HashSet<int>? erased = plan?.Freed.ToHashSet();
            int OwnerOf(int p) => claimed != null && claimed.Contains(p) ? plan!.Next.Target
                : erased != null && erased.Contains(p) ? 0
                : freed != null && freed.Contains(p) ? plan!.Next.Source : layer.Get(p);
            if (plan != null) layer.AliveWall(plan.Next, OwnerOf, taken, segments);
            foreach (var path in layer._boundaries.Values.Reverse())
                if (plan == null || path.Id != plan.Next.Id)
                    layer.AliveWall(path, OwnerOf, taken, segments);
        }
        var result = new Godot.Collections.Dictionary { ["count"] = segments.Count };
        if (segments.Count > 0) PackWalls(segments, size, result);
        return result;
    }

    /// A curva do traço em pedaços de até um pixel do mapa, na grade de centros inteiros (a mesma da pintura).
    private List<(double X, double Y)> GridCurve(Vector3[] controls)
    {
        var curve = SmoothBoundary(controls);
        if (curve.Length < 2) return new List<(double X, double Y)>();
        // A curva em pedaços de até um pixel do mapa, na grade de centros inteiros (a mesma da pintura), sem saltar na longitude 180°.
        var points = new List<(double X, double Y)> { BoundaryGrid(curve[0]) };
        for (int i = 1; i < curve.Length; i++)
        {
            var from = points[^1];
            var to = BoundaryGrid(curve[i]);
            to.X -= Size.X * Math.Round((to.X - from.X) / Size.X);
            int steps = Math.Max(1, (int)Math.Ceiling(Math.Max(Math.Abs(to.X - from.X), Math.Abs(to.Y - from.Y))));
            for (int s = 1; s <= steps; s++)
                points.Add((from.X + (to.X - from.X) * s / steps, from.Y + (to.Y - from.Y) * s / steps));
        }
        return points;
    }

    /// Pedaços de linha por célula de um pixel (a longitude dá a volta), para saber se um pedaço já tem outra linha correndo junto.
    private sealed class WallPieces
    {
        private readonly Dictionary<(int, int), List<((double X, double Y) A, (double X, double Y) B)>> _cells = new();

        private static int Wrap(int x, int width) => (x % width + width) % width;

        public void Add((double X, double Y) a, (double X, double Y) b, int width)
        {
            var key = (Wrap((int)Math.Floor((a.X + b.X) / 2), width), (int)Math.Floor((a.Y + b.Y) / 2));
            if (!_cells.TryGetValue(key, out var list)) _cells[key] = list = new();
            list.Add((a, b));
        }

        /// Há um pedaço quase paralelo (até 45°) a menos de WallReach do meio de a-b? Um que cruza ou chega de lado não conta.
        public bool Along((double X, double Y) a, (double X, double Y) b, int width)
        {
            if (_cells.Count == 0) return false;
            double mx = (a.X + b.X) / 2, my = (a.Y + b.Y) / 2, ux = b.X - a.X, uy = b.Y - a.Y;
            int span = (int)Math.Ceiling(WallReach) + 1;
            for (int dy = -span; dy <= span; dy++)
            for (int dx = -span; dx <= span; dx++)
            {
                if (!_cells.TryGetValue((Wrap((int)Math.Floor(mx) + dx, width), (int)Math.Floor(my) + dy), out var list)) continue;
                foreach (var (c, d) in list)
                {
                    double vx = d.X - c.X, vy = d.Y - c.Y, length = vx * vx + vy * vy;
                    double dot = ux * vx + uy * vy;
                    if (length < 1e-12 || dot * dot < 0.5 * length * (ux * ux + uy * uy)) continue;
                    double px = mx - c.X, py = my - c.Y;
                    px -= width * Math.Round(px / width);
                    double t = Math.Clamp((px * vx + py * vy) / length, 0, 1);
                    if ((px - t * vx) * (px - t * vx) + (py - t * vy) * (py - t * vy) <= WallReach * WallReach) return true;
                }
            }
            return false;
        }
    }

    private void AliveWall(TerritoryBoundary path, Func<int, int> ownerOf, WallPieces taken, List<(Vector2, Vector2)> into)
    {
        var points = GridCurve(path.Points);
        if (points.Count < 2) return;
        var kept = new List<int>();
        // Um pedaço vale enquanto a linha, ali, ainda separa o país de quem não é ele: de um lado há pixel dele e do outro nenhum. Não
        // importa quem pintou cada pixel (o traço que só ajusta uma área feita com o pincel redondo vale igual). Os lados são os mesmos
        // da tela: dois pontos estão do mesmo lado se o segmento entre eles cruza a linha um número par de vezes, o que continua certo
        // num bico mais fino que um pixel do mapa (ali um dos lados pode não ter pixel nenhum).
        var buckets = new Dictionary<(int, int), List<int>>();
        for (int i = 0; i + 1 < points.Count; i++)
        {
            var key = ((int)Math.Floor(points[i].X), (int)Math.Floor(points[i].Y));
            if (!buckets.TryGetValue(key, out var list)) buckets[key] = list = new List<int>();
            list.Add(i);
        }
        var near = new List<int>();
        (int, int) gathered = (int.MinValue, int.MinValue);  // pedaços seguidos caem na mesma célula: a lista dos vizinhos serve para vários
        bool Holds(int piece)
        {
            var (a, b) = (points[piece], points[piece + 1]);
            (double X, double Y) middle = ((a.X + b.X) / 2, (a.Y + b.Y) / 2);
            double length = Math.Sqrt((b.X - a.X) * (b.X - a.X) + (b.Y - a.Y) * (b.Y - a.Y));
            if (length < 1e-9) return false;
            (double X, double Y) beside = (middle.X - (b.Y - a.Y) / length * 1e-3, middle.Y + (b.X - a.X) / length * 1e-3);
            var home = ((int)Math.Floor(middle.X), (int)Math.Floor(middle.Y));
            if (home != gathered)
            {
                gathered = home;
                near.Clear();
                int span = (int)Math.Ceiling(WallReach) + 1;  // os pedaços (de até 1 pixel) que podem passar entre este ponto e um da janela
                for (int dy = -span; dy <= span; dy++)
                for (int dx = -span; dx <= span; dx++)
                    if (buckets.TryGetValue((home.Item1 + dx, home.Item2 + dy), out var list)) near.AddRange(list);
            }
            Span<bool> owned = stackalloc bool[2];
            for (int y = (int)Math.Ceiling(middle.Y - WallReach); y <= (int)Math.Floor(middle.Y + WallReach); y++)
            {
                if (y < 0 || y >= Size.Y) continue;
                for (int x = (int)Math.Ceiling(middle.X - WallReach); x <= (int)Math.Floor(middle.X + WallReach); x++)
                {
                    if ((x - middle.X) * (x - middle.X) + (y - middle.Y) * (y - middle.Y) > WallReach * WallReach) continue;
                    if (ownerOf(BoundaryIndex(x, y)) != path.Target) continue;
                    int side = 0;
                    foreach (int other in near)
                        if (Crosses(beside, (x, y), points[other], points[other + 1])) side ^= 1;
                    owned[side] = true;
                    if (owned[0] && owned[1]) return false;  // o país dos dois lados: a linha passa por dentro dele
                }
            }
            return owned[0] != owned[1];
        }
        var run = new List<Vector2>();
        for (int i = 0; i < points.Count; i++)
        {
            bool keep = i + 1 < points.Count && !taken.Along(points[i], points[i + 1], Size.X) && Holds(i);
            if (keep)
            {
                kept.Add(i);
                if (run.Count == 0) run.Add(Texel(points[i]));
                run.Add(Texel(points[i + 1]));
            }
            else if (run.Count > 0)
            {
                Simplify(run, into);
                run.Clear();
            }
        }
        foreach (int i in kept) taken.Add(points[i], points[i + 1], Size.X);  // só depois: a linha não disputa com ela mesma
    }

    /// Todo o traço antigo corre junto do novo (então não diz mais nada)?
    private bool CoveredBy(Vector3[] old, Vector3[] next)
    {
        var over = new WallPieces();
        var line = GridCurve(next);
        for (int i = 0; i + 1 < line.Count; i++) over.Add(line[i], line[i + 1], Size.X);
        var points = GridCurve(old);
        return points.Count > 1 && Enumerable.Range(0, points.Count - 1).All(i => over.Along(points[i], points[i + 1], Size.X));
    }

    /// O segmento p-q cruza o segmento a-b?
    private static bool Crosses((double X, double Y) p, (double X, double Y) q, (double X, double Y) a, (double X, double Y) b)
    {
        static double Cross(double ux, double uy, double vx, double vy) => ux * vy - uy * vx;
        double dx = q.X - p.X, dy = q.Y - p.Y, ex = b.X - a.X, ey = b.Y - a.Y;
        return (Cross(dx, dy, a.X - p.X, a.Y - p.Y) > 0) != (Cross(dx, dy, b.X - p.X, b.Y - p.Y) > 0) &&
               (Cross(ex, ey, p.X - a.X, p.Y - a.Y) > 0) != (Cross(ex, ey, q.X - a.X, q.Y - a.Y) > 0);
    }

    // Da grade da pintura (centros inteiros, com o desempate de BoundaryGrid) para a do desenho (centros em i + 0,5).
    private static Vector2 Texel((double X, double Y) g) => new((float)(g.X + 0.499999), (float)(g.Y + 0.499997));

    /// Douglas-Peucker: a curva suavizada tem muito mais pontos que o necessário, e cada trecho custa na tela.
    private static void Simplify(List<Vector2> run, List<(Vector2, Vector2)> into)
    {
        var keep = new bool[run.Count];
        keep[0] = keep[^1] = true;
        var stack = new Stack<(int, int)>();
        stack.Push((0, run.Count - 1));
        while (stack.Count > 0)
        {
            var (a, b) = stack.Pop();
            Vector2 line = run[b] - run[a];
            int far = -1;
            float worst = WallTolerance;
            for (int i = a + 1; i < b; i++)
            {
                float t = line.LengthSquared() > 0f ? Mathf.Clamp((run[i] - run[a]).Dot(line) / line.LengthSquared(), 0f, 1f) : 0f;
                float d = run[i].DistanceTo(run[a] + line * t);
                if (d > worst) (worst, far) = (d, i);
            }
            // Um trecho comprido demais espalharia a linha por muitas células do índice.
            if (far < 0 && line.Length() > 2 * WallCell && b - a > 1) far = (a + b) / 2;
            if (far < 0) continue;
            keep[far] = true;
            stack.Push((a, far));
            stack.Push((far, b));
        }
        int last = 0;
        for (int i = 1; i < run.Count; i++)
            if (keep[i])
            {
                into.Add((run[last], run[i]));
                last = i;
            }
    }

    private static void PackWalls(List<(Vector2 A, Vector2 B)> segments, Vector2I size, Godot.Collections.Dictionary result)
    {
        int columns = Math.Max(1, size.X / WallCell), rows = Math.Max(1, size.Y / WallCell);
        var cells = new Dictionary<int, List<int>>();
        for (int s = 0; s < segments.Count; s++)
        {
            var (a, b) = segments[s];
            var low = a.Min(b) - new Vector2(WallPad, WallPad);
            var high = a.Max(b) + new Vector2(WallPad, WallPad);
            for (int cy = Math.Max(0, (int)Math.Floor(low.Y / WallCell)); cy <= Math.Min(rows - 1, (int)Math.Floor(high.Y / WallCell)); cy++)
            for (int cx = (int)Math.Floor(low.X / WallCell); cx <= (int)Math.Floor(high.X / WallCell); cx++)
            {
                int cell = cy * columns + ((cx % columns) + columns) % columns;
                if (!cells.TryGetValue(cell, out var list)) cells[cell] = list = new List<int>();
                list.Add(s);
            }
        }
        var index = new float[columns * rows * 2];
        int total = cells.Values.Sum(l => l.Count), height = Math.Max(1, (total + 1023) / 1024);
        var data = new float[1024 * height * 4];
        int cursor = 0;
        foreach (var (cell, list) in cells)
        {
            index[cell * 2] = cursor;
            index[cell * 2 + 1] = list.Count;
            foreach (int s in list)
            {
                var (a, b) = segments[s];
                float shift = size.X * MathF.Floor(a.X / size.X);  // o começo sempre dentro do mapa; o fim acompanha
                data[cursor * 4] = a.X - shift;
                data[cursor * 4 + 1] = a.Y;
                data[cursor * 4 + 2] = b.X - shift;
                data[cursor * 4 + 3] = b.Y;
                cursor++;
            }
        }
        result["index"] = FloatImage(columns, rows, Image.Format.Rgf, index);
        result["segments"] = FloatImage(1024, height, Image.Format.Rgbaf, data);
        result["longest"] = cells.Values.Max(l => l.Count);
    }

    private static Image FloatImage(int width, int height, Image.Format format, float[] values)
    {
        var bytes = new byte[values.Length * sizeof(float)];
        Buffer.BlockCopy(values, 0, bytes, 0, bytes.Length);
        return Image.CreateFromData(width, height, false, format, bytes);
    }

    /// Rascunho -> cadastro novo: as linhas desenhadas no rascunho passam para esta camada, com os pixels que ficaram dele (depois de
    /// TakeFrom). Sem isso o país novo perderia o traço exato.
    public void AdoptBoundaries(Territory draft, int draftOwner, int owner)
    {
        bool any = false;
        foreach (var path in draft._boundaries.Values.Where(p => p.Target == draftOwner).OrderBy(p => p.Id).ToArray())
        {
            var pixels = path.Pixels.Where(p => Get(p) == owner).ToArray();  // pode ficar vazio (um redesenho que só tirou área)
            int id = _nextBoundary;
            SetBoundary(id, new TerritoryBoundary(id, 0, owner, path.Points, pixels));
            any = true;
        }
        if (any) Touch();
    }
}
