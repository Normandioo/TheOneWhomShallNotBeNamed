using System;
using System.Collections.Generic;
using Godot;

namespace Evron;

/// Preenchimento em massa do mundo (tools/mundo_completo.gd): reparte um país em subdivisões e cobre a terra com áreas (cultura, etnia...).
/// Os pontos de partida vêm de um sorteio com semente: o mesmo mundo dá sempre o mesmo resultado.
public partial class Territory
{
    Vector3[]? _dirs;

    Vector3 DirOfPixel(int i)
    {
        if (_dirs == null)
        {
            _dirs = new Vector3[Size.X * Size.Y];
            for (int y = 0; y < Size.Y; y++)
            {
                double lat = Math.PI * (0.5 - (y + 0.5) / Size.Y), cl = Math.Cos(lat), sl = Math.Sin(lat);
                for (int x = 0; x < Size.X; x++)
                {
                    double lon = ((x + 0.5) / Size.X - 0.5) * 2.0 * Math.PI;
                    _dirs[y * Size.X + x] = new Vector3((float)(cl * Math.Sin(lon)), (float)sl, (float)(cl * Math.Cos(lon)));
                }
            }
        }
        return _dirs[i];
    }

    /// Reparte o território de `sourceOwner` em `ids.Length` partes compactas (agrupamento por distância no globo), uma por cadastro de `ids`.
    /// Só onde esta camada ainda não tem dono. Devolve a edição para desfazer, ou null se não havia o que repartir.
    public TerritoryEdit? Partition(Territory source, int sourceOwner, int[] ids, int seed)
    {
        var pixels = new List<int>();
        for (int i = 0; i < Size.X * Size.Y; i++)
            if (source.Get(i) == sourceOwner && Get(i) == 0) pixels.Add(i);
        if (pixels.Count == 0 || ids.Length == 0) return null;
        var rng = new Random(seed);
        int k = Math.Min(ids.Length, pixels.Count);
        var seeds = PickSeeds(pixels, k, rng, true);
        int[] label = new int[pixels.Count];
        for (int round = 0; round < 4; round++)
        {
            for (int p = 0; p < pixels.Count; p++)
            {
                var d = DirOfPixel(pixels[p]);
                float best = float.MinValue;
                for (int s = 0; s < k; s++)
                {
                    float dot = d.Dot(seeds[s]);
                    if (dot > best) { best = dot; label[p] = s; }
                }
            }
            var sum = new Vector3[k];
            for (int p = 0; p < pixels.Count; p++) sum[label[p]] += DirOfPixel(pixels[p]);
            for (int s = 0; s < k; s++)
                if (sum[s].Length() > 0f) seeds[s] = sum[s].Normalized();
        }
        return ApplyLabels(pixels, label, ids);
    }

    /// Cobre a terra que ainda não tem dono nesta camada com as áreas de `ids` (diagrama de Voronoi com pesos e bordas onduladas).
    public TerritoryEdit? FillLand(int[] ids, int seed)
    {
        var pixels = new List<int>();
        for (int i = 0; i < Size.X * Size.Y; i++)
            if (Get(i) == 0 && !_terrain!.Water(i)) pixels.Add(i);
        if (pixels.Count == 0 || ids.Length == 0) return null;
        var rng = new Random(seed);
        int k = ids.Length;
        var seeds = PickSeeds(pixels, k, rng, false);
        var weight = new float[k];
        var phase = new float[k, 4];
        for (int s = 0; s < k; s++)
        {
            weight[s] = 0.6f + (float)rng.NextDouble();
            for (int j = 0; j < 4; j++) phase[s, j] = (float)(rng.NextDouble() * Math.PI * 2);
        }
        int[] label = new int[pixels.Count];
        for (int p = 0; p < pixels.Count; p++)
        {
            var d = DirOfPixel(pixels[p]);
            float best = float.MaxValue;
            for (int s = 0; s < k; s++)
            {
                float wave = 1f + 0.32f * Mathf.Sin(7f * d.X + phase[s, 0]) * Mathf.Sin(6f * d.Z + phase[s, 1]) + 0.2f * Mathf.Sin(13f * d.Y + phase[s, 2]);
                float dist = (1f - d.Dot(seeds[s])) / weight[s] * wave;
                if (dist < best) { best = dist; label[p] = s; }
            }
        }
        return ApplyLabels(pixels, label, ids);
    }

    TerritoryEdit? ApplyLabels(List<int> pixels, int[] label, int[] ids)
    {
        var all = new List<int>(pixels.Count);
        var before = new List<ushort>(pixels.Count);
        for (int p = 0; p < pixels.Count; p++)
        {
            int owner = ids[label[p]];
            if (owner < 1 || owner > MaxOwner) throw new ArgumentException($"dono fora de 1..{MaxOwner}: {owner}");
            all.Add(pixels[p]);
            before.Add((ushort)Get(pixels[p]));
            Put(pixels[p], owner);
        }
        Touch();
        return new TerritoryEdit(this, all.ToArray(), before.ToArray());
    }

    /// k pontos espalhados: cada um é o melhor de vários sorteios (o mais longe dos já escolhidos).
    Vector3[] PickSeeds(List<int> pixels, int k, Random rng, bool far)
    {
        var seeds = new List<Vector3> { DirOfPixel(pixels[rng.Next(pixels.Count)]) };
        int tries = far ? 400 : 24;
        while (seeds.Count < k)
        {
            Vector3 bestDir = seeds[0];
            float bestGap = -1f;
            for (int t = 0; t < tries; t++)
            {
                var d = DirOfPixel(pixels[rng.Next(pixels.Count)]);
                float nearest = float.MinValue;
                foreach (var s in seeds) nearest = Math.Max(nearest, d.Dot(s));
                float gap = 1f - nearest;
                if (gap > bestGap) { bestGap = gap; bestDir = d; }
            }
            seeds.Add(bestDir);
        }
        return seeds.ToArray();
    }
}
