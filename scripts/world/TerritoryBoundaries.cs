using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Threading.Tasks;
using Godot;

namespace Evron;

internal sealed record TerritoryBoundary(int Id, int Source, int Target, Vector3[] Points, int[] Pixels)
{
    // Pares célula/dono recortados em cada nível abaixo desta fronteira.
    public Dictionary<int, ushort>[] Subdivisions { get; } = { new(), new() };

    public long Bytes => Points.Length * 12L + Pixels.Length * 4L +
        Subdivisions.Sum(level => level.Count * 24L);
}

public partial class Territory
{
    private sealed record CutPart(List<int> Pixels, bool MeetsTarget, int PreviousPixels, double Area);

    private const int MaxBoundaryPoints = 4096;  // um traço longo guarda todas as curvas (o lápis só rareia os pontos acima disto)
    private const int BoundaryFormat = 2;
    private static readonly (int X, int Y)[] BoundaryNeighbors = { (-1, 0), (1, 0), (0, -1), (0, 1) };
    private Dictionary<int, TerritoryBoundary> _boundaries = new();
    private byte[]? _packedBoundaries;
    private int _nextBoundary = 1;
    private Task<Godot.Collections.Dictionary>? _openBoundaryJob;
    private float[]? _boundaryHeights;
    private Territory? _jobMask;
    private long _jobMaskVersion;
    private Territory? _jobTaken;
    private long _jobTakenVersion;
    private int _jobMaskOwner;
    private long _jobVersion;

    /// A thread de trabalho só lê cópias dos buffers que o editor pode alterar.
    public bool BeginOpenBoundary(int target, Vector3[] controls, int id, bool landOnly)
    {
        if (_openBoundaryJob is { IsCompleted: false } || _stroke != null) return false;
        var snapshot = new Territory
        {
            Size = Size,
            B = (byte[])B.Clone(),
            _terrain = _terrain,
            _maskOwner = _maskOwner,
            _nextBoundary = _nextBoundary,
            _boundaryHeights = landOnly ? (float[])_terrain!.H.Clone() : null,
        };
        if (_boundaries.TryGetValue(id, out var previous)) snapshot._boundaries[id] = previous;
        _jobMask = _maskLayer;
        _jobMaskVersion = _maskLayer?.Version ?? 0;
        _jobMaskOwner = _maskOwner;
        _jobVersion = Version;
        if (_maskLayer != null)
            snapshot._maskLayer = new Territory { B = (byte[])_maskLayer.B.Clone() };
        _jobTaken = _takenLayer;
        _jobTakenVersion = _takenLayer?.Version ?? 0;
        if (_takenLayer != null)
        {
            snapshot._takenLayer = new Territory { B = (byte[])_takenLayer.B.Clone() };
            snapshot._takenSelf = _takenSelf;
        }
        var points = controls.ToArray();
        _openBoundaryJob = Task.Run(() =>
        {
            try
            {
                var result = snapshot.PlanStroke(target, points, id, landOnly);
                if (result.TryGetValue("plan", out var value)) value.As<TerritoryBoundaryPlan>().Map = null;
                return result;
            }
            finally
            {
                snapshot._maskLayer?.Dispose();
                snapshot._takenLayer?.Dispose();
                snapshot.Dispose();
            }
        });
        return true;
    }

    /// Vazio enquanto o plano está em cálculo.
    public Godot.Collections.Dictionary PollOpenBoundary()
    {
        if (_openBoundaryJob is not { IsCompleted: true } job) return new();
        _openBoundaryJob = null;
        bool maskChanged = _maskLayer != _jobMask || _maskOwner != _jobMaskOwner ||
            (_maskLayer?.Version ?? 0) != _jobMaskVersion || _takenLayer != _jobTaken || (_takenLayer?.Version ?? 0) != _jobTakenVersion;
        _jobMask = null;
        _jobTaken = null;
        if (job.IsFaulted || job.IsCanceled) return RefuseBoundary("Não consegui calcular a fronteira.");
        if (Version != _jobVersion || maskChanged)
            return RefuseBoundary("O mapa mudou durante o cálculo. Desenhe novamente.");
        var result = job.Result;
        if (result.TryGetValue("plan", out var value))
        {
            var plan = value.As<TerritoryBoundaryPlan>();
            plan.Map = this;
            plan.Version = Version;
        }
        return result;
    }

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
    public Godot.Collections.Dictionary PlanBoundaryClaim(int target, Vector3[] controls, int id) => PlanBoundaryClaimOn(target, controls, id, false);

    /// Como PlanBoundaryClaim, e também em terra sem dono: uma linha aberta que sai da borda do selecionado e volta a ela toma o bolsão
    /// de terra livre entre a linha e o território (o menor lado que encosta nele). landOnly: desse bolsão, só a terra.
    public Godot.Collections.Dictionary PlanBoundaryClaimOn(int target, Vector3[] controls, int id, bool landOnly)
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
        var onBoundary = new BitArray(length);
        foreach (long edge in edges)
        {
            onBoundary[(int)(edge >> 32)] = true;
            onBoundary[(int)edge] = true;
        }
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
                bool crosses = onBoundary[p];
                area += rowArea[p / Size.X];
                if (restored != null && restored[p]) previousPixels++;
                foreach (var (x, y) in BoundaryNeighbors)
                {
                    int q = terrain.Neighbor(p, x, y);
                    if (q < 0 || labels[q] == label) continue;
                    int neighbor = OwnerBefore(q);
                    if (neighbor == target) meetsTarget = true;
                    if (neighbor != owner || labels[q] != 0 || (crosses && edges.Contains(BoundaryEdge(p, q)))) continue;
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
            if (owner == target || OwnerBefore(q) != owner || (previous != null && owner != previous.Source)) continue;
            int left = LabelPart(p, owner), right = LabelPart(q, owner);
            if (left == right) continue;
            if (!cuts.TryGetValue(owner, out var cut)) cut = (new HashSet<int>(), 0);
            cut.Parts.Add(left);
            cut.Parts.Add(right);
            cuts[owner] = (cut.Parts, cut.Crossings + 1);
        }
        if (cuts.Count == 0) return RefuseBoundary("Comece e termine o traço DENTRO do território (atravessando um vizinho, ou saindo pela terra livre e voltando), ou feche um contorno em terra livre.");

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
        // A máscara vale também quando a área vem de outro território.
        var heights = _boundaryHeights ?? terrain.H;
        var choices = candidates
            .Select(c => c.Pixels.Where(p => Allowed(p) && (source != 0 || !landOnly || heights[p] >= 0f)).ToArray())
            .Where(px => px.Length > 0)
            .Select(px => { Array.Sort(px); return px; }).ToArray();
        if (choices.Length == 0) return RefuseBoundary("O pedaço separado não tem terra que possa ser tomada." + TakenHint);
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
        foreach (int p in plan.Freed) Set(p, 0);
        return Image.CreateFromData(Size.X, Size.Y, false, Image.Format.Rg8, bytes);
    }

    /// A área (km²) que o plano passa para o selecionado.
    public double PlanAreaKm2(TerritoryBoundaryPlan plan)
    {
        int row = -1;
        double area = 0, cell = 0;
        foreach (int pixel in plan.Next.Pixels)
        {
            int y = pixel / Size.X;
            if (y != row)
            {
                row = y;
                cell = RowCellKm2(row, Size.X, Size.Y);
            }
            area += cell;
        }
        return area;
    }

    public TerritoryEdit? ApplyBoundary(TerritoryBoundaryPlan plan)
    {
        if (plan.Map != this || plan.Version != Version || _stroke != null) return null;
        var planned = plan.Next;
        var next = new TerritoryBoundary(planned.Id, planned.Source, planned.Target, planned.Points, planned.Pixels);
        if (Limited && next.Pixels.Any(p => !Allowed(p))) return null;
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
        foreach (int pixel in plan.Freed)  // o que o território tinha do outro lado do traço: fica sem dono (ou com o país novo, ao dividir)
        {
            if (Get(pixel) != next.Target) continue;
            pixels.Add(pixel);
            before.Add((ushort)next.Target);
            Put(pixel, plan.FreedOwner);
        }
        // O registro que o desfazer devolve: o da remodelagem; num redesenho que reaproveita um traço guardado, o dele.
        var replaced = plan.Previous ?? (plan.IsRedraw ? _boundaries.GetValueOrDefault(next.Id) : null);
        if (plan.Previous is { } previous)
        {
            for (int depth = 0; depth < next.Subdivisions.Length; depth++)
                foreach (var (pixel, owner) in previous.Subdivisions[depth])
                    if (Array.BinarySearch(next.Pixels, pixel) >= 0)
                        next.Subdivisions[depth].Add(pixel, owner);
        }
        SetBoundary(next.Id, next);
        // Fronteira nova (não a remodelagem de uma existente): o registro da anterior entre os mesmos dois lados sai. O território que ela mudou
        // fica como está; só deixa de poder ser reaberta por ela. O desfazer devolve o registro.
        var dropped = new List<TerritoryBoundary>();
        // Só os cortes de vizinho: contornos e redesenhos em terra livre convivem (cada um é um trecho diferente da borda do mesmo país).
        if (plan.Previous == null && next.Source != 0)
            foreach (var old in _boundaries.Values.Where(p => p.Id != next.Id && p.Target == next.Target && p.Source == next.Source).ToList())
            {
                dropped.Add(old);
                SetBoundary(old.Id, null);
            }
        // Um redesenho passado por cima de um traço guardado aposenta o antigo, senão há dois registros da mesma borda.
        if (plan.IsRedraw)
            foreach (var old in _boundaries.Values.Where(p => p.Id != next.Id && p.Target == next.Target && p.Source == 0
                         && CoveredBy(p.Points, next.Points)).ToList())
            {
                dropped.Add(old);
                SetBoundary(old.Id, null);
            }
        Touch();
        return new TerritoryEdit(this, pixels.ToArray(), before.ToArray(), replaced, next, dropped);
    }

    /// Dividir: os donos da camada de baixo (subdivisões) com mais da metade dos pixels no lado que o plano tira do selecionado. Eles vão
    /// junto para o cadastro novo (quem chama troca o vínculo antes de aplicar); os outros são aparados na borda, como em qualquer corte.
    public int[] OwnersMostlyFreed(TerritoryBoundaryPlan plan, Territory below)
    {
        var freed = new Dictionary<int, int>();
        foreach (int p in plan.Freed)
            if (below.Get(p) is int o and > 0) freed[o] = freed.GetValueOrDefault(o) + 1;
        if (freed.Count == 0) return [];
        var total = new Dictionary<int, int>();
        for (int p = 0; p < Size.X * Size.Y; p++)
            if (below.Get(p) is int o and > 0 && freed.ContainsKey(o)) total[o] = total.GetValueOrDefault(o) + 1;
        return freed.Where(kv => 2 * kv.Value > total[kv.Key]).Select(kv => kv.Key).OrderBy(o => o).ToArray();
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
        if (points.Length < 2 || points.Length > MaxBoundaryPoints + 1) return false;  // +1: o contorno fechado repete o primeiro ponto
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
                foreach (var level in path.Subdivisions)
                {
                    writer.Write(level.Count);
                    foreach (var (pixel, owner) in level)
                    {
                        writer.Write7BitEncodedInt(pixel);
                        writer.Write(owner);
                    }
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
        int format = reader.ReadInt32();
        if (format != 1 && format != BoundaryFormat) throw new InvalidDataException("Formato de fronteiras incompatível.");
        int count = reader.ReadInt32();
        if (count < 0 || count > Size.X * Size.Y) throw new InvalidDataException("Número de fronteiras inválido.");
        var paths = new Dictionary<int, TerritoryBoundary>();
        int lastId = 0;
        for (int i = 0; i < count; i++)
        {
            int id = reader.ReadInt32(), source = reader.ReadInt32(), target = reader.ReadInt32();
            int pointsCount = reader.ReadInt32();
            // source 0 = a área veio de terra sem dono (contorno fechado ou bolsão de terra livre); o contorno guarda o ponto de volta (+1).
            if (id <= 0 || id == int.MaxValue || (source != 0 && !ValidOwner(source)) || !ValidOwner(target) || source == target ||
                pointsCount < 2 || pointsCount > MaxBoundaryPoints + 1)
                throw new InvalidDataException("Identidade ou geometria de fronteira inválida.");
            var points = new Vector3[pointsCount];
            for (int p = 0; p < points.Length; p++) points[p] = new Vector3(reader.ReadSingle(), reader.ReadSingle(), reader.ReadSingle());
            if (!ValidBoundaryPoints(points)) throw new InvalidDataException("Pontos de fronteira inválidos.");

            int pixelsCount = reader.ReadInt32(), length = Size.X * Size.Y;
            // Zero vale: um redesenho de borda que só tirou área.
            if (pixelsCount < 0 || pixelsCount > length) throw new InvalidDataException("Área de fronteira inválida.");
            var pixels = new int[pixelsCount];
            int previous = -1;
            for (int p = 0; p < pixels.Length; p++)
            {
                int gap = reader.Read7BitEncodedInt();
                if (gap <= 0 || gap >= length - previous) throw new InvalidDataException("Célula de fronteira inválida.");
                pixels[p] = previous += gap;
            }
            var path = new TerritoryBoundary(id, source, target, points, pixels);
            if (format >= 2)
            {
                foreach (var level in path.Subdivisions)
                {
                    int removedCount = reader.ReadInt32();
                    if (removedCount < 0 || removedCount > pixelsCount)
                        throw new InvalidDataException("Número de células de subdivisão inválido.");
                    for (int j = 0; j < removedCount; j++)
                    {
                        int pixel = reader.Read7BitEncodedInt();
                        ushort owner = reader.ReadUInt16();
                        if (!ValidOwner(owner) || Array.BinarySearch(pixels, pixel) < 0 || !level.TryAdd(pixel, owner))
                            throw new InvalidDataException("Célula de subdivisão inválida.");
                    }
                }
            }
            if (!paths.TryAdd(id, path))
                throw new InvalidDataException("Identificador de fronteira duplicado.");
            lastId = Math.Max(lastId, id);
        }
        _boundaries = paths;
        _nextBoundary = lastId + 1;
        _packedBoundaries = bytes;
    }
}
