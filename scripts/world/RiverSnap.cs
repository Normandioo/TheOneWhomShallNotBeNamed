using System;
using System.Collections.Generic;
using Godot;

namespace Evron;

/// "Grudar no rio" do lápis de fronteira: os pontos do traço perto de um rio vão para o leito, e entre dois deles a linha anda pela rede
/// de rios (todas as curvas). Os trechos são os que a tela desenha no satélite e em "Rios em destaque" (rivers_indexed.rgbaf,
/// tools/build_indexed_rivers.py). Lê do arquivo só as células por onde o traço passa.
public partial class RiverSnap : RefCounted
{
    private const int GridW = 1024, GridH = 512;
    private const double R = 6371.0;
    public const double MaxReachKm = 20.0;  // a célula do índice garante todos os trechos até 20,5 km
    private const double SameKm = 0.1;      // pontas de trecho a menos disto são o mesmo nó

    private record struct V(double X, double Y, double Z)
    {
        public static V From(Vector3 v) => new V(v.X, v.Y, v.Z).Unit();
        public static V operator +(V a, V b) => new(a.X + b.X, a.Y + b.Y, a.Z + b.Z);
        public static V operator -(V a, V b) => new(a.X - b.X, a.Y - b.Y, a.Z - b.Z);
        public static V operator *(V a, double s) => new(a.X * s, a.Y * s, a.Z * s);
        public double Dot(V b) => X * b.X + Y * b.Y + Z * b.Z;
        public V Unit() => this * (1.0 / Math.Sqrt(Dot(this)));
        public double Km(V b) => R * Math.Sqrt((this - b).Dot(this - b));  // corda: igual ao arco nestas distâncias
        public Vector3 ToVector3() => new((float)X, (float)Y, (float)Z);
    }

    private sealed class Net
    {
        public readonly List<V> Nodes = new();
        public readonly List<List<int>> Links = new();
        public readonly List<(int A, int B)> Segments = new();
        private readonly Dictionary<(int, int, int), List<int>> _hash = new();
        private readonly HashSet<(int, int)> _seen = new();

        private int Node(V p)
        {
            int x = (int)Math.Floor(p.X * R / SameKm), y = (int)Math.Floor(p.Y * R / SameKm), z = (int)Math.Floor(p.Z * R / SameKm);
            for (int dx = -1; dx <= 1; dx++)
                for (int dy = -1; dy <= 1; dy++)
                    for (int dz = -1; dz <= 1; dz++)
                        if (_hash.TryGetValue((x + dx, y + dy, z + dz), out var near))
                            foreach (int n in near)
                                if (Nodes[n].Km(p) < SameKm) return n;
            if (!_hash.TryGetValue((x, y, z), out var list)) _hash[(x, y, z)] = list = new();
            list.Add(Nodes.Count);
            Nodes.Add(p);
            Links.Add(new());
            return Nodes.Count - 1;
        }

        public void Add(V from, V to)
        {
            int a = Node(from), b = Node(to);
            if (a == b || !_seen.Add((Math.Min(a, b), Math.Max(a, b)))) return;  // o mesmo trecho está em várias células
            Links[a].Add(b);
            Links[b].Add(a);
            Segments.Add((a, b));
        }
    }

    private record struct Hit(int Segment, V At);

    private static V Dir(double u, double v)
    {
        double lon = (u - 0.5) * Math.Tau, lat = (0.5 - v) * Math.PI;
        return new V(Math.Cos(lat) * Math.Sin(lon), Math.Sin(lat), Math.Cos(lat) * Math.Cos(lon));
    }

    private static int Cell(V p)
    {
        double u = Math.Atan2(p.X, p.Z) / Math.Tau + 0.5, v = 0.5 - Math.Asin(Math.Clamp(p.Y, -1, 1)) / Math.PI;
        return Math.Clamp((int)(v * GridH), 0, GridH - 1) * GridW + Math.Clamp((int)(u * GridW), 0, GridW - 1);
    }

    /// O traço grudado nos rios do atlas. Ponto sem rio a até reachKm fica onde foi desenhado. Sem o arquivo, devolve o próprio traço.
    public static Vector3[] Snap(string atlasPath, Vector3[] stroke, double reachKm, int maxPoints)
    {
        using var file = FileAccess.Open(atlasPath, FileAccess.ModeFlags.Read);
        if (file == null || stroke.Length < 2 || file.Get32() != 0x32525645) return stroke;
        reachKm = Math.Min(reachKm, MaxReachKm);

        var net = new Net();
        var loaded = new HashSet<int>();
        void Load(int cell)
        {
            if (!loaded.Add(cell)) return;
            file.Seek(8UL + (ulong)cell * 16);
            int start = (int)file.GetFloat(), count = (int)file.GetFloat();
            if (count == 0) return;
            file.Seek(8UL + (ulong)start * 16);
            var bytes = file.GetBuffer(count * 32L);
            for (int i = 0; i + 32 <= bytes.Length; i += 32)
            {
                double u = BitConverter.ToSingle(bytes, i), v = BitConverter.ToSingle(bytes, i + 4);
                net.Add(Dir(u, v), Dir(u + BitConverter.ToSingle(bytes, i + 8), v + BitConverter.ToSingle(bytes, i + 12)));
            }
        }

        // O traço com pontos intermediários a cada ~10 km: pegam as células do caminho e seguram a linha no rio entre amostras distantes.
        var samples = new List<(V Raw, bool Own)>();
        for (int i = 0; i < stroke.Length; i++)
        {
            var p = V.From(stroke[i]);
            if (i > 0)
            {
                var from = V.From(stroke[i - 1]);
                int steps = (int)Math.Ceiling(from.Km(p) / 10.0);
                for (int k = 1; k < steps; k++) samples.Add(((from + (p - from) * ((double)k / steps)).Unit(), false));
            }
            samples.Add((p, true));
        }
        foreach (var (raw, _) in samples) Load(Cell(raw));

        Hit? Nearest(V p)
        {
            Hit? best = null;
            double bestKm = reachKm;
            for (int s = 0; s < net.Segments.Count; s++)
            {
                V a = net.Nodes[net.Segments[s].A], d = net.Nodes[net.Segments[s].B] - a;
                // shortcut: busca linear nos trechos do corredor (alguns milhares); um índice local se o traço longo travar.
                if (Math.Abs(a.X - p.X) * R > 60 || Math.Abs(a.Y - p.Y) * R > 60 || Math.Abs(a.Z - p.Z) * R > 60) continue;
                var at = (a + d * Math.Clamp((p - a).Dot(d) / Math.Max(d.Dot(d), 1e-18), 0, 1)).Unit();
                double km = at.Km(p);
                if (km < bestKm) { bestKm = km; best = new Hit(s, at); }
            }
            return best;
        }

        var line = new List<V>();
        void Push(V p)
        {
            if (line.Count > 0 && line[^1].Km(p) < SameKm) return;
            // Voltar a um ponto por onde acabou de passar é uma entrada num afluente (ou um vaivém da mão): a volta inteira sai.
            double back = 0;
            for (int i = line.Count - 2; i >= 0 && back <= 4 * reachKm; i--)
            {
                back += line[i].Km(line[i + 1]);
                if (line[i].Km(p) < SameKm)
                {
                    line.RemoveRange(i + 1, line.Count - i - 1);
                    return;
                }
            }
            line.Add(p);
        }

        Hit? previous = null;
        foreach (var (raw, own) in samples)
        {
            var hit = Nearest(raw);
            if (hit == null)
            {
                if (own)  // só um ponto desenhado fora do alcance solta a linha do rio
                {
                    Push(raw);
                    previous = null;
                }
                continue;
            }
            if (previous is { } last && last.Segment != hit.Value.Segment)
                foreach (int n in Route(net, last, hit.Value, 3 * last.At.Km(hit.Value.At) + 2 * reachKm))
                    Push(net.Nodes[n]);
            Push(hit.Value.At);
            previous = hit;
        }

        // Pontos demais para guardar: rareia por igual, mantendo as pontas.
        while (line.Count > maxPoints)
            for (int i = line.Count - 2; i > 0; i -= 2) line.RemoveAt(i);
        if (line.Count < 2) return stroke;
        var result = new Vector3[line.Count];
        for (int i = 0; i < result.Length; i++) result[i] = line[i].ToVector3();
        return result;
    }

    /// Os nós do caminho mais curto pela rede entre dois pontos dela; vazio se não há um de até limitKm (aí a linha vai direto).
    private static List<int> Route(Net net, Hit from, Hit to, double limitKm)
    {
        var cost = new Dictionary<int, double>();
        var came = new Dictionary<int, int>();
        var queue = new PriorityQueue<int, double>();
        void Reach(int node, double km, int parent)
        {
            if (km > limitKm || (cost.TryGetValue(node, out var old) && old <= km)) return;
            cost[node] = km;
            came[node] = parent;
            queue.Enqueue(node, km);
        }
        var (a, b) = net.Segments[from.Segment];
        var (c, d) = net.Segments[to.Segment];
        Reach(a, from.At.Km(net.Nodes[a]), -1);
        Reach(b, from.At.Km(net.Nodes[b]), -1);
        int end = -1;
        double best = limitKm;
        while (queue.TryDequeue(out int node, out double km) && km < best)
        {
            if (km > cost[node]) continue;
            if (node == c || node == d)
            {
                double total = km + net.Nodes[node].Km(to.At);
                if (total < best) { best = total; end = node; }
            }
            foreach (int next in net.Links[node]) Reach(next, km + net.Nodes[node].Km(net.Nodes[next]), node);
        }
        var path = new List<int>();
        for (int n = end; n >= 0; n = came[n]) path.Add(n);
        path.Reverse();
        return path;
    }
}
