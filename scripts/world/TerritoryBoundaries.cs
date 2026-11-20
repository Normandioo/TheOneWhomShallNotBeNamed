using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using Godot;

namespace Evron;

internal sealed record TerritoryBoundary(int Id, int Source, int Target, Vector3[] Points, int[] Pixels)
{
    public long Bytes => Points.Length * 12L + Pixels.Length * 4L;
}

public partial class Territory
{
    private sealed record CutPart(List<int> Pixels, bool MeetsTarget, int PreviousPixels, double Area);

    private const int MaxBoundaryPoints = 256;
    private const int BoundaryFormat = 1;
    private static readonly (int X, int Y)[] BoundaryNeighbors = { (-1, 0), (1, 0), (0, -1), (0, 1) };
    private Dictionary<int, TerritoryBoundary> _boundaries = new();
    private byte[]? _packedBoundaries;
    private int _nextBoundary = 1;

    public Godot.Collections.Array<Godot.Collections.Dictionary> BoundariesFor(int owner)
    {
        var result = new Godot.Collections.Array<Godot.Collections.Dictionary>();
        foreach (var path in _boundaries.Values.OrderBy(p => p.Id))
        {
            if (path.Target == owner)
                result.Add(new Godot.Collections.Dictionary { ["id"] = path.Id, ["source"] = path.Source, ["points"] = path.Points });
        }
        return result;
    }

    public void ForgetOwnerBoundaries(int owner)
    {
        var ids = _boundaries.Values.Where(p => p.Source == owner || p.Target == owner).Select(p => p.Id).ToArray();
        foreach (int id in ids) SetBoundary(id, null);
        if (ids.Length > 0) Touch();
    }

    /// Arredonda os cantos em duas passagens sobre a esfera, com as pontas fixas. Os controles são guardados separadamente.
    public Vector3[] SmoothBoundary(Vector3[] controls)
    {
        var curve = controls;
        for (int pass = 0; pass < 2 && curve.Length > 2; pass++)
        {
            var next = new Vector3[curve.Length * 2];
            next[0] = curve[0];
            next[^1] = curve[^1];
            for (int i = 0; i < curve.Length - 1; i++)
            {
                next[i * 2 + 1] = curve[i].Lerp(curve[i + 1], 0.25f).Normalized();
                next[i * 2 + 2] = curve[i].Lerp(curve[i + 1], 0.75f).Normalized();
            }
            curve = next;
        }
        return curve;
    }

    /// Descobre o país cortado e a parte ligada ao país selecionado, sem alterar o mapa.
    public Godot.Collections.Dictionary PlanBoundaryClaim(int target, Vector3[] controls, int id)
    {
        if (_stroke != null || !ValidOwner(target)) return RefuseBoundary("Selecione um país no mapa.");
        if (!ValidBoundaryPoints(controls))
            return RefuseBoundary("Desenhe uma linha contínua com pelo menos dois pontos distintos.");

        _boundaries.TryGetValue(id, out var previous);
        if (id != 0 && (previous == null || previous.Target != target))
            return RefuseBoundary("Esta fronteira não pertence ao país selecionado.");

        int length = Size.X * Size.Y;
        BitArray? restored = null;
        if (previous != null)
        {
            restored = new BitArray(length);
            foreach (int p in previous.Pixels)
            {
                if (Get(p) != previous.Target)
                    return RefuseBoundary("Parte desta divisão foi repintada. Desfaça a pintura antes de remodelar o traço.");
                restored[p] = true;
            }
        }

        int OwnerBefore(int p) => restored != null && restored[p] ? previous!.Source : Get(p);
        var edges = RasterizeBoundary(SmoothBoundary(controls));
        var labels = new int[length];
        var parts = new List<CutPart>();
        var cuts = new Dictionary<int, (HashSet<int> Parts, int Crossings)>();
        var rowArea = Enumerable.Range(0, Size.Y).Select(y => Math.Cos(Math.PI * (0.5 - (y + 0.5) / Size.Y))).ToArray();
        var terrain = _terrain!;

        int LabelPart(int start, int owner)
        {
            if (labels[start] != 0) return labels[start];
            int label = parts.Count + 1;
            var pixels = new List<int> { start };
            labels[start] = label;
            bool meetsTarget = false;
            int previousPixels = 0;
            double area = 0;
            for (int i = 0; i < pixels.Count; i++)
            {
                int p = pixels[i];
                area += rowArea[p / Size.X];
                if (restored != null && restored[p]) previousPixels++;
                foreach (var (x, y) in BoundaryNeighbors)
                {
                    int q = terrain.Neighbor(p, x, y);
                    if (q < 0 || labels[q] == label) continue;
                    int neighbor = OwnerBefore(q);
                    if (neighbor == target) meetsTarget = true;
                    if (neighbor != owner || labels[q] != 0 || edges.Contains(BoundaryEdge(p, q))) continue;
                    labels[q] = label;
                    pixels.Add(q);
                }
            }
            parts.Add(new CutPart(pixels, meetsTarget, previousPixels, area));
            return label;
        }

        foreach (long edge in edges)
        {
            int p = (int)(edge >> 32), q = (int)edge;
            int owner = OwnerBefore(p);
            if (owner == 0 || owner == target || OwnerBefore(q) != owner || (previous != null && owner != previous.Source)) continue;
            int left = LabelPart(p, owner), right = LabelPart(q, owner);
            if (left == right) continue;
            if (!cuts.TryGetValue(owner, out var cut)) cut = (new HashSet<int>(), 0);
            cut.Parts.Add(left);
            cut.Parts.Add(right);
            cuts[owner] = (cut.Parts, cut.Crossings + 1);
        }
        if (cuts.Count == 0) return RefuseBoundary("Atravesse o país vizinho de uma borda à outra para separar um pedaço.");

        // As pontas podem passar pela borda de um terceiro país. Só usa o corte claramente predominante.
        var ranked = cuts.OrderByDescending(c => c.Value.Crossings).ToArray();
        if (ranked.Length > 1 && ranked[0].Value.Crossings < 2 * ranked[1].Value.Crossings)
            return RefuseBoundary("O traço divide mais de um país. Desenhe dentro de um vizinho por vez.");
        int source = ranked[0].Key;
        var separated = ranked[0].Value.Parts;

        var candidates = separated.Select(label => parts[label - 1]).Where(p => p.MeetsTarget)
            .OrderByDescending(p => p.PreviousPixels).ThenBy(p => p.Area).ToArray();
        if (candidates.Length == 0) return RefuseBoundary("O pedaço separado precisa encostar no país selecionado.");

        // Mais de um lado encosta no selecionado: nada é escolhido às escondidas; o plano leva todos e quem decide é o usuário (Choose).
        var choices = candidates.Select(c => { var px = c.Pixels.ToArray(); Array.Sort(px); return px; }).ToArray();
        var plan = new TerritoryBoundaryPlan
        {
            Map = this,
            Version = Version,
            Previous = previous,
            Choices = choices,
            Next = new TerritoryBoundary(id == 0 ? _nextBoundary : id, source, target, controls.ToArray(), choices[0])
        };
        return new Godot.Collections.Dictionary { ["plan"] = plan };
    }

    /// A camada como ficaria com o plano aplicado (RG8, como OwnersImage), para a prévia. Não muda nada.
    public Image PreviewImage(TerritoryBoundaryPlan plan)
    {
        var bytes = (byte[])B.Clone();
        void Set(int p, int owner) { bytes[p * 2] = (byte)owner; bytes[p * 2 + 1] = (byte)(owner >> 8); }
        foreach (int p in plan.Previous?.Pixels ?? Array.Empty<int>()) Set(p, plan.Next.Source);
        foreach (int p in plan.Next.Pixels) Set(p, plan.Next.Target);
        return Image.CreateFromData(Size.X, Size.Y, false, Image.Format.Rg8, bytes);
    }

    /// A área (km²) que o plano passa para o selecionado.
    public double PlanAreaKm2(TerritoryBoundaryPlan plan) => plan.Next.Pixels.Sum(p => RowCellKm2(p / Size.X, Size.X, Size.Y));

    public TerritoryEdit? ApplyBoundary(TerritoryBoundaryPlan plan)
    {
        if (plan.Map != this || plan.Version != Version || _stroke != null) return null;
        var next = plan.Next;
        var pixels = new List<int>();
        var before = new List<ushort>();
        // Mescla duas listas ordenadas para escrever cada célula no máximo uma vez.
        int[] oldPixels = plan.Previous?.Pixels ?? Array.Empty<int>();
        int i = 0, j = 0;
        while (i < oldPixels.Length || j < next.Pixels.Length)
        {
            int oldPixel = i < oldPixels.Length ? oldPixels[i] : int.MaxValue;
            int newPixel = j < next.Pixels.Length ? next.Pixels[j] : int.MaxValue;
            int pixel = Math.Min(oldPixel, newPixel);
            int owner = pixel == newPixel ? next.Target : next.Source;
            if (pixel == oldPixel) i++;
            if (pixel == newPixel) j++;
            int current = Get(pixel);
            if (current == owner) continue;
            pixels.Add(pixel);
            before.Add((ushort)current);
            Put(pixel, owner);
        }
        SetBoundary(next.Id, next);
        Touch();
        return new TerritoryEdit(this, pixels.ToArray(), before.ToArray(), plan.Previous, next);
    }

    private HashSet<long> RasterizeBoundary(Vector3[] curve)
    {
        var edges = new HashSet<long>();
        var previous = BoundaryGrid(curve[0]);
        for (int i = 1; i < curve.Length; i++)
        {
            var a = curve[i - 1];
            var b = curve[i];
            int steps = Math.Max(1, (int)Math.Ceiling(EvronGeo.Angle(a, b) * Size.Y * 2 / Math.PI));
            for (int s = 1; s <= steps; s++)
            {
                var next = BoundaryGrid(s == steps ? b : a.Slerp(b, (float)s / steps).Normalized());
                // Desenrola a longitude antes de cruzar as linhas da grade.
                next.X -= Size.X * Math.Round((next.X - previous.X) / Size.X);
                for (int x = (int)Math.Ceiling(Math.Min(previous.X, next.X)); x < Math.Max(previous.X, next.X); x++)
                {
                    int y = (int)Math.Floor(previous.Y + (next.Y - previous.Y) * (x - previous.X) / (next.X - previous.X));
                    if (y >= 0 && y < Size.Y - 1) edges.Add(BoundaryEdge(BoundaryIndex(x, y), BoundaryIndex(x, y + 1)));
                }
                for (int y = (int)Math.Ceiling(Math.Min(previous.Y, next.Y)); y < Math.Max(previous.Y, next.Y); y++)
                {
                    int x = (int)Math.Floor(previous.X + (next.X - previous.X) * (y - previous.Y) / (next.Y - previous.Y));
                    if (y >= 0 && y < Size.Y) edges.Add(BoundaryEdge(BoundaryIndex(x, y), BoundaryIndex(x + 1, y)));
                }
                previous = next;
            }
        }
        return edges;
    }

    private (double X, double Y) BoundaryGrid(Vector3 n)
    {
        var (lat, lon) = EvronGeo.LatLon(n);
        // Centros em coordenadas inteiras. O deslocamento resolve empates sobre um centro de modo consistente.
        return ((lon / 360.0 + 0.5) * Size.X - 0.499999, (0.5 - lat / 180.0) * Size.Y - 0.499997);
    }

    private int BoundaryIndex(int x, int y) => y * Size.X + (x % Size.X + Size.X) % Size.X;
    private static long BoundaryEdge(int a, int b) => ((long)Math.Min(a, b) << 32) | (uint)Math.Max(a, b);
    private static bool ValidOwner(int owner) => owner > 0 && owner <= MaxOwner;
    private static Godot.Collections.Dictionary RefuseBoundary(string message) => new() { ["message"] = message };

    private static bool ValidBoundaryPoints(Vector3[] points)
    {
        if (points.Length < 2 || points.Length > MaxBoundaryPoints) return false;
        for (int i = 0; i < points.Length; i++)
        {
            if (!points[i].IsFinite() || !points[i].IsNormalized()) return false;
            if (i > 0 && (points[i].IsEqualApprox(points[i - 1]) || points[i].Dot(points[i - 1]) < -0.99f)) return false;
        }
        return true;
    }

    internal void SetBoundary(int id, TerritoryBoundary? path)
    {
        if (path == null) _boundaries.Remove(id);
        else _boundaries[id] = path;
        _nextBoundary = Math.Max(_nextBoundary, id + 1);
        _packedBoundaries = null;
    }

    private void ResetBoundaries()
    {
        _boundaries.Clear();
        _packedBoundaries = null;
        _nextBoundary = 1;
    }

    internal byte[]? PackBoundaries()
    {
        if (_boundaries.Count == 0) return null;
        if (_packedBoundaries != null) return _packedBoundaries;
        using var bytes = new MemoryStream();
        using (var stream = new DeflateStream(bytes, CompressionLevel.Fastest, true))
        using (var writer = new BinaryWriter(stream))
        {
            writer.Write(BoundaryFormat);
            writer.Write(_boundaries.Count);
            foreach (var path in _boundaries.Values)
            {
                writer.Write(path.Id);
                writer.Write(path.Source);
                writer.Write(path.Target);
                writer.Write(path.Points.Length);
                foreach (var point in path.Points)
                {
                    writer.Write(point.X);
                    writer.Write(point.Y);
                    writer.Write(point.Z);
                }
                writer.Write(path.Pixels.Length);
                int previous = -1;
                foreach (int p in path.Pixels)
                {
                    writer.Write7BitEncodedInt(p - previous);
                    previous = p;
                }
            }
        }
        return _packedBoundaries = bytes.ToArray();
    }

    private void RestoreBoundaries(byte[]? bytes)
    {
        if (bytes == null)
        {
            ResetBoundaries();
            return;
        }
        using var stream = new DeflateStream(new MemoryStream(bytes), CompressionMode.Decompress);
        using var reader = new BinaryReader(stream);
        if (reader.ReadInt32() != BoundaryFormat) throw new InvalidDataException("Formato de fronteiras incompatível.");
        int count = reader.ReadInt32();
        if (count < 0 || count > Size.X * Size.Y) throw new InvalidDataException("Número de fronteiras inválido.");
        var paths = new Dictionary<int, TerritoryBoundary>();
        int lastId = 0;
        for (int i = 0; i < count; i++)
        {
            int id = reader.ReadInt32(), source = reader.ReadInt32(), target = reader.ReadInt32();
            int pointsCount = reader.ReadInt32();
            if (id <= 0 || id == int.MaxValue || !ValidOwner(source) || !ValidOwner(target) || source == target ||
                pointsCount < 2 || pointsCount > MaxBoundaryPoints)
                throw new InvalidDataException("Identidade ou geometria de fronteira inválida.");
            var points = new Vector3[pointsCount];
            for (int p = 0; p < points.Length; p++) points[p] = new Vector3(reader.ReadSingle(), reader.ReadSingle(), reader.ReadSingle());
            if (!ValidBoundaryPoints(points)) throw new InvalidDataException("Pontos de fronteira inválidos.");

            int pixelsCount = reader.ReadInt32(), length = Size.X * Size.Y;
            if (pixelsCount <= 0 || pixelsCount > length) throw new InvalidDataException("Área de fronteira inválida.");
            var pixels = new int[pixelsCount];
            int previous = -1;
            for (int p = 0; p < pixels.Length; p++)
            {
                int gap = reader.Read7BitEncodedInt();
                if (gap <= 0 || gap >= length - previous) throw new InvalidDataException("Célula de fronteira inválida.");
                pixels[p] = previous += gap;
            }
            if (!paths.TryAdd(id, new TerritoryBoundary(id, source, target, points, pixels)))
                throw new InvalidDataException("Identificador de fronteira duplicado.");
            lastId = Math.Max(lastId, id);
        }
        _boundaries = paths;
        _nextBoundary = lastId + 1;
        _packedBoundaries = bytes;
    }
}
