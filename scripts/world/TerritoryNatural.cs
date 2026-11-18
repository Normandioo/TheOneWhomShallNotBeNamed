using System;
using System.Collections.Generic;
using Godot;

namespace Evron;

/// Fronteiras naturais (docs/mapa-politico.md, etapa 1): os países crescem pela terra sem dono como as fronteiras de verdade se formam, e uma
/// fronteira pintada à mão pode ser assentada na crista ou no rio mais perto. Tudo devolve uma TerritoryEdit (desfazer); nada sobrescreve terra
/// de outro país sem o usuário pedir.
///
/// Custo de atravessar 1 km (o "atrito"), o mesmo do protótipo tools/mapa_politico.py:
///   terra = (1 + 0,6·declividade em graus + 1,2·(altitude acima de 1.500 m, por km, até 4)) × e^(3·(ruído − 0,5)) + pedágio de rio grande
///   lago = 8, mar raso (até 400 m) = 10, mar fundo = 60: ilha perto da costa entra no país; outro continente, não.
/// O ruído (colinas de ~100 km, semente fixa) faz o papel da história: sem ele a fronteira na planície sai reta, como um Voronoi.
/// A fronteira cai onde dois países chegam com o mesmo custo: serras e rios grandes a seguram.
public partial class Territory
{
    private const int NoiseSeed = 7;
    private const double RiverT = 0.7;   // fluxo (0..1 do Gleba) a partir do qual o rio é "grande" e custa atravessar

    private byte[]? _flow;  // fluxo de água do Gleba (Waterflow.png), 0..255; null = só os rios do pincel Vales (Terrain.R)

    // As 9 cores da escala viridis (a mesma de tools/build_natural.py e ui/map_layers.gd), em que o Gleba grava o fluxo.
    private static readonly double[,] Viridis =
    {
        { 0.267, 0.005, 0.329 }, { 0.279, 0.175, 0.483 }, { 0.230, 0.322, 0.546 }, { 0.173, 0.449, 0.558 }, { 0.128, 0.567, 0.551 },
        { 0.158, 0.684, 0.502 }, { 0.369, 0.789, 0.383 }, { 0.678, 0.864, 0.190 }, { 0.993, 0.906, 0.144 },
    };

    /// O fluxo de água do Gleba ("Waterflow.png", escala viridis), na grade do terreno: os rios grandes passam a segurar fronteiras.
    /// Uma imagem de outro tamanho é recusada (false).
    public bool SetRiverFlow(Image waterflow)
    {
        if (waterflow == null || waterflow.GetSize() != Size) return false;
        var img = (Image)waterflow.Duplicate();
        img.Convert(Image.Format.Rgb8);
        var rgb = img.GetData();
        var lut = new double[256, 3];
        for (int k = 0; k < 256; k++)
        {
            double x = k / 255.0 * 8;
            int a = Math.Min((int)x, 7);
            for (int c = 0; c < 3; c++) lut[k, c] = (Viridis[a, c] + (Viridis[a + 1, c] - Viridis[a, c]) * (x - a)) * 255;
        }
        var cache = new Dictionary<int, byte>();
        var flow = new byte[Size.X * Size.Y];
        for (int i = 0; i < flow.Length; i++)
        {
            int r = rgb[3 * i], g = rgb[3 * i + 1], b = rgb[3 * i + 2], key = (r << 16) | (g << 8) | b;
            if (!cache.TryGetValue(key, out byte t))
            {
                double best = double.MaxValue;
                for (int k = 0; k < 256; k++)
                {
                    double d = (r - lut[k, 0]) * (r - lut[k, 0]) + (g - lut[k, 1]) * (g - lut[k, 1]) + (b - lut[k, 2]) * (b - lut[k, 2]);
                    if (d < best) { best = d; t = (byte)k; }
                }
                cache[key] = t;
            }
            flow[i] = t;
        }
        _flow = flow;
        return true;
    }

    /// Fluxo 0..1 do pixel: o do Gleba ou o rio marcado pelo pincel Vales, o que for maior.
    private double River(int p) => Math.Max(_flow != null ? _flow[p] / 255.0 : 0.0, _terrain!.R[p] > 0 ? 1.0 : 0.0);

    /// Atrito por km do pixel p (ver o topo). cache: 0 = ainda não calculado (o terreno pode ter mudado desde a última vez: um por chamada).
    private float Friction(int p, float[] cache, TerrainNoise noise)
    {
        if (cache[p] > 0f) return cache[p];
        var t = _terrain!;
        double h = t.H[p];
        double f;
        if (t.Water(p))
            f = h >= 0 ? 8.0 : h > -400 ? 10.0 : 60.0;  // lago, mar raso, mar fundo
        else
        {
            int w = Size.X, y = p / w;
            double dyKm = Math.PI * EvronGeo.RadiusKm / Size.Y;
            double dxKm = Math.Max(Math.Cos(Math.PI * (0.5 - (y + 0.5) / Size.Y)), 0.05) * 2 * Math.PI * EvronGeo.RadiusKm / w;
            double H(int q) => q < 0 ? h : Math.Max(t.H[q], 0f);  // o mar conta como 0 m: a costa não vira "encosta"
            double gx = (H(t.Neighbor(p, 1, 0)) - H(t.Neighbor(p, -1, 0))) / (2000 * dxKm);
            double gy = (H(t.Neighbor(p, 0, 1)) - H(t.Neighbor(p, 0, -1))) / (2000 * dyKm);
            double slope = Math.Atan(Math.Sqrt(gx * gx + gy * gy)) * 180 / Math.PI;
            double r = River(p);
            f = (1 + 0.6 * slope + 1.2 * Math.Clamp((h - 1500) / 1000, 0, 4)) * Math.Exp(3 * (noise.Fbm(t.DirOf(p)) - 0.5))
                + (r > RiverT ? 3 + 25 * (r - RiverT) : 0);
        }
        cache[p] = (float)f;
        return cache[p];
    }

    /// Distância em km entre os centros de p e do vizinho (dx, dy): na linha, encolhe com o cos da latitude.
    private double StepKm(int p, int dx, int dy)
    {
        double lat = Math.PI * (0.5 - (p / Size.X + 0.5 + dy * 0.5) / Size.Y);
        double ex = dx * Math.Cos(lat) * 2 * Math.PI * EvronGeo.RadiusKm / Size.X, ey = dy * Math.PI * EvronGeo.RadiusKm / Size.Y;
        return Math.Sqrt(ex * ex + ey * ey);
    }

    /// Os países crescem pela terra SEM dono, a partir do território que já têm e das capitais (capitalOwners[i] em capitalLat/Lon[i]), cada pixel
    /// para quem chega com o menor custo (atrito × km), até maxKm de custo. A terra de outro país é barreira (nunca é tomada) e o mar se atravessa caro
    /// mas não se pinta. Todos competem; onlyOwner > 0 grava só o que esse país ganha (ele para onde os vizinhos chegariam primeiro), 0 grava todos.
    public TerritoryEdit? Grow(int[] capitalOwners, double[] capitalLat, double[] capitalLon, int onlyOwner, double maxKm)
    {
        if (capitalOwners.Length != capitalLat.Length || capitalOwners.Length != capitalLon.Length)
            throw new ArgumentException("capitais: listas de tamanhos diferentes");
        var t = _terrain!;
        int n = Size.X * Size.Y;
        var dist = new float[n];
        Array.Fill(dist, float.PositiveInfinity);
        var lab = new ushort[n];
        var fr = new float[n];
        var noise = new TerrainNoise();
        noise.SetSeed(NoiseSeed);
        var queue = new PriorityQueue<int, float>();

        // Fontes: a borda de cada território (pixel com dono que encosta em pixel sem dono) e as capitais em pixel sem dono.
        for (int p = 0; p < n; p++)
        {
            int o = Get(p);
            if (o == 0) continue;
            foreach (var (dx, dy, _) in Terrain.Neighbors)
            {
                int q = t.Neighbor(p, dx, dy);
                if (q >= 0 && Get(q) == 0)
                {
                    dist[p] = 0f;
                    lab[p] = (ushort)o;
                    queue.Enqueue(p, 0f);
                    break;
                }
            }
        }
        for (int i = 0; i < capitalOwners.Length; i++)
        {
            int o = capitalOwners[i];
            if (o <= 0 || o > MaxOwner) throw new ArgumentException($"dono fora de 1..{MaxOwner}: {o}");
            int c = t.PixelOf(EvronGeo.Dir(capitalLat[i], capitalLon[i]));
            if (Get(c) != 0 || lab[c] != 0) continue;  // a capital já está em território (de alguém) ou outra capital caiu no mesmo pixel
            dist[c] = 0f;
            lab[c] = (ushort)o;
            queue.Enqueue(c, 0f);
        }

        while (queue.TryDequeue(out int p, out float d))
        {
            if (d > dist[p]) continue;  // entrada velha da fila
            float fp = Get(p) == 0 ? Friction(p, fr, noise) : 1f;  // a borda de um território sai sem atrito próprio
            foreach (var (dx, dy, _) in Terrain.Neighbors)
            {
                int q = t.Neighbor(p, dx, dy);
                if (q < 0 || Get(q) != 0) continue;  // terra com dono é barreira
                float nd = d + (float)(StepKm(p, dx, dy) * 0.5 * (fp + Friction(q, fr, noise)));
                if (nd < dist[q] && nd <= maxKm)
                {
                    dist[q] = nd;
                    lab[q] = lab[p];
                    queue.Enqueue(q, nd);
                }
            }
        }

        var pixels = new List<int>();
        var owners = new List<int>();
        for (int p = 0; p < n; p++)
            if (lab[p] != 0 && Get(p) == 0 && !t.Water(p) && (onlyOwner <= 0 || lab[p] == onlyOwner))
            {
                pixels.Add(p);
                owners.Add(lab[p]);
            }
        return ApplyMany(pixels, owners);
    }

    /// Assenta as fronteiras do país `owner` (0 = de todos) com os vizinhos no relevo: numa faixa de bandKm de cada lado da fronteira, a linha vai para a
    /// crista ou o rio grande mais perto (watershed: cada lado "enche" a partir do seu território, das partes baixas para as altas, e os dois se encontram
    /// no alto ou no rio). Só troca pixels de terra entre os países que já se tocam ali: não cria nem apaga território, nem mexe na costa.
    public TerritoryEdit? Snap(int owner, double bandKm)
    {
        var t = _terrain!;
        int n = Size.X * Size.Y;
        bool Land(int p) => p >= 0 && !t.Water(p);
        (int, int)[] four = { (1, 0), (-1, 0), (0, 1), (0, -1) };

        // Quem pode trocar pixels: o país e quem faz fronteira com ele (todos, se owner = 0).
        var allowed = new HashSet<int>();
        var band = new float[n];
        Array.Fill(band, float.PositiveInfinity);
        var queue = new PriorityQueue<int, float>();
        for (int p = 0; p < n; p++)
        {
            int a = Get(p);
            if (a == 0 || !Land(p)) continue;
            foreach (var (dx, dy) in four)
            {
                int q = t.Neighbor(p, dx, dy);
                if (!Land(q)) continue;
                int b = Get(q);
                if (b == 0 || b == a || (owner != 0 && a != owner && b != owner)) continue;
                allowed.Add(a);
                allowed.Add(b);
                if (band[p] > 0f)
                {
                    band[p] = 0f;
                    queue.Enqueue(p, 0f);
                }
            }
        }
        if (queue.Count == 0) return null;

        // A faixa: os pixels desses países a até bandKm (pela superfície) de um pixel de fronteira.
        while (queue.TryDequeue(out int p, out float d))
        {
            if (d > band[p]) continue;
            foreach (var (dx, dy, _) in Terrain.Neighbors)
            {
                int q = t.Neighbor(p, dx, dy);
                if (!Land(q) || !allowed.Contains(Get(q))) continue;
                float nd = d + (float)StepKm(p, dx, dy);
                if (nd < band[q] && nd <= bandKm)
                {
                    band[q] = nd;
                    queue.Enqueue(q, nd);
                }
            }
        }
        // País que cabe inteiro na faixa (pequeno) não teria de onde encher e sumiria: ele sai da faixa e fica como está, sem encher (só enche
        // quem tem terra fora da faixa: `outside`).
        var outside = new HashSet<int>();
        for (int p = 0; p < n; p++)
            if (Land(p) && float.IsPositiveInfinity(band[p]) && allowed.Contains(Get(p))) outside.Add(Get(p));
        for (int p = 0; p < n; p++)
            if (!float.IsPositiveInfinity(band[p]) && !outside.Contains(Get(p))) band[p] = float.PositiveInfinity;
        bool InBand(int p) => p >= 0 && !float.IsPositiveInfinity(band[p]);

        // Watershed com marcadores: fora da faixa cada país fica como está; dentro, os pixels são tomados das partes baixas para as altas.
        // O rio grande é um "muro": os dois lados enchem até ele, e a fronteira fica na margem. A altura é a média 3×3 (os degraus do Gleba).
        var level = new float[n];
        Array.Fill(level, float.NaN);
        double Level(int p)
        {
            if (float.IsNaN(level[p])) level[p] = (float)(t.NeighborMean(p) + (River(p) > RiverT ? 1e5 : 0));
            return level[p];
        }
        var lab = new int[n];
        var queued = new bool[n];
        var flood = new PriorityQueue<int, (double, long)>();
        long order = 0;
        for (int p = 0; p < n; p++)
        {
            if (!InBand(p)) continue;
            foreach (var (dx, dy) in four)
            {
                int q = t.Neighbor(p, dx, dy);
                if (Land(q) && !InBand(q) && outside.Contains(Get(q)))
                {
                    queued[p] = true;
                    flood.Enqueue(p, (Level(p), order++));
                    break;
                }
            }
        }
        while (flood.TryDequeue(out int p, out _))
        {
            // O dono vem do vizinho já decidido (marcador ou já tomado) mais baixo: a água que chegou primeiro.
            double low = double.MaxValue;
            foreach (var (dx, dy) in four)
            {
                int q = t.Neighbor(p, dx, dy);
                if (!Land(q)) continue;
                int o = InBand(q) ? lab[q] : (outside.Contains(Get(q)) ? Get(q) : 0);
                if (o != 0 && Level(q) < low)
                {
                    low = Level(q);
                    lab[p] = o;
                }
            }
            foreach (var (dx, dy) in four)
            {
                int q = t.Neighbor(p, dx, dy);
                if (InBand(q) && !queued[q])
                {
                    queued[q] = true;
                    flood.Enqueue(q, (Level(q), order++));
                }
            }
        }

        var pixels = new List<int>();
        var owners = new List<int>();
        for (int p = 0; p < n; p++)
            if (InBand(p) && lab[p] != 0 && lab[p] != Get(p))
            {
                pixels.Add(p);
                owners.Add(lab[p]);
            }
        return ApplyMany(pixels, owners);
    }

    /// Como Apply, mas cada pixel com o seu dono novo.
    private TerritoryEdit? ApplyMany(List<int> pixels, List<int> owners)
    {
        if (pixels.Count == 0) return null;
        var idx = pixels.ToArray();
        var before = new ushort[idx.Length];
        for (int k = 0; k < idx.Length; k++)
        {
            before[k] = (ushort)Get(idx[k]);
            Put(idx[k], owners[k]);
        }
        Touch();
        return new TerritoryEdit(this, idx, before);
    }
}
