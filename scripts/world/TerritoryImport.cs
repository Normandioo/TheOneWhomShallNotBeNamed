using System;
using System.Collections.Generic;
using System.Linq;
using Godot;

namespace Evron;

/// Importação de PNG (especificação 17.6): a imagem é reamostrada para a grade (equiretangular, vizinho mais próximo), cada cor vira
/// regiões conectadas e cada REGIÃO é uma linha para o usuário mapear: duas manchas da mesma cor não são assumidas como a mesma entidade.
/// Transparente (alfa < 128) é fundo. Nada muda na camada até ApplyImport; a importação não cria caminhos vetoriais.
public partial class Territory
{
    private int[] _importLabels = Array.Empty<int>();  // região de cada pixel (0 = fundo ou mancha pequena demais)
    private int _importRegions;

    /// Analisa a imagem e devolve as regiões (as maiores primeiro): {index, rgb, pixels, area_km2, lat, lon}. lat/lon é um pixel da
    /// própria região (para levar a câmera até ela). Manchas com menos de minPixels pixels ficam de fora (ruído de antisserrilhado).
    public Godot.Collections.Array<Godot.Collections.Dictionary> AnalyzeImage(Image source, int minPixels)
    {
        var img = (Image)source.Duplicate();
        if (img.IsCompressed()) img.Decompress();
        img.Convert(Image.Format.Rgba8);
        img.Resize(Size.X, Size.Y, Image.Interpolation.Nearest);
        var rgba = img.GetData();
        int w = Size.X, n = Size.X * Size.Y;
        int ColorAt(int p) => rgba[p * 4 + 3] < 128 ? -1 : (rgba[p * 4] << 16) | (rgba[p * 4 + 1] << 8) | rgba[p * 4 + 2];

        var labels = new int[n];
        var found = new List<(int Rgb, List<int> Pixels)>();
        var stack = new Stack<int>();
        for (int start = 0; start < n; start++)
        {
            int rgb = ColorAt(start);
            if (rgb < 0 || labels[start] != 0) continue;
            var pixels = new List<int>();
            labels[start] = -1;
            stack.Push(start);
            while (stack.Count > 0)
            {
                int p = stack.Pop();
                pixels.Add(p);
                foreach (var (dx, dy) in new[] { (-1, 0), (1, 0), (0, -1), (0, 1) })
                {
                    int q = _terrain!.Neighbor(p, dx, dy);
                    if (q < 0 || labels[q] != 0 || ColorAt(q) != rgb) continue;
                    labels[q] = -1;
                    stack.Push(q);
                }
            }
            found.Add((rgb, pixels));
        }

        Array.Clear(labels);
        var result = new Godot.Collections.Array<Godot.Collections.Dictionary>();
        int index = 0;
        foreach (var (rgb, pixels) in found.Where(f => f.Pixels.Count >= minPixels).OrderByDescending(f => f.Pixels.Count))
        {
            index++;
            double area = 0;
            foreach (int p in pixels)
            {
                labels[p] = index;
                area += RowCellKm2(p / w, w, Size.Y);
            }
            var (lat, lon) = EvronGeo.LatLon(_terrain!.DirOf(pixels[pixels.Count / 2]));
            result.Add(new Godot.Collections.Dictionary
            {
                ["index"] = index, ["rgb"] = rgb, ["pixels"] = pixels.Count, ["area_km2"] = area, ["lat"] = lat, ["lon"] = lon,
            });
        }
        _importLabels = labels;
        _importRegions = index;
        return result;
    }

    /// Preenche a camada a partir de uma imagem de categorias: o pixel da cor rgbs[k] passa a ser do dono k + 1; outra cor fica sem dono.
    /// Sem interpolação (a imagem é reduzida pelo vizinho mais próximo). Não é uma edição (é o ponto de partida): não vai para o desfazer.
    /// Devolve quantos pixels ficaram com dono.
    public int FillFromColors(Image source, int[] rgbs)
    {
        var img = (Image)source.Duplicate();
        if (img.IsCompressed()) img.Decompress();
        img.Convert(Image.Format.Rgb8);
        if (img.GetSize() != Size) img.Resize(Size.X, Size.Y, Image.Interpolation.Nearest);
        var rgb = img.GetData();
        var owner = new Dictionary<int, int>();
        for (int k = 0; k < rgbs.Length; k++) owner[rgbs[k]] = k + 1;
        int set = 0;
        for (int p = 0; p < Size.X * Size.Y; p++)
        {
            int o = owner.GetValueOrDefault((rgb[3 * p] << 16) | (rgb[3 * p + 1] << 8) | rgb[3 * p + 2]);
            Put(p, o);
            if (o > 0) set++;
        }
        Touch();
        return set;
    }

    /// Aplica o mapeamento da última análise: a região indices[k] passa a ser de owners[k] (0 = apagar). Regiões fora da lista não mudam.
    /// Devolve a edição (um comando: desfazer volta tudo), ou null se nada mudou.
    public TerritoryEdit? ApplyImport(int[] indices, int[] owners)
    {
        if (indices.Length != owners.Length) throw new ArgumentException("uma entidade para cada região");
        if (_importLabels.Length != Size.X * Size.Y) throw new InvalidOperationException("analise uma imagem antes de aplicar");
        var map = new int[_importRegions + 1];
        Array.Fill(map, -1);
        for (int k = 0; k < indices.Length; k++)
        {
            if (indices[k] < 1 || indices[k] > _importRegions) throw new ArgumentException($"região inexistente: {indices[k]}");
            if (owners[k] < 0 || owners[k] > MaxOwner) throw new ArgumentException($"dono fora de 0..{MaxOwner}: {owners[k]}");
            map[indices[k]] = owners[k];
        }
        var idx = new List<int>();
        var before = new List<ushort>();
        for (int p = 0; p < _importLabels.Length; p++)
        {
            int owner = map[_importLabels[p]];
            if (owner < 0 || Get(p) == owner) continue;
            idx.Add(p);
            before.Add((ushort)Get(p));
            Put(p, owner);
        }
        if (idx.Count == 0) return null;
        Touch();
        return new TerritoryEdit(this, idx.ToArray(), before.ToArray());
    }
}
