using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using Godot;

namespace Evron;

/// Geração de sugestões no banco (etapa 2 do plano de recursos). Regra de autoria: a geração só substitui ocorrências GERADAS e
/// não fixadas. Manuais e fixadas nunca mudam, e editar uma gerada a fixa. O que o autor tira vira supressão e não volta.
public partial class Registry
{
    const string GenerationMigration = """
        alter table resource_type add column rule text;
        alter table resource_occurrence add column fixed integer not null default 0 check (fixed in (0, 1));
        alter table resource_occurrence add column generation_id integer;
        alter table resource_occurrence add column gen_lat real;
        alter table resource_occurrence add column gen_lon real;
        alter table resource_occurrence add column gen_km real;

        -- Sem chave estrangeira para o tipo: excluir um recurso (e desfazer) não pode esbarrar no histórico dele.
        create table resource_generation(
            id integer primary key autoincrement,
            type_id integer not null,
            algorithm integer not null,
            rule text not null,
            layers text not null,
            created_at integer not null default (unixepoch()));
        create table resource_suppression(
            id integer primary key autoincrement,
            type_id integer not null,
            lat real not null,
            lon real not null,
            radius_km real not null,
            generation_id integer,
            created_at integer not null default (unixepoch()));
        create index resource_suppression_type on resource_suppression(type_id);
        """;

    static readonly string[] GenerationColumns = { "type_id", "algorithm", "rule", "layers", "created_at", "terrain_hash" };
    static readonly string[] SuppressionColumns = { "type_id", "lat", "lon", "radius_km", "generation_id", "created_at" };

    /// A regra gravada do recurso ("" = nenhuma).
    public string ResourceRuleOf(long typeId) => _db.Scalar("select rule from resource_type where id = @0", typeId)?.ToString() ?? "";

    /// Os mapas que a regra precisa (vazio também se ela não vale).
    public string[] RuleMaps(string rule)
    {
        try { return Evron.ResourceRule.Parse(rule).Maps(); }
        catch (ArgumentException) { return System.Array.Empty<string>(); }
    }

    /// Grava a regra no recurso sem gerar nada (um perfil recém-adicionado).
    public ResourceEdit SetResourceRule(long typeId, string rule)
    {
        string json = Evron.ResourceRule.Parse(rule).ToJson();
        return Change("resource_type", TypeColumns, typeId, () => _db.Run("update resource_type set rule = @0 where id = @1", json, typeId));
    }

    // ---- testes do gerador (estabilidade e avaliação às cegas) ----

    /// Quanto o resultado muda com pequenas variações. maps como em PlanResources. Devolve:
    /// area_overlap: o pior dos sobrepostos (0..1, por área) entre os lugares aptos da regra e os dela com pesos, mínimo, altitude e
    /// declive variados em ±10%; seed_agreement: a parte das sugestões que têm uma sugestão de outra semente a até nearKm (média de 4 sementes);
    /// random_agreement: o mesmo para pontos sorteados entre TODOS os lugares do mesmo tipo de superfície (o acaso, para comparar).
    public Godot.Collections.Dictionary RuleStability(string rule, Terrain terrain, Godot.Collections.Dictionary maps, double nearKm)
    {
        var baseRule = Evron.ResourceRule.Parse(rule);
        var bytes = baseRule.Maps().ToDictionary(file => file, file => maps[file].As<Image>().GetData());
        var scores = ResourceGenerator.Scores(baseRule, terrain, bytes, out _);
        double worst = 1;
        foreach (double k in new[] { 0.9, 1.1 })
        {
            var changed = new List<Evron.ResourceRule>();
            Evron.ResourceRule Copy() => Evron.ResourceRule.Parse(baseRule.ToJson());
            if (baseRule.Prefer.Length > 0)
            {
                var weights = Copy();
                foreach (var f in weights.Prefer) f.Weight = Math.Clamp((int)Math.Round(f.Weight * k), 1, 100);
                changed.Add(weights);
                var minimum = Copy();
                minimum.MinScore = Math.Clamp((int)Math.Round(minimum.MinScore * k), 1, 100);
                changed.Add(minimum);
            }
            var limits = Copy();
            limits.ElevMin *= limits.ElevMin > 0 ? k : 2 - k;
            limits.ElevMax *= limits.ElevMax > 0 ? k : 2 - k;
            if (limits.ElevMin > limits.ElevMax) limits.ElevMin = limits.ElevMax;
            if (limits.SlopeMax < 90) limits.SlopeMax = Math.Min(limits.SlopeMax * k, 90);
            foreach (var f in limits.Prefer)
                if (f.SlopeMax < 90) f.SlopeMax = Math.Min(f.SlopeMax * k, 90);
            limits.TreesMin = Math.Min(limits.TreesMin * k, 100);
            limits.SoilMin = Math.Min(limits.SoilMin * k, 100);
            changed.Add(limits);
            foreach (var other in changed)
                worst = Math.Min(worst, Overlap(scores, ResourceGenerator.Scores(other, terrain, bytes, out _), terrain));
        }

        List<Vec> Picks(int seed)
        {
            var copy = Evron.ResourceRule.Parse(baseRule.ToJson());
            copy.Seed = seed;
            copy.Output = "ponto";  // o que se compara são os lugares escolhidos
            copy.SizeKm = baseRule.Output == "area" ? Math.Min(2 * baseRule.SizeKm, 2000) : baseRule.SizeKm;
            return ResourceGenerator.Generate(copy, terrain, bytes, _ => false).Select(p => Vec.FromLatLon(p.Lat, p.Lon)).ToList();
        }
        double Agreement(List<Vec> from, List<Vec> to) =>
            from.Count == 0 ? 0 : from.Count(a => to.Any(b => Vec.Angle(a, b) * EvronGeo.RadiusKm <= nearKm)) / (double)from.Count;

        var first = Picks(baseRule.Seed);
        double agreement = 0, random = 0;
        for (int i = 1; i <= 4; i++)
        {
            agreement += Agreement(first, Picks(baseRule.Seed + i * 7919)) / 4;
            random += Agreement(first, RandomPlaces(baseRule.Surface, baseRule.Seed + i, first.Count, terrain)
                .Select(p => Vec.FromLatLon(p.Lat, p.Lon)).ToList()) / 4;
        }
        return new Godot.Collections.Dictionary { ["area_overlap"] = worst, ["seed_agreement"] = agreement, ["random_agreement"] = random, ["count"] = first.Count };
    }

    static double Overlap(byte[] a, byte[] b, Terrain terrain)
    {
        double both = 0, either = 0;
        for (int i = 0; i < a.Length; i++)
        {
            if (a[i] == 0 && b[i] == 0) continue;
            double km2 = Territory.RowCellKm2(i / terrain.Size.X, terrain.Size.X, terrain.Size.Y);
            either += km2;
            if (a[i] != 0 && b[i] != 0) both += km2;
        }
        return either == 0 ? 1 : both / either;
    }

    /// Pontos sorteados por área entre TODA a terra (ou todo o mar), sem olhar a regra: o grupo de comparação.
    static List<(double Lat, double Lon)> RandomPlaces(string surface, int seed, int count, Terrain terrain)
    {
        var random = new System.Random(seed);
        var places = new List<(double, double)>();
        for (int tries = 0; places.Count < count && tries < count * 1000 + 1000; tries++)
        {
            double lat = Math.Asin(2 * random.NextDouble() - 1) * 180 / Math.PI, lon = random.NextDouble() * 360 - 180;
            if (terrain.H[terrain.PixelOf(EvronGeo.Dir(lat, lon))] < 0f == (surface == "mar")) places.Add((lat, lon));
        }
        return places;
    }

    /// A aptidão que a regra dá a cada lugar (lat0, lon0, lat1, lon1, ...): 0 = o lugar não serve. Para o gabarito do autor.
    public int[] ScorePlaces(string rule, Terrain terrain, Godot.Collections.Dictionary maps, double[] latLon)
    {
        var parsed = Evron.ResourceRule.Parse(rule);
        var bytes = parsed.Maps().ToDictionary(file => file, file => maps[file].As<Image>().GetData());
        var scores = ResourceGenerator.Scores(parsed, terrain, bytes, out _);
        var result = new int[latLon.Length / 2];
        for (int i = 0; i < result.Length; i++) result[i] = scores[terrain.PixelOf(EvronGeo.Dir(latLon[2 * i], latLon[2 * i + 1]))];
        return result;
    }

    /// Os mapas que explicar esta ocorrência pede (os da regra que a gerou); vazio se ela não veio da geração.
    public string[] ExplanationMaps(long occurrenceId) =>
        GenerationOf(occurrenceId) is var (rule, _, _) ? Evron.ResourceRule.Parse(rule).Maps() : System.Array.Empty<string>();

    /// Por que uma sugestão aplicada foi escolhida: a regra da geração dela, avaliada no centro original com os mapas e o relevo de
    /// hoje. Vazio se não veio da geração. Traz também lat e lon desse centro.
    public Godot.Collections.Dictionary ExplainOccurrence(long occurrenceId, Terrain terrain, Godot.Collections.Dictionary maps)
    {
        if (GenerationOf(occurrenceId) is not var (json, lat, lon)) return new Godot.Collections.Dictionary();
        var rule = Evron.ResourceRule.Parse(json);
        var bytes = rule.Maps().ToDictionary(file => file, file => maps[file].As<Image>().GetData());
        ResourceGenerator.Scores(rule, terrain, bytes, out var factors);
        int pixel = terrain.PixelOf(EvronGeo.Dir(lat, lon));
        var matched = factors.Select(f => f[pixel]).ToArray();
        // A soma é refeita aqui porque Scores zera quem fica abaixo do mínimo, e o cartão mostra quanto faltou.
        int score = rule.Prefer.Length == 0 ? 100 : Math.Min(100, rule.Prefer.Where((_, k) => matched[k]).Sum(f => f.Weight));
        var why = ResourceGenerator.Explanation(rule, matched, score);
        why["lat"] = lat;
        why["lon"] = lon;
        return why;
    }

    (string Rule, double Lat, double Lon)? GenerationOf(long occurrenceId)
    {
        var r = _db.Rows("select g.rule, o.gen_lat, o.gen_lon from resource_occurrence o join resource_generation g on g.id = o.generation_id " +
            "where o.id = @0 and o.gen_lat is not null", occurrenceId);
        return r.Count == 0 ? null : (Str(r[0][0]), Convert.ToDouble(r[0][1]), Convert.ToDouble(r[0][2]));
    }

    /// O mesmo para o GDScript: [{lat, lon}].
    public Godot.Collections.Array RandomSites(string surface, long seed, long count, Terrain terrain)
    {
        var sites = new Godot.Collections.Array();
        foreach (var (lat, lon) in RandomPlaces(surface, (int)seed, (int)count, terrain))
            sites.Add(new Godot.Collections.Dictionary { ["lat"] = lat, ["lon"] = lon });
        return sites;
    }

    /// O que os mapas dizem de um lugar, em palavras (rocha, clima, altitude, província e vulcanismo perto). maps: os quatro mapas em RGB8.
    public string PlaceFacts(Terrain terrain, Godot.Collections.Dictionary maps, double lat, double lon)
    {
        int pixel = terrain.PixelOf(EvronGeo.Dir(lat, lon));
        return ResourceGenerator.Facts(terrain, pixel, file => maps.ContainsKey(file) ? maps[file].As<Image>().GetData() : null);
    }

    /// "" se a regra vale; senão o que está errado.
    public string CheckResourceRule(string rule)
    {
        try { Evron.ResourceRule.Parse(rule); return ""; }
        catch (ArgumentException e) { return e.Message; }
    }

    string GenerationSignature(long typeId) => JsonSerializer.Serialize(new[]
    {
        _db.Rows("select id, kind, lat, lon, origin, fixed from resource_occurrence where type_id = @0 order by id", typeId),
        _db.Rows("select id from resource_suppression where type_id = @0 order by id", typeId),
    });

    /// A regra deste recurso cobre tudo o que serve? Só em áreas. Sem dizer na regra, vegetação e animal cobrem; o resto é em manchas.
    public bool CoversArea(long typeId, string rule)
    {
        try { return Covers(typeId, Evron.ResourceRule.Parse(rule)); }
        catch (ArgumentException) { return false; }
    }

    bool Covers(long typeId, Evron.ResourceRule rule) => rule.Output == "area" && (rule.Spread != "" ? rule.Spread == "cobertura"
        : _db.Scalar("select category from resource_type where id = @0", typeId)?.ToString() is "vegetal" or "animal");

    /// A prévia: não grava nada. maps: arquivo -> Image RGB8 na grade do terreno; layer: a camada pintada do recurso.
    public ResourcePlan PlanResources(long typeId, string rule, Terrain terrain, Territory layer, Godot.Collections.Dictionary maps)
    {
        var plan = new ResourcePlan { TypeId = typeId };
        try
        {
            plan.Rule = Evron.ResourceRule.Parse(rule);
            if (_db.Scalar("select 1 from resource_type where id = @0", typeId) == null) throw new ArgumentException($"recurso {typeId} não existe");
            var bytes = new Dictionary<string, byte[]>();
            foreach (var file in plan.Rule.Maps())
            {
                if (!maps.ContainsKey(file) || maps[file].As<Image>() is not Image image) throw new ArgumentException($"falta o mapa {file}");
                if (image.GetSize() != terrain.Size || image.GetFormat() != Image.Format.Rgb8) throw new ArgumentException($"o mapa {file} não está na grade do terreno em RGB");
                bytes[file] = image.GetData();
            }

            var protectedAreas = new HashSet<int>();
            var protectedPoints = new List<Vec>();
            foreach (var r in _db.Rows("select id, kind, lat, lon, origin, fixed from resource_occurrence where type_id = @0 order by id", typeId))
            {
                long id = Convert.ToInt64(r[0]);
                bool replaceable = Str(r[4]) == "gerada" && Convert.ToInt64(r[5]) == 0;
                if (replaceable)
                {
                    plan.Replaced.Add(id);
                    if (Str(r[1]) == "area") plan.ReplacedAreas.Add((int)id);
                    continue;
                }
                plan.ProtectedCount++;
                if (Str(r[1]) == "area") protectedAreas.Add((int)id);
                else protectedPoints.Add(Vec.FromLatLon(Convert.ToDouble(r[2]), Convert.ToDouble(r[3])));
            }

            plan.Cover = Covers(typeId, plan.Rule);
            var proposals = ResourceGenerator.Generate(plan.Rule, terrain, bytes, p => protectedAreas.Contains(layer.Get(p)), plan.Cover);
            var suppressed = _db.Rows("select lat, lon, radius_km from resource_suppression where type_id = @0", typeId)
                .Select(r => (At: Vec.FromLatLon(Convert.ToDouble(r[0]), Convert.ToDouble(r[1])), Km: Convert.ToDouble(r[2]))).ToList();
            // Uma gerada fixada fica onde está: a sugestão que a originou não aparece de novo.
            foreach (var r in _db.Rows("select gen_lat, gen_lon, gen_km from resource_occurrence where type_id = @0 and fixed = 1 and gen_lat is not null", typeId))
                protectedPoints.Add(Vec.FromLatLon(Convert.ToDouble(r[0]), Convert.ToDouble(r[1])));
            foreach (var p in proposals)
            {
                var at = Vec.FromLatLon(p.Lat, p.Lon);
                if (suppressed.Any(s => Vec.Angle(s.At, at) * EvronGeo.RadiusKm <= s.Km)) plan.SuppressedCount++;
                else if (!protectedPoints.Any(q => Vec.Angle(q, at) * EvronGeo.RadiusKm <= Math.Min(p.RadiusKm, 100))) plan.Proposals.Add(p);
            }
            plan.Signature = GenerationSignature(typeId);
            plan.TerrainHash = TerrainHash(terrain);
            plan.LayerVersion = layer.Version;
        }
        catch (ArgumentException e) { plan.Error = e.Message; }
        return plan;
    }

    /// Aplica a prévia: sai o que era gerado e não fixado, entram as sugestões aceitas, as tiradas viram supressão e a regra fica
    /// gravada no recurso. Devolve os comandos já aplicados, na ordem (para um desfazer só). Vazio se o mundo mudou desde a prévia.
    public Godot.Collections.Array ApplyGeneration(ResourcePlan plan, Territory layer)
    {
        var commands = new Godot.Collections.Array();
        if (plan.Error != "" || plan.LayerVersion != layer.Version || plan.Signature != GenerationSignature(plan.TypeId)) return commands;
        var painted = new Dictionary<int, int>();  // pixel -> dono novo
        var edits = _db.Tx(() =>
        {
            var list = new List<ResourceEdit>();
            long type = plan.TypeId;
            string rule = plan.Rule.ToJson();
            list.Add(Change("resource_type", TypeColumns, type, () => _db.Run("update resource_type set rule = @0 where id = @1", rule, type)));
            // O histórico guarda o jeito que valeu de fato: mudar a categoria depois não muda o que esta geração diz.
            var used = Evron.ResourceRule.Parse(rule);
            used.Spread = plan.Cover ? "cobertura" : "manchas";
            long generation = _db.Insert("insert into resource_generation(type_id, algorithm, rule, layers, terrain_hash) values (@0, @1, @2, @3, @4)",
                type, ResourceGenerator.AlgorithmVersion, used.ToJson(), JsonSerializer.Serialize(plan.Rule.Maps().Prepend("altitude")), plan.TerrainHash);
            list.Add(Edit("resource_generation", GenerationColumns, generation, null));
            foreach (long id in plan.Replaced) list.Add(Remove("resource_occurrence", OccurrenceColumns, id));
            if (plan.ReplacedAreas.Count > 0)
                for (int p = 0; p < layer.Size.X * layer.Size.Y; p++)
                    if (plan.ReplacedAreas.Contains(layer.Get(p))) painted[p] = 0;
            foreach (var s in plan.Proposals)
            {
                if (s.Rejected)
                {
                    list.Add(AddSuppression(type, s.Lat, s.Lon, Math.Min(s.RadiusKm, 200), generation));
                    continue;
                }
                bool area = plan.IsArea;
                // O motivo fica na anotação: quem abrir a ocorrência vê por que ela foi sugerida.
                string? note = plan.Scored ? $"Aptidão {s.Score}: {s.Why}." : null;
                long id = _db.Insert("insert into resource_occurrence(type_id, kind, lat, lon, origin, generation_id, gen_lat, gen_lon, gen_km, note, reserve) " +
                    "values (@0, @1, @2, @3, 'gerada', @4, @5, @6, @7, @8, @9)",
                    type, area ? "area" : "ponto", area ? null : s.Lat, area ? null : s.Lon, generation, s.Lat, s.Lon, s.RadiusKm, note,
                    s.Reserve > 0 ? s.Reserve : null);
                if (area && id >= ResourcePlan.PreviewBase) throw new InvalidOperationException("o mundo chegou ao limite de áreas de recurso");
                list.Add(Edit("resource_occurrence", OccurrenceColumns, id, null));
                foreach (int p in s.Pixels) painted[p] = (int)id;
            }
            return list;
        });
        foreach (var edit in edits) commands.Add(edit);
        if (layer.Rewrite(painted) is TerritoryEdit pixels) commands.Add(pixels);  // depois do banco: pintar não falha
        return commands;
    }

    ResourceEdit AddSuppression(long type, double lat, double lon, double km, long? generation)
    {
        long id = _db.Insert("insert into resource_suppression(type_id, lat, lon, radius_km, generation_id) values (@0, @1, @2, @3, @4)",
            type, lat, lon, km, generation);
        return Edit("resource_suppression", SuppressionColumns, id, null);
    }

    /// Antes de excluir uma sugestão gerada: registra a supressão, para ela não reaparecer. null se a ocorrência não veio da geração.
    public ResourceEdit? SuppressOccurrence(long id)
    {
        var r = _db.Rows("select type_id, gen_lat, gen_lon, gen_km, generation_id from resource_occurrence where id = @0 and gen_lat is not null", id);
        if (r.Count == 0) return null;
        return _db.Tx(() => AddSuppression(Convert.ToInt64(r[0][0]), Convert.ToDouble(r[0][1]), Convert.ToDouble(r[0][2]),
            Math.Min(Convert.ToDouble(r[0][3]), 200), r[0][4] == null ? null : Convert.ToInt64(r[0][4])));
    }

    public long SuppressionCount(long typeId) => Convert.ToInt64(_db.Scalar("select count(*) from resource_suppression where type_id = @0", typeId));

    /// Libera todas as supressões do recurso. Devolve os comandos para um desfazer só.
    public Godot.Collections.Array ClearSuppressions(long typeId)
    {
        var commands = new Godot.Collections.Array();
        var edits = _db.Tx(() => _db.Rows("select id from resource_suppression where type_id = @0 order by id", typeId)
            .Select(r => Remove("resource_suppression", SuppressionColumns, Convert.ToInt64(r[0]))).ToList());
        foreach (var edit in edits) commands.Add(edit);
        return commands;
    }

    /// Fixar protege uma ocorrência gerada: a geração não a substitui.
    public ResourceEdit SetFixed(long id, bool on) => Change("resource_occurrence", OccurrenceColumns, id, () => _db.Run(
        "update resource_occurrence set fixed = @0 where id = @1", on ? 1 : 0, id));
}
