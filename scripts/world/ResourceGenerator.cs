using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using Godot;

namespace Evron;

/// Um indício que soma aptidão: vale onde TODAS as suas condições valem (lista vazia = qualquer uma).
public sealed class ResourceFactor
{
    public string Name { get; set; } = "";
    public string[] Rocks { get; set; } = Array.Empty<string>();
    public string[] Climates { get; set; } = Array.Empty<string>();
    public string[] Provinces { get; set; } = Array.Empty<string>();  // orogeno | derrames (calibração: hipótese)
    public string[] Volcanoes { get; set; } = Array.Empty<string>();  // arco | colisao | rifte (hipótese)
    public double VolcanoKm { get; set; } = 300;                      // a até quantos km do vulcanismo
    public double SlopeMax { get; set; } = 90;
    public int Weight { get; set; } = 50;
}

/// A condição de um recurso (etapa 2 do plano de recursos): onde ele PODE aparecer, pelos mapas. Lista vazia = qualquer um.
/// São sugestões de um mundo gerado, não levantamento: não há mapa de minério.
public sealed class ResourceRule
{
    public int Version { get; set; } = 1;
    public string Surface { get; set; } = "terra";                      // terra | mar
    public string[] Rocks { get; set; } = Array.Empty<string>();         // classes de ResourceGenerator.RockColors
    public string[] Climates { get; set; } = Array.Empty<string>();      // grupos de Köppen: A a E
    public double ElevMin { get; set; } = -13500;
    public double ElevMax { get; set; } = 9200;
    public double SlopeMax { get; set; } = 90;                          // graus
    public double TreesMin { get; set; }                                // % de árvores (Vegetação.png)
    public double SoilMin { get; set; }                                 // índice 0..100 (Soil Richness.png)
    // Sem indícios, todo lugar que passa nas condições vale 100. Com eles, a aptidão é a soma dos pesos (até 100).
    public ResourceFactor[] Prefer { get; set; } = Array.Empty<ResourceFactor>();
    public int MinScore { get; set; } = 1;
    public string Output { get; set; } = "area";                        // area | ponto
    public int Count { get; set; } = 8;
    public double SizeKm { get; set; } = 250;                           // área: raio aproximado; ponto: distância mínima entre eles
    public int Seed { get; set; } = 1;

    static readonly JsonSerializerOptions Options = new() { PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower, Converters = { new WholeNumber() } };

    /// O JSON do Godot devolve todo número como 1.0: um inteiro escrito assim vale; 1.5 continua recusado.
    private sealed class WholeNumber : System.Text.Json.Serialization.JsonConverter<int>
    {
        public override int Read(ref Utf8JsonReader reader, Type type, JsonSerializerOptions options)
        {
            double v = reader.TokenType == JsonTokenType.Number ? reader.GetDouble() : double.NaN;
            return v == Math.Floor(v) && v >= int.MinValue && v <= int.MaxValue ? (int)v : throw new JsonException("esperava um número inteiro");
        }

        public override void Write(Utf8JsonWriter writer, int value, JsonSerializerOptions options) => writer.WriteNumberValue(value);
    }

    public string ToJson() => JsonSerializer.Serialize(this, Options);

    /// Lê e confere. Lança ArgumentException dizendo o que está errado.
    public static ResourceRule Parse(string json)
    {
        ResourceRule r;
        try { r = JsonSerializer.Deserialize<ResourceRule>(json, Options) ?? throw new ArgumentException("regra vazia"); }
        catch (JsonException e) { throw new ArgumentException("a regra não é um JSON válido: " + e.Message); }
        string? why =
            r.Version != 1 ? "versão de regra desconhecida" :
            r.Surface is not ("terra" or "mar") ? "a superfície é terra ou mar" :
            r.Rocks == null || r.Rocks.Any(k => !ResourceGenerator.RockColors.ContainsKey(k)) ? "classe de rocha desconhecida" :
            r.Climates == null || r.Climates.Any(k => k is not ("A" or "B" or "C" or "D" or "E")) ? "grupo de clima desconhecido" :
            !(r.ElevMin <= r.ElevMax) ? "a altitude mínima passa da máxima" :
            !(r.SlopeMax > 0 && r.SlopeMax <= 90) ? "o declive máximo vai de 0 a 90 graus" :
            !(r.TreesMin >= 0 && r.TreesMin <= 100 && r.SoilMin >= 0 && r.SoilMin <= 100) ? "árvores e solo vão de 0 a 100" :
            r.Output is not ("area" or "ponto") ? "a saída é área ou ponto" :
            r.Count < 1 || r.Count > ResourceGenerator.MaxCount ? $"a quantidade vai de 1 a {ResourceGenerator.MaxCount}" :
            !(r.SizeKm >= 10 && r.SizeKm <= 2000) ? "o tamanho vai de 10 a 2000 km" :
            r.Prefer == null || r.Prefer.Length > 12 || r.Prefer.Any(f => !ValidFactor(f)) ? "há um indício inválido (nome, rochas, climas, províncias, vulcanismo, distância, declive ou peso)" :
            r.MinScore < 1 || r.MinScore > 100 ? "a aptidão mínima vai de 1 a 100" :
            r.Surface == "mar" && (r.Rocks.Length > 0 || r.Climates.Length > 0 || r.TreesMin > 0 || r.SoilMin > 0 || r.Prefer.Length > 0)
                ? "no mar só valem altitude (profundidade) e declive: rocha, clima, árvores e solo são da terra" : null;
        return why == null ? r : throw new ArgumentException(why);
    }

    static bool ValidFactor(ResourceFactor f) =>
        f != null && !string.IsNullOrWhiteSpace(f.Name) && f.Rocks != null && f.Rocks.All(k => ResourceGenerator.RockColors.ContainsKey(k))
        && f.Climates != null && f.Climates.All(k => k is "A" or "B" or "C" or "D" or "E")
        && f.Provinces != null && f.Provinces.All(k => ResourceGenerator.ProvinceColors.ContainsKey(k))
        && f.Volcanoes != null && f.Volcanoes.All(k => ResourceGenerator.VolcanoColors.ContainsKey(k))
        && f.VolcanoKm >= 10 && f.VolcanoKm <= 1000 && f.SlopeMax > 0 && f.SlopeMax <= 90 && f.Weight >= 1 && f.Weight <= 100;

    /// Os mapas que a regra precisa ler (a altitude vem do terreno, com as edições).
    public string[] Maps()
    {
        var maps = new List<string>();
        if (Rocks.Length > 0 || Prefer.Any(f => f.Rocks.Length > 0)) maps.Add("Bedrock.png");
        if (Climates.Length > 0 || Prefer.Any(f => f.Climates.Length > 0)) maps.Add("Clima.png");
        if (Prefer.Any(f => f.Provinces.Length > 0)) maps.Add("Provincias geologicas.png");
        if (Prefer.Any(f => f.Volcanoes.Length > 0)) maps.Add("Vulcanismo.png");
        if (TreesMin > 0) maps.Add("Vegetação.png");
        if (SoilMin > 0) maps.Add("Soil Richness.png");
        return maps.ToArray();
    }
}

internal sealed class Proposal
{
    public int Center;
    public double Lat, Lon, Km2, RadiusKm;
    public int Score = 100;
    public string Why = "";                    // os indícios que valem no centro
    public bool[] Matched = Array.Empty<bool>();  // por indício da regra: vale no centro?
    public int[] Pixels = Array.Empty<int>();  // só nas áreas
    public bool Rejected;
}

/// O gerador, sem banco e sem tela. A mesma regra, semente e mapas dão as mesmas sugestões. Primeiro acha os ambientes candidatos,
/// depois escolhe centros agrupados (um ruído de ~600 km na esfera) e cresce as manchas só dentro dos candidatos.
internal static class ResourceGenerator
{
    public const int AlgorithmVersion = 2;  // 2: aptidão por indícios (sem indícios o resultado é o mesmo da 1)
    public const int MaxCount = 200;
    private const int Pool = 40000;  // quantos candidatos concorrem a centro
    private const float ClusterScale = 0.17f;  // o Fbm de TerrainNoise tem ~100 km: encolher a posição o leva a ~600 km

    /// Cada rocha em Bedrock.png: (código, nome, cor). Legenda do Gleba, com acerto de 100% na terra (docs/calibracao).
    public static readonly (string Code, string Name, int Color)[] RockTable =
    {
        ("arenito", "Arenito", Rgb(200, 190, 15)),
        ("conglomerado", "Conglomerado", Rgb(190, 155, 165)),
        ("brecha", "Brecha", Rgb(180, 124, 135)),
        ("siltito", "Siltito", Rgb(166, 131, 17)),
        ("lamito", "Lamito", Rgb(163, 78, 30)),
        ("argilito", "Argilito", Rgb(160, 40, 46)),
        ("folhelho", "Folhelho", Rgb(239, 228, 176)),
        ("cre", "Cré", Rgb(195, 220, 195)),
        ("calcario", "Calcário", Rgb(82, 242, 77)),
        ("dolomito", "Dolomito", Rgb(34, 177, 76)),
        ("silex", "Sílex", Rgb(30, 147, 56)),
        ("halita", "Halita", Rgb(255, 235, 235)),
        ("granito", "Granito", Rgb(190, 100, 220)),
        ("granodiorito", "Granodiorito", Rgb(170, 80, 200)),
        ("diorito", "Diorito", Rgb(150, 60, 180)),
        ("gabro", "Gabro", Rgb(130, 40, 160)),
        ("peridotito", "Peridotito", Rgb(110, 20, 140)),
        ("riolito", "Riolito", Rgb(15, 21, 239)),
        ("dacito", "Dacito", Rgb(13, 20, 211)),
        ("andesito", "Andesito", Rgb(11, 19, 190)),
        ("basalto", "Basalto", Rgb(10, 18, 165)),
        ("picrobasalto", "Picrobasalto", Rgb(6, 15, 140)),
        ("marmore", "Mármore", Rgb(200, 200, 250)),
        ("quartzito", "Quartzito", Rgb(250, 200, 200)),
        ("skarn", "Skarn", Rgb(40, 145, 145)),
        ("hornfels", "Hornfels", Rgb(20, 223, 200)),
        ("ardosia", "Ardósia", Rgb(56, 56, 56)),
        ("filito", "Filito", Rgb(85, 85, 85)),
        ("xisto", "Xisto", Rgb(100, 100, 100)),
        ("gnaisse", "Gnaisse", Rgb(120, 120, 120)),
        ("migmatito", "Migmatito", Rgb(143, 143, 143)),
        ("xisto_azul", "Xisto azul", Rgb(0, 50, 100)),
        ("eclogito", "Eclogito", Rgb(0, 50, 50)),
        ("rocha_verde", "Rocha verde", Rgb(0, 100, 0)),
        ("anfibolito", "Anfibolito", Rgb(0, 50, 0)),
        ("xisto_verde", "Xisto verde", Rgb(0, 75, 0)),
        ("granulito", "Granulito", Rgb(0, 25, 0)),
    };

    /// Rocha ou classe de rocha -> as cores dela.
    public static readonly Dictionary<string, int[]> RockColors = BuildRockColors();

    private static Dictionary<string, int[]> BuildRockColors()
    {
        var colors = RockTable.ToDictionary(r => r.Code, r => new[] { r.Color });
        int[] Group(params string[] codes) => codes.Select(c => colors[c][0]).ToArray();
        colors["sedimentar_clastica"] = Group("arenito", "conglomerado", "brecha", "siltito", "lamito", "argilito", "folhelho");
        colors["sedimentar_quimica"] = Group("cre", "calcario", "dolomito", "silex", "halita");
        colors["intrusiva"] = Group("granito", "granodiorito", "diorito", "gabro", "peridotito");
        colors["extrusiva"] = Group("riolito", "dacito", "andesito", "basalto", "picrobasalto");
        colors["metamorfica"] = Group("marmore", "quartzito", "skarn", "hornfels", "ardosia", "filito", "xisto", "gnaisse", "migmatito",
            "xisto_azul", "eclogito", "rocha_verde", "anfibolito", "xisto_verde", "granulito");
        return colors;
    }

    // Provincias geologicas.png e Vulcanismo.png (cor forte = ativo, escura = extinto): os NOMES são hipótese na calibração.
    public static readonly Dictionary<string, int[]> ProvinceColors = new()
    {
        ["orogeno"] = new[] { Rgb(153, 255, 204) },
        ["derrames"] = new[] { Rgb(153, 102, 153) },
    };

    public static readonly Dictionary<string, int[]> VolcanoColors = new()
    {
        ["arco"] = new[] { Rgb(0, 250, 50), Rgb(0, 62, 12) },
        ["colisao"] = new[] { Rgb(255, 255, 255), Rgb(63, 63, 63) },
        ["rifte"] = new[] { Rgb(250, 0, 0), Rgb(62, 0, 0) },
    };

    // Köppen em Clima.png (paleta de Beck et al. 2018, docs/calibracao): cor -> grupo.
    private static readonly Dictionary<int, char> ClimateColors = new[]
    {
        ('A', new[] { Rgb(0, 0, 255), Rgb(0, 119, 255), Rgb(70, 169, 255) }),
        ('B', new[] { Rgb(255, 0, 0), Rgb(255, 150, 150), Rgb(245, 163, 0), Rgb(255, 219, 99) }),
        ('C', new[] { Rgb(255, 255, 0), Rgb(198, 199, 0), Rgb(150, 150, 0), Rgb(150, 255, 150), Rgb(99, 199, 100), Rgb(50, 150, 51), Rgb(198, 255, 78), Rgb(102, 255, 51), Rgb(51, 191, 1) }),
        ('D', new[] { Rgb(198, 1, 199), Rgb(150, 50, 149), Rgb(76, 81, 181), Rgb(0, 255, 255), Rgb(56, 199, 255), Rgb(0, 126, 126) }),
        ('E', new[] { Rgb(178, 178, 178), Rgb(104, 104, 104) }),
    }.SelectMany(g => g.Item2.Select(c => (Color: c, Group: g.Item1))).ToDictionary(x => x.Color, x => x.Group);

    private static readonly double[,] Viridis =
    {
        { 0.267, 0.005, 0.329 }, { 0.279, 0.175, 0.483 }, { 0.230, 0.322, 0.546 }, { 0.173, 0.449, 0.558 }, { 0.128, 0.567, 0.551 },
        { 0.158, 0.684, 0.502 }, { 0.369, 0.789, 0.383 }, { 0.678, 0.864, 0.190 }, { 0.993, 0.906, 0.144 },
    };

    private static int Rgb(int r, int g, int b) => (r << 16) | (g << 8) | b;

    /// O que os mapas dizem do pixel, em palavras.
    public static string Facts(Terrain terrain, int pixel, Func<string, byte[]?> map)
    {
        int? ColorOf(string file) => map(file) is byte[] b ? Rgb(b[3 * pixel], b[3 * pixel + 1], b[3 * pixel + 2]) : null;
        var lines = new List<string> { $"Altitude: {Math.Round(terrain.H[pixel])} m" };
        if (ColorOf("Bedrock.png") is int rock && terrain.H[pixel] >= 0)
            lines.Add("Rocha: " + (RockTable.FirstOrDefault(r => r.Color == rock).Name ?? "sem leitura"));
        if (ColorOf("Clima.png") is int climate && ClimateColors.TryGetValue(climate, out char group))
            lines.Add("Clima: " + group switch { 'A' => "tropical", 'B' => "árido", 'C' => "temperado", 'D' => "continental", _ => "polar" });
        if (ColorOf("Provincias geologicas.png") is int province)
            lines.Add("Província: " + (ProvinceColors["orogeno"].Contains(province) ? "cinturão de montanhas"
                : ProvinceColors["derrames"].Contains(province) ? "derrames de basalto" : "comum"));
        if (map("Vulcanismo.png") is byte[] volcanoes)
        {
            // Para UM lugar basta medir até cada pixel vulcânico (a varredura do planeta inteiro é a de NearVolcano).
            var colors = VolcanoColors.Values.SelectMany(c => c).ToHashSet();
            var here = VecOf(pixel, terrain);
            bool near = false;
            for (int i = 0; i < terrain.H.Length && !near; i++)
                near = colors.Contains(Rgb(volcanoes[3 * i], volcanoes[3 * i + 1], volcanoes[3 * i + 2])) && Km(here, VecOf(i, terrain)) <= 300;
            lines.Add(near ? "Vulcanismo a menos de 300 km" : "Sem vulcanismo a 300 km");
        }
        return string.Join("\n", lines);
    }

    /// A posição 0..100 da cor na escala viridis (a mesma leitura de tools/build_natural.py).
    private static double ViridisIndex(int rgb)
    {
        double r = (rgb >> 16) / 255.0, g = ((rgb >> 8) & 255) / 255.0, b = (rgb & 255) / 255.0, best = double.MaxValue, at = 0;
        for (int i = 0; i < 8; i++)
        {
            double dr = Viridis[i + 1, 0] - Viridis[i, 0], dg = Viridis[i + 1, 1] - Viridis[i, 1], db = Viridis[i + 1, 2] - Viridis[i, 2];
            double t = Math.Clamp(((r - Viridis[i, 0]) * dr + (g - Viridis[i, 1]) * dg + (b - Viridis[i, 2]) * db) / (dr * dr + dg * dg + db * db), 0, 1);
            double er = r - Viridis[i, 0] - t * dr, eg = g - Viridis[i, 1] - t * dg, eb = b - Viridis[i, 2] - t * db;
            double d = er * er + eg * eg + eb * eb;
            if (d < best) { best = d; at = (i + t) / 8.0; }
        }
        return at * 100.0;
    }

    /// Os pixels onde a regra vale. maps: arquivo -> bytes RGB na grade do terreno.
    public static BitArray Candidates(ResourceRule rule, Terrain terrain, Dictionary<string, byte[]> maps)
    {
        int w = terrain.Size.X, h = terrain.Size.Y, n = w * h;
        var ok = new BitArray(n);
        bool sea = rule.Surface == "mar";
        for (int i = 0; i < n; i++)
        {
            float z = terrain.H[i];
            ok[i] = (z < 0f) == sea && z >= rule.ElevMin && z <= rule.ElevMax;
        }
        if (rule.SlopeMax < 90) FilterSlope(ok, rule.SlopeMax, terrain);
        if (rule.Rocks.Length > 0)
        {
            var colors = rule.Rocks.SelectMany(k => RockColors[k]).ToHashSet();
            Filter(ok, maps["Bedrock.png"], c => colors.Contains(c));
        }
        if (rule.Climates.Length > 0)
            Filter(ok, maps["Clima.png"], c => ClimateColors.TryGetValue(c, out char group) && rule.Climates.Contains(group.ToString()));
        if (rule.TreesMin > 0)  // composição: o canal azul é a fração de árvores
            Filter(ok, maps["Vegetação.png"], c => (c & 255) / 2.55 >= rule.TreesMin);
        if (rule.SoilMin > 0)
        {
            var seen = new Dictionary<int, bool>();
            Filter(ok, maps["Soil Richness.png"], c => seen.TryGetValue(c, out bool v) ? v : seen[c] = ViridisIndex(c) >= rule.SoilMin);
        }
        return ok;
    }

    /// A aptidão de cada pixel (0 = não serve). Sem indícios, todo candidato vale 100; com eles, a soma dos pesos dos que valem.
    public static byte[] Scores(ResourceRule rule, Terrain terrain, Dictionary<string, byte[]> maps, out BitArray[] factors)
    {
        var ok = Candidates(rule, terrain, maps);
        var scores = new byte[ok.Length];
        factors = rule.Prefer.Select(f => FactorMask(f, ok, terrain, maps)).ToArray();
        for (int i = 0; i < ok.Length; i++)
        {
            if (!ok[i]) continue;
            int score = 100;
            if (factors.Length > 0)
            {
                score = 0;
                for (int k = 0; k < factors.Length; k++)
                    if (factors[k][i]) score += rule.Prefer[k].Weight;
                score = Math.Min(score, 100);
                if (score < rule.MinScore) continue;
            }
            scores[i] = (byte)score;
        }
        return scores;
    }

    private static BitArray FactorMask(ResourceFactor f, BitArray ok, Terrain terrain, Dictionary<string, byte[]> maps)
    {
        var mask = new BitArray(ok);
        if (f.Rocks.Length > 0)
        {
            var colors = f.Rocks.SelectMany(k => RockColors[k]).ToHashSet();
            Filter(mask, maps["Bedrock.png"], c => colors.Contains(c));
        }
        if (f.Climates.Length > 0)
            Filter(mask, maps["Clima.png"], c => ClimateColors.TryGetValue(c, out char group) && f.Climates.Contains(group.ToString()));
        if (f.Provinces.Length > 0)
        {
            var colors = f.Provinces.SelectMany(k => ProvinceColors[k]).ToHashSet();
            Filter(mask, maps["Provincias geologicas.png"], c => colors.Contains(c));
        }
        if (f.Volcanoes.Length > 0) mask.And(NearVolcano(f.Volcanoes, f.VolcanoKm, terrain, maps["Vulcanismo.png"]));
        if (f.SlopeMax < 90) FilterSlope(mask, f.SlopeMax, terrain);
        return mask;
    }

    /// Os pixels a até km (pela superfície) de algum vulcanismo desses tipos.
    private static BitArray NearVolcano(string[] kinds, double km, Terrain terrain, byte[] rgb)
    {
        var colors = kinds.SelectMany(k => VolcanoColors[k]).ToHashSet();
        var near = new BitArray(terrain.Size.X * terrain.Size.Y);
        // Uma frente só, a partir de todo o vulcanismo: cada pixel passa aos vizinhos a origem mais próxima, e a distância é medida
        // até ela pela esfera. Um pixel entra uma vez, na ordem da distância.
        var queue = new PriorityQueue<(int Pixel, int Source), double>();
        var sources = new Dictionary<int, Vec>();
        for (int i = 0; i < near.Length; i++)
        {
            if (!colors.Contains(Rgb(rgb[3 * i], rgb[3 * i + 1], rgb[3 * i + 2]))) continue;
            sources[i] = VecOf(i, terrain);
            queue.Enqueue((i, i), 0);
        }
        while (queue.TryDequeue(out var item, out _))
        {
            if (near[item.Pixel]) continue;
            near[item.Pixel] = true;
            var from = sources[item.Source];
            foreach (var (dx, dy, _) in Terrain.Neighbors)
            {
                int q = terrain.Neighbor(item.Pixel, dx, dy);
                if (q < 0 || near[q]) continue;
                double d = Km(from, VecOf(q, terrain));
                if (d <= km) queue.Enqueue((q, item.Source), d);
            }
        }
        return near;
    }

    private static void Filter(BitArray ok, byte[] rgb, Func<int, bool> keep)
    {
        for (int i = 0; i < ok.Length; i++)
            if (ok[i]) ok[i] = keep(Rgb(rgb[3 * i], rgb[3 * i + 1], rgb[3 * i + 2]));
    }

    private static void FilterSlope(BitArray ok, double maxDegrees, Terrain terrain)
    {
        int w = terrain.Size.X, h = terrain.Size.Y;
        double dy = Math.PI * EvronGeo.RadiusKm / h * 1000.0, max = Math.Tan(maxDegrees * Math.PI / 180.0);
        for (int y = 0; y < h; y++)
        {
            // Perto do polo os pixels ficam estreitíssimos: o passo leste-oeste não desce de 1/5 do norte-sul.
            double dx = Math.Max(2 * Math.PI * EvronGeo.RadiusKm / w * 1000.0 * Math.Cos(Math.PI * (0.5 - (y + 0.5) / h)), dy / 5);
            for (int x = 0; x < w; x++)
            {
                int i = y * w + x;
                if (!ok[i]) continue;
                float z = terrain.H[i];
                double east = Math.Abs(terrain.H[y * w + (x + 1) % w] - z) / dx;
                double south = y + 1 < h ? Math.Abs(terrain.H[i + w] - z) / dy : 0;
                ok[i] = Math.Sqrt(east * east + south * south) <= max;
            }
        }
    }

    // SplitMix64: o mesmo número para a mesma semente e o mesmo pixel em qualquer versão do .NET e em qualquer ordem.
    private static double Uniform(int seed, int pixel)
    {
        ulong z = ((ulong)(uint)seed << 32 | (uint)pixel) + 0x9E3779B97F4A7C15UL;
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL;
        z ^= z >> 31;
        return ((z >> 11) + 1.0) / (1UL << 53);
    }

    private static Vec VecOf(int pixel, Terrain t)
    {
        int x = pixel % t.Size.X, y = pixel / t.Size.X;
        return Vec.FromLatLon(90.0 - (y + 0.5) * 180.0 / t.Size.Y, ((x + 0.5) / t.Size.X - 0.5) * 360.0);
    }

    private static double Km(Vec a, Vec b) => Vec.Angle(a, b) * EvronGeo.RadiusKm;

    /// Escolhe os centros: um sorteio sem reposição com peso (área do pixel × agrupamento), mantendo uma distância mínima entre eles.
    private static List<int> Centers(ResourceRule rule, byte[] scores, Terrain terrain, TerrainNoise noise)
    {
        int w = terrain.Size.X, h = terrain.Size.Y;
        var best = new PriorityQueue<int, double>();  // guarda os Pool de menor chave (a fila tira o de MAIOR: prioridade negada)
        for (int y = 0; y < h; y++)
        {
            double area = Math.Max(Math.Cos(Math.PI * (0.5 - (y + 0.5) / h)), 0.001);
            for (int x = 0; x < w; x++)
            {
                int i = y * w + x;
                if (scores[i] == 0) continue;
                double fit = scores[i] / 100.0;
                double key = -Math.Log(Uniform(rule.Seed, i)) / (area * fit * fit);  // aptidão alta concorre bem mais
                // O ruído custa caro: só é calculado para quem ainda pode entrar (o peso nunca passa de 1).
                if (best.Count == Pool && best.TryPeek(out _, out double worst) && key >= -worst) continue;
                double cluster = Math.Max(noise.Fbm(terrain.DirOf(i) * ClusterScale) - 0.3, 0.03) / 0.7;
                key /= cluster * cluster * cluster;
                if (best.Count < Pool) best.Enqueue(i, -key);
                else best.EnqueueDequeue(i, -key);
            }
        }
        var ordered = best.UnorderedItems.OrderByDescending(x => x.Priority).ThenBy(x => x.Element).Select(x => x.Element);
        double spacing = rule.Output == "area" ? 2 * rule.SizeKm : rule.SizeKm;
        var centers = new List<int>();
        var vectors = new List<Vec>();
        foreach (int p in ordered)
        {
            var v = VecOf(p, terrain);
            if (vectors.Any(o => Km(o, v) < spacing)) continue;
            centers.Add(p);
            vectors.Add(v);
            if (centers.Count == rule.Count) break;
        }
        return centers;
    }

    private static bool[] Matched(BitArray[] factors, int pixel) => factors.Select(f => f[pixel]).ToArray();

    private static readonly Dictionary<char, string> ClimateNames = new()
    {
        ['A'] = "tropical", ['B'] = "árido", ['C'] = "temperado", ['D'] = "continental", ['E'] = "polar",
    };

    /// Os dados de "Por que aqui?": {scored, score, min_score, factors: [{name, ok, weight}], conditions: [texto]}.
    public static Godot.Collections.Dictionary Explanation(ResourceRule rule, bool[] matched, int score)
    {
        var factors = new Godot.Collections.Array();
        for (int k = 0; k < rule.Prefer.Length; k++)
            factors.Add(new Godot.Collections.Dictionary { ["name"] = rule.Prefer[k].Name, ["weight"] = rule.Prefer[k].Weight, ["ok"] = k < matched.Length && matched[k] });
        var conditions = new Godot.Collections.Array { rule.Surface == "mar" ? "estar no mar" : "estar em terra" };
        if (rule.ElevMin > -13500) conditions.Add($"altitude de pelo menos {rule.ElevMin:0} m");
        if (rule.ElevMax < 9200) conditions.Add($"altitude de no máximo {rule.ElevMax:0} m");
        if (rule.SlopeMax < 90) conditions.Add($"declive de no máximo {rule.SlopeMax:0.##} graus");
        if (rule.Rocks.Length > 0)
            conditions.Add("rocha de um destes grupos: " + string.Join(", ", rule.Rocks.Select(k =>
                RockTable.FirstOrDefault(r => r.Code == k).Name ?? k.Replace('_', ' '))));
        if (rule.Climates.Length > 0) conditions.Add("clima " + string.Join(" ou ", rule.Climates.Select(c => ClimateNames[c[0]])));
        if (rule.TreesMin > 0) conditions.Add($"pelo menos {rule.TreesMin:0}% de árvores");
        if (rule.SoilMin > 0) conditions.Add($"riqueza do solo de pelo menos {rule.SoilMin:0} (leitura de baixa confiança)");
        return new Godot.Collections.Dictionary
        {
            ["scored"] = rule.Prefer.Length > 0, ["score"] = score, ["min_score"] = rule.MinScore, ["factors"] = factors, ["conditions"] = conditions,
        };
    }

    private static string Why(ResourceRule rule, BitArray[] factors, int pixel) =>
        string.Join("; ", rule.Prefer.Where((_, k) => factors[k][pixel]).Select(f => f.Name));

    /// As sugestões. protectedPixels: onde o autor já tem área deste recurso. A proteção entra DEPOIS da escolha dos centros: assim
    /// proteger ou suprimir uma sugestão não muda as outras.
    public static List<Proposal> Generate(ResourceRule rule, Terrain terrain, Dictionary<string, byte[]> maps, Func<int, bool> protectedPixels)
    {
        var scores = Scores(rule, terrain, maps, out var factors);
        var noise = new TerrainNoise();
        noise.SetSeed(rule.Seed);
        var centers = Centers(rule, scores, terrain, noise);
        var taken = new HashSet<int>();
        var proposals = new List<Proposal>();
        foreach (int center in centers)
        {
            var at = VecOf(center, terrain);
            var (lat, lon) = at.ToLatLon();
            if (rule.Output == "ponto")
            {
                proposals.Add(new Proposal { Center = center, Lat = lat, Lon = lon, RadiusKm = rule.SizeKm / 2, Score = scores[center], Why = Why(rule, factors, center), Matched = Matched(factors, center) });
                continue;
            }
            if (protectedPixels(center) || !taken.Add(center)) continue;
            var pixels = new List<int> { center };
            for (int k = 0; k < pixels.Count; k++)  // a própria lista é a fila da busca em largura
            {
                foreach (var (dx, dy) in new[] { (-1, 0), (1, 0), (0, -1), (0, 1) })
                {
                    int q = terrain.Neighbor(pixels[k], dx, dy);
                    if (q < 0 || scores[q] == 0 || taken.Contains(q) || protectedPixels(q)) continue;
                    // Borda irregular: o alcance varia de 0,55 a 1,45 do raio, em manchas de ~100 km.
                    if (Km(at, VecOf(q, terrain)) > rule.SizeKm * (0.55 + 0.9 * noise.Fbm(terrain.DirOf(q)))) continue;
                    taken.Add(q);
                    pixels.Add(q);
                }
            }
            double km2 = pixels.Sum(p => Territory.RowCellKm2(p / terrain.Size.X, terrain.Size.X, terrain.Size.Y));
            proposals.Add(new Proposal { Center = center, Lat = lat, Lon = lon, RadiusKm = rule.SizeKm, Km2 = km2, Pixels = pixels.ToArray(), Score = scores[center], Why = Why(rule, factors, center), Matched = Matched(factors, center) });
        }
        return proposals;
    }
}
