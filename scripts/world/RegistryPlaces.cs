using System;
using System.Collections.Generic;
using System.Linq;
using Godot;
using Godot.Collections;
using GArray = Godot.Collections.Array;

namespace Evron;

/// Lugares, presenças no mapa e demografia (etapa 5 do plano de domínios). Só guarda e consulta; o desenho no globo é de
/// view/place_layer.gd e a ficha, de ui/sheet_panel.gd.
///
/// · Lugar: um ponto (radius_km = 0) ou uma ÁREA APROXIMADA em disco (radius_km > 0), compartilhável: o mesmo lugar em várias fichas é o
///   mesmo registro. Polígonos de fronteira não existem ainda (shortcut: disco, até haver um editor de contornos).
/// · Presença: entidade + lugar + função (capital, sede, território...) + validade [início, fim). A CAMADA do mapa vem do tipo da entidade
///   (país = política; cultura = cultural; etnia = étnica; idioma = linguística; religião = religiosa; raça = habitat): fronteira política,
///   presença cultural, distribuição étnica, área linguística e presença religiosa são camadas diferentes, e nenhuma implica a outra.
/// · Estimativa: o que se conta (habitantes, integrantes, falantes ou adeptos, conforme o tipo da entidade) num lugar e numa data, como faixa
///   numérica OU só como nível (baixa/média/alta). Nível nunca vira número: não há conversão automática.
/// · Distribuição: a composição percentual de uma população de referência (a entidade-sujeito, num lugar e numa data) por raça, etnia, cultura,
///   religião ou idioma, declarando se as categorias são exclusivas e se a lista é completa. Só a distribuição completa e exclusiva soma 100%.
///   Duas distribuições (marginais) nunca geram um cruzamento: não existe consulta que faça isso, de propósito.
public partial class Registry
{
    const string PlacesMigration = """
        create table place(
            id integer primary key,
            name text not null,
            kind text not null default 'assentamento' check (kind in ('assentamento','regiao','local_sagrado','natural','outro')),
            lat real not null check (lat >= -90 and lat <= 90),
            lon real not null check (lon >= -180 and lon <= 180),
            radius_km real not null default 0 check (radius_km >= 0),
            note text,
            created_at integer not null default (unixepoch()));
        create index place_name on place(name collate nocase);

        create table presence(
            id integer primary key,
            entity_id integer not null references entity(id),
            place_id integer not null references place(id),
            role text not null check (role in ('capital','sede','origem','presenca','centro_cultural','lugar_sagrado','territorio','reivindicacao','outro')),
            valid_from integer not null,
            valid_to integer not null,
            certainty text not null default 'media' check (certainty in ('alta','media','baixa','desconhecida')),
            note text,
            check (valid_from < valid_to));
        create index presence_entity on presence(entity_id);
        create index presence_place on presence(place_id);

        -- low/high: faixa numérica (iguais = exato). level: só quando não há número. Nunca os dois.
        create table population_estimate(
            id integer primary key,
            subject_id integer not null references entity(id),
            place_id integer not null references place(id),
            t integer not null,
            low real,
            high real,
            level text check (level in ('baixa','media','alta')),
            certainty text not null default 'media' check (certainty in ('alta','media','baixa','desconhecida')),
            source text,
            check ((low is null and high is null and level is not null) or (low is not null and high is not null and level is null and low >= 0 and high >= low)));
        create index estimate_subject on population_estimate(subject_id, place_id, t);

        create table distribution(
            id integer primary key,
            subject_id integer not null references entity(id),
            place_id integer not null references place(id),
            t integer not null,
            dimension text not null check (dimension in ('raca','etnia','cultura','religiao','idioma')),
            denominator_id integer references population_estimate(id),
            exclusive integer not null check (exclusive in (0, 1)),
            complete integer not null check (complete in (0, 1)),
            certainty text not null default 'media' check (certainty in ('alta','media','baixa','desconhecida')),
            source text);
        create index distribution_subject on distribution(subject_id, place_id, dimension, t);

        create table distribution_share(
            distribution_id integer not null references distribution(id),
            category_id integer not null references entity(id),
            pct real not null check (pct >= 0 and pct <= 100),
            primary key (distribution_id, category_id));
        """;

    static readonly string[] Layers = { "politica", "cultural", "etnica", "linguistica", "religiosa", "racial" };

    /// A camada do mapa de uma entidade, pelo tipo dela.
    static string LayerOf(string kind) => kind switch
    {
        "pais" => "politica", "cultura" => "cultural", "etnia" => "etnica", "idioma" => "linguistica", "religiao" => "religiosa", _ => "racial",
    };

    /// O que se conta para esse tipo de entidade. Contagens de bases diferentes nunca se somam entre si.
    static string BasisOf(string kind) => kind switch
    {
        "pais" => "habitantes", "idioma" => "falantes", "religiao" => "adeptos", _ => "integrantes",
    };

    static readonly System.Collections.Generic.Dictionary<string, string> DimensionKind = new()
    {
        ["raca"] = "raca", ["etnia"] = "etnia", ["cultura"] = "cultura", ["religiao"] = "religiao", ["idioma"] = "idioma",
    };

    // ---- lugares ----

    /// Cria um lugar. radiusKm = 0: ponto; > 0: área aproximada em disco. lat de −90 a 90 e lon de −180 a 180, em graus.
    public long AddPlace(string name, string kind, double lat, double lon, double radiusKm, string note)
    {
        if (!double.IsFinite(lat) || !double.IsFinite(lon) || !double.IsFinite(radiusKm)) throw new ArgumentException("coordenadas inválidas");
        return _db.Insert("insert into place(name, kind, lat, lon, radius_km, note) values (@0, @1, @2, @3, @4, @5)",
            Clean(name), kind, lat, lon, radiusKm, note == "" ? null : note);
    }

    public Dictionary Place(long id)
    {
        var r = _db.Rows("select id, name, kind, lat, lon, radius_km, note from place where id = @0", id);
        if (r.Count == 0) throw new ArgumentException($"lugar {id} não existe");
        var d = PlaceDict(r[0]);
        d["vertex_count"] = Convert.ToInt64(_db.Scalar("select count(*) from place_vertex where place_id = @0", id));
        return d;
    }

    static Dictionary PlaceDict(object?[] r) => new()
    {
        ["id"] = Convert.ToInt64(r[0]), ["name"] = Str(r[1]), ["kind"] = Str(r[2]), ["lat"] = Convert.ToDouble(r[3]), ["lon"] = Convert.ToDouble(r[4]),
        ["radius_km"] = Convert.ToDouble(r[5]), ["note"] = Str(r[6]),
    };

    /// Lugares cujo nome contém o texto (sem diferenciar maiúsculas nem acentos); vazio lista todos (até 200), por nome.
    public Array<Dictionary> Places(string text)
    {
        return new(_db.Rows("select id, name, kind, lat, lon, radius_km, note from place order by name collate nocase, id")
            .Where(r => Matches(Str(r[1]), text)).Take(200).Select(PlaceDict));
    }

    /// Exclui um lugar criado por engano: recusa se alguma presença, estimativa ou distribuição o usa.
    public void DeletePlace(long id)
    {
        long uses = Convert.ToInt64(_db.Scalar("select (select count(*) from presence where place_id = @0) + (select count(*) from population_estimate where place_id = @0) + (select count(*) from distribution where place_id = @0)", id));
        if (uses > 0) throw new ArgumentException($"o lugar {id} está em uso ({uses} registros)");
        _db.Run("delete from place_vertex where place_id = @0", id);
        _db.Run("delete from place where id = @0", id);
    }

    // ---- presenças ----

    /// A entidade está no lugar, com essa função, sem prazo. certainty: alta | media | baixa | desconhecida.
    public long AddPresence(long entityId, long placeId, string role, string certainty) =>
        AddPresenceDuring(entityId, placeId, role, certainty, Always, Forever);

    /// Idem, em [from, to). Recusa repetir entidade + lugar + função em períodos sobrepostos (o mesmo lugar é reutilizado, não duplicado).
    public long AddPresenceDuring(long entityId, long placeId, string role, string certainty, long from, long to)
    {
        long dup = Convert.ToInt64(_db.Scalar(
            "select count(*) from presence where entity_id = @0 and place_id = @1 and role = @2 and valid_from < @4 and @3 < valid_to", entityId, placeId, role, from, to));
        if (dup > 0) throw new ArgumentException("essa presença já existe nesse período");
        return _db.Insert("insert into presence(entity_id, place_id, role, valid_from, valid_to, certainty) values (@0, @1, @2, @3, @4, @5)",
            entityId, placeId, role, from, to, certainty);
    }

    /// Encerra uma presença em aberto em t (fim excluído), como a perda de uma capital.
    public void EndPresence(long presenceId, long t)
    {
        if (_db.Run("update presence set valid_to = @0 where id = @1 and valid_to = @2 and valid_from < @0", t, presenceId, Forever) == 0)
            throw new ArgumentException($"a presença {presenceId} não está em aberto antes de {t}");
    }

    public void DeletePresence(long presenceId) => _db.Run("delete from presence where id = @0", presenceId);

    const string PresenceSelect =
        "select p.id, p.entity_id, e.kind, p.role, p.certainty, pl.id, pl.name, pl.kind, pl.lat, pl.lon, pl.radius_km, p.valid_from, p.valid_to, " +
        // o nome principal vigente em t e, se não houver, o atual: no mesmo SELECT, sem uma consulta por presença
        "coalesce((select n.name from entity_name n where n.entity_id = e.id and n.role = 'principal' and n.valid_from <= @0 and @0 < n.valid_to), " +
        "(select n.name from entity_name n where n.entity_id = e.id and n.role = 'principal' and n.valid_to = 9223372036854775807)), " +
        "(select count(*) from place_vertex v where v.place_id = pl.id) " +
        "from presence p join entity e on e.id = p.entity_id join place pl on pl.id = p.place_id " +
        "where p.valid_from <= @0 and @0 < p.valid_to";

    /// Cada presença: id, entity_id, entity, kind, layer, role, certainty, place_id, place, place_kind, lat/lon (o ponto, o centro do disco ou do contorno),
    /// radius_km (0 se ponto ou contorno), vertices (lat0, lon0, lat1, lon1...; vazio se não é contorno), area_km2 (0 se ponto), from e to.
    static Dictionary PresenceDict(object?[] r, System.Collections.Generic.Dictionary<long, (double[] Flat, double Area)> shapes)
    {
        double radius = Convert.ToDouble(r[10]);
        double[] flat = new double[0];
        double area = radius > 0 ? 2 * Math.PI * EvronGeo.RadiusKm * EvronGeo.RadiusKm * (1 - Math.Cos(radius / EvronGeo.RadiusKm)) : 0;
        if (shapes.TryGetValue(Convert.ToInt64(r[5]), out var s)) (flat, area) = s;
        return new Dictionary
        {
            ["id"] = Convert.ToInt64(r[0]), ["entity_id"] = Convert.ToInt64(r[1]), ["entity"] = Str(r[13]), ["kind"] = Str(r[2]),
            ["layer"] = LayerOf(Str(r[2])), ["role"] = Str(r[3]), ["certainty"] = Str(r[4]), ["place_id"] = Convert.ToInt64(r[5]), ["place"] = Str(r[6]),
            ["place_kind"] = Str(r[7]), ["lat"] = Convert.ToDouble(r[8]), ["lon"] = Convert.ToDouble(r[9]), ["radius_km"] = radius,
            ["vertices"] = flat, ["area_km2"] = area, ["from"] = Convert.ToInt64(r[11]), ["to"] = Convert.ToInt64(r[12]),
        };
    }

    /// Monta os dicionários das presenças; os contornos (todos de uma vez, numa consulta só) vêm com os vértices e a área.
    Array<Dictionary> BuildPresences(System.Collections.Generic.IEnumerable<object?[]> rows)
    {
        var list = rows.ToList();
        var shapes = new System.Collections.Generic.Dictionary<long, (double[] Flat, double Area)>();
        var ids = list.Where(r => Convert.ToInt64(r[14]) > 0).Select(r => Convert.ToInt64(r[5])).Distinct().ToList();
        if (ids.Count > 0)
        {
            var byPlace = ids.ToDictionary(i => i, _ => new System.Collections.Generic.List<double>());
            foreach (var v in _db.Rows($"select place_id, lat, lon from place_vertex where place_id in ({string.Join(",", ids)}) order by place_id, seq"))
            {
                var l = byPlace[Convert.ToInt64(v[0])];
                l.Add(Convert.ToDouble(v[1]));
                l.Add(Convert.ToDouble(v[2]));
            }
            foreach (var (id, l) in byPlace)
            {
                var flat = l.ToArray();
                shapes[id] = (flat, PlaceGeometry.AreaKm2(PlaceGeometry.ToVecs(flat)));
            }
        }
        return new(list.Select(r => PresenceDict(r, shapes)));
    }

    /// As presenças de uma entidade no instante t.
    public Array<Dictionary> PresencesOf(long entityId, long t) => BuildPresences(
        _db.Rows(PresenceSelect + " and p.entity_id = @1 order by pl.name collate nocase, p.id", t, entityId));

    /// O que o mapa desenha em t: as presenças das camadas pedidas (lista vazia = nenhuma camada, nada), de uma entidade só (onlyEntity ≠ 0) ou de todas.
    public Array<Dictionary> MapItems(string[] layers, long onlyEntity, long t) => BuildPresences(
        _db.Rows(PresenceSelect + " and (@1 = 0 or p.entity_id = @1) order by p.id", t, onlyEntity)
           .Where(r => layers.Contains(LayerOf(Str(r[2])))));

    /// As presenças que cobrem o ponto (lat, lon) em t: o ponto está dentro do disco ou do contorno do lugar, ou a no máximo toleranceKm do ponto, do centro
    /// do disco ou da borda do contorno. Mesmos filtros do MapItems. Os de área menor primeiro (o mais específico), depois por distância; cada resultado
    /// tem distance_km (do centro, ou da borda se está fora de um contorno; 0 dentro de um contorno) e inside (dentro do disco ou do contorno).
    public Array<Dictionary> EntitiesAt(double lat, double lon, double toleranceKm, string[] layers, long onlyEntity, long t)
    {
        var here = Vec.FromLatLon(lat, lon);
        var hits = new List<(Dictionary D, double Dist, double Radius)>();
        foreach (var d in MapItems(layers, onlyEntity, t))
        {
            var flat = d["vertices"].AsFloat64Array();
            double dist, radius;
            bool inside;
            if (flat.Length >= 6)  // contorno
            {
                var v = PlaceGeometry.ToVecs(flat);
                inside = PlaceGeometry.Contains(here, v);
                dist = inside ? 0 : PlaceGeometry.DistanceToBoundaryKm(here, v);
                radius = Math.Sqrt((double)d["area_km2"] / Math.PI);  // raio equivalente, só para ordenar do mais específico
            }
            else  // ponto ou disco
            {
                radius = (double)d["radius_km"];
                dist = Vec.Angle(here, Vec.FromLatLon((double)d["lat"], (double)d["lon"])) * EvronGeo.RadiusKm;
                inside = dist <= radius;
            }
            if (!inside && dist > toleranceKm) continue;
            d["distance_km"] = dist;
            d["inside"] = inside;
            hits.Add((d, dist, radius));
        }
        return new(hits.OrderBy(h => h.Radius).ThenBy(h => h.Dist).Select(h => h.D));
    }

    // ---- estimativas ----

    /// Estimativa numérica (faixa low..high; iguais = exata) do que se conta para a entidade (habitantes, integrantes, falantes ou adeptos) no lugar em t.
    public long AddEstimate(long subjectId, long placeId, long t, double low, double high, string certainty, string source)
    {
        if (!double.IsFinite(low) || !double.IsFinite(high)) throw new ArgumentException("a estimativa precisa de números finitos");
        return _db.Insert("insert into population_estimate(subject_id, place_id, t, low, high, certainty, source) values (@0, @1, @2, @3, @4, @5, @6)",
            subjectId, placeId, t, low, high, certainty, source == "" ? null : source);
    }

    /// Estimativa só por nível (baixa | media | alta), sem número: nunca é convertida em número.
    public long AddEstimateLevel(long subjectId, long placeId, long t, string level, string certainty, string source) =>
        _db.Insert("insert into population_estimate(subject_id, place_id, t, level, certainty, source) values (@0, @1, @2, @3, @4, @5)",
            subjectId, placeId, t, level, certainty, source == "" ? null : source);

    public void DeleteEstimate(long id)
    {
        long uses = Convert.ToInt64(_db.Scalar("select count(*) from distribution where denominator_id = @0", id));
        if (uses > 0) throw new ArgumentException($"a estimativa {id} é o denominador de {uses} distribuição(ões)");
        _db.Run("delete from population_estimate where id = @0", id);
    }

    Dictionary EstimateDict(object?[] r) => new()
    {
        ["id"] = Convert.ToInt64(r[0]), ["subject_id"] = Convert.ToInt64(r[1]), ["basis"] = BasisOf(Str(r[2])), ["place_id"] = Convert.ToInt64(r[3]), ["place"] = Str(r[4]),
        ["t"] = Convert.ToInt64(r[5]), ["low"] = r[6] == null ? Variant.CreateFrom("") : Convert.ToDouble(r[6]), ["high"] = r[7] == null ? Variant.CreateFrom("") : Convert.ToDouble(r[7]),
        ["level"] = Str(r[8]), ["certainty"] = Str(r[9]), ["source"] = Str(r[10]),
    };

    const string EstimateSelect =
        "select x.id, x.subject_id, e.kind, x.place_id, pl.name, x.t, x.low, x.high, x.level, x.certainty, x.source " +
        "from population_estimate x join entity e on e.id = x.subject_id join place pl on pl.id = x.place_id";

    /// As estimativas de uma entidade vigentes em t: em cada lugar, a mais recente com data até t (o passado não olha para o futuro, e
    /// uma estimativa antiga não é projetada para depois). Cada uma: id, basis, place, t, low/high ("" se só nível), level, certainty, source.
    public Array<Dictionary> EstimatesOf(long subjectId, long t)
    {
        var latest = new System.Collections.Generic.Dictionary<long, object?[]>();
        foreach (var r in _db.Rows(EstimateSelect + " where x.subject_id = @0 and x.t <= @1 order by x.t, x.id", subjectId, t)) latest[Convert.ToInt64(r[3])] = r;
        return new(latest.Values.OrderBy(r => Str(r[4]), StringComparer.CurrentCultureIgnoreCase).Select(EstimateDict));
    }

    /// Pode somar essas estimativas? Devolve {ok: true, low, high} ou {ok: false, reason}. Só soma o que é a mesma base (habitantes com
    /// habitantes...), no mesmo lugar e na mesma data, de entidades diferentes, com número, e que TENHAM sido declaradas categorias EXCLUSIVAS de
    /// uma mesma distribuição nesse lugar e data (sem isso, uma pessoa pode contar em duas e a soma repetiria gente).
    /// Contagens de país, etnia e religião nunca se somam entre si.
    public Dictionary SumEstimates(long[] ids)
    {
        if (ids.Length < 2) return Refuse("a soma precisa de ao menos duas estimativas");
        var rows = ids.Select(id => _db.Rows(EstimateSelect + " where x.id = @0", id)).ToList();
        if (rows.Any(r => r.Count == 0)) return Refuse("estimativa inexistente");
        var es = rows.Select(r => r[0]).ToList();
        if (es.Select(r => BasisOf(Str(r[2]))).Distinct().Count() > 1) return Refuse("contagens de bases diferentes (habitantes, integrantes, falantes, adeptos) não se somam entre si");
        if (es.Select(r => Convert.ToInt64(r[3])).Distinct().Count() > 1) return Refuse("estimativas de lugares diferentes");
        if (es.Select(r => Convert.ToInt64(r[5])).Distinct().Count() > 1) return Refuse("estimativas de datas diferentes");
        if (es.Select(r => Convert.ToInt64(r[1])).Distinct().Count() != es.Count) return Refuse("a mesma entidade aparece mais de uma vez");
        if (es.Any(r => r[6] == null)) return Refuse("estimativa só por nível não tem número para somar");
        long place = Convert.ToInt64(es[0][3]), t = Convert.ToInt64(es[0][5]);
        bool exclusive = _db.Rows("select id from distribution where place_id = @0 and t = @1 and exclusive = 1", place, t).Any(d =>
            es.All(e => Convert.ToInt64(_db.Scalar("select count(*) from distribution_share where distribution_id = @0 and category_id = @1", d[0], e[1])) > 0));
        if (!exclusive) return Refuse("as categorias não foram declaradas exclusivas numa mesma distribuição (uma pessoa pode estar em mais de uma)");
        return new Dictionary { ["ok"] = true, ["low"] = es.Sum(r => Convert.ToDouble(r[6])), ["high"] = es.Sum(r => Convert.ToDouble(r[7])) };
    }

    static Dictionary Refuse(string reason) => new() { ["ok"] = false, ["reason"] = reason };

    // ---- distribuições ----

    /// Registra a composição percentual da população da entidade-sujeito no lugar em t, por dimensão (raca | etnia | cultura | religiao | idioma).
    /// categories/pcts: o que se declara (mesmo comprimento); cada categoria é uma entidade do tipo da dimensão, sem repetir, de 0 a 100%.
    /// exclusive: cada pessoa está em uma só categoria. complete: a lista traz todas as categorias. denominatorId: a estimativa da população de
    /// referência (0 = sem denominador); precisa ser da mesma entidade, lugar e data. Regras: exclusiva + completa soma 100%; exclusiva e
    /// incompleta soma até 100% (o resto é "desconhecido"); não exclusiva não tem teto de soma (falantes de vários idiomas contam em cada um).
    public long AddDistribution(long subjectId, long placeId, long t, string dimension, long denominatorId, bool exclusive, bool complete,
                                string certainty, string source, long[] categories, double[] pcts)
    {
        if (!DimensionKind.TryGetValue(dimension, out var catKind)) throw new ArgumentException($"dimensão inválida: {dimension}");
        if (categories.Length == 0 || categories.Length != pcts.Length) throw new ArgumentException("categorias e percentuais precisam ter o mesmo tamanho (e ao menos um)");
        if (categories.Distinct().Count() != categories.Length) throw new ArgumentException("categoria repetida");
        foreach (long c in categories)
            if (Kind(c) != catKind) throw new ArgumentException($"{c} não é do tipo '{catKind}' (a dimensão é {dimension})");
        if (pcts.Any(p => !double.IsFinite(p) || p < 0 || p > 100)) throw new ArgumentException("percentual fora de 0 a 100");
        double sum = pcts.Sum();
        if (exclusive && complete && Math.Abs(sum - 100) > 0.01) throw new ArgumentException($"categorias exclusivas e lista completa precisam somar 100% (somam {sum:0.##}%)");
        if (exclusive && sum > 100.01) throw new ArgumentException($"categorias exclusivas não passam de 100% (somam {sum:0.##}%)");
        if (denominatorId != 0)
        {
            var d = _db.Rows("select subject_id, place_id, t from population_estimate where id = @0", denominatorId);
            if (d.Count == 0) throw new ArgumentException($"estimativa {denominatorId} não existe");
            if (Convert.ToInt64(d[0][0]) != subjectId || Convert.ToInt64(d[0][1]) != placeId || Convert.ToInt64(d[0][2]) != t)
                throw new ArgumentException("o denominador precisa ser a estimativa da mesma entidade, no mesmo lugar e na mesma data");
        }
        return _db.Tx(() =>
        {
            long id = _db.Insert("insert into distribution(subject_id, place_id, t, dimension, denominator_id, exclusive, complete, certainty, source) values (@0, @1, @2, @3, @4, @5, @6, @7, @8)",
                subjectId, placeId, t, dimension, denominatorId == 0 ? null : denominatorId, exclusive ? 1 : 0, complete ? 1 : 0, certainty, source == "" ? null : source);
            for (int i = 0; i < categories.Length; i++)
                _db.Run("insert into distribution_share(distribution_id, category_id, pct) values (@0, @1, @2)", id, categories[i], pcts[i]);
            return id;
        });
    }

    public void DeleteDistribution(long id) => _db.Tx(() =>
    {
        _db.Run("delete from distribution_share where distribution_id = @0", id);
        _db.Run("delete from distribution where id = @0", id);
        return 0;
    });

    /// A composição: id, subject, place, t, dimension, exclusive, complete, certainty, source, shares (category_id, name, pct e, com denominador
    /// numérico, low/high em pessoas), unknown_pct (só exclusiva e incompleta; senão −1) e denominator ({} se não há). Sem denominador não há
    /// número absoluto: o percentual fica como está.
    public Dictionary Composition(long id)
    {
        var d = _db.Rows("select d.id, d.subject_id, d.place_id, pl.name, d.t, d.dimension, d.exclusive, d.complete, d.certainty, d.source, d.denominator_id " +
                         "from distribution d join place pl on pl.id = d.place_id where d.id = @0", id);
        if (d.Count == 0) throw new ArgumentException($"distribuição {id} não existe");
        var r = d[0];
        bool exclusive = Convert.ToInt64(r[6]) == 1, complete = Convert.ToInt64(r[7]) == 1;
        double? lo = null, hi = null;
        var den = new Dictionary();
        if (r[10] != null)
        {
            var e = _db.Rows("select low, high, level from population_estimate where id = @0", r[10])[0];
            den = new Dictionary { ["id"] = Convert.ToInt64(r[10]), ["low"] = e[0] == null ? Variant.CreateFrom("") : Convert.ToDouble(e[0]), ["high"] = e[1] == null ? Variant.CreateFrom("") : Convert.ToDouble(e[1]), ["level"] = Str(e[2]) };
            if (e[0] != null) { lo = Convert.ToDouble(e[0]); hi = Convert.ToDouble(e[1]); }
        }
        var shares = new GArray();
        double sum = 0;
        foreach (var s in _db.Rows("select category_id, pct from distribution_share where distribution_id = @0 order by pct desc, category_id", id))
        {
            double pct = Convert.ToDouble(s[1]);
            sum += pct;
            var item = new Dictionary { ["category_id"] = Convert.ToInt64(s[0]), ["name"] = Name(Convert.ToInt64(s[0])), ["pct"] = pct };
            if (lo != null) { item["low"] = Math.Round(lo.Value * pct / 100); item["high"] = Math.Round(hi!.Value * pct / 100); }
            shares.Add(item);
        }
        return new Dictionary
        {
            ["id"] = id, ["subject_id"] = Convert.ToInt64(r[1]), ["place_id"] = Convert.ToInt64(r[2]), ["place"] = Str(r[3]), ["t"] = Convert.ToInt64(r[4]), ["dimension"] = Str(r[5]),
            ["exclusive"] = exclusive, ["complete"] = complete, ["certainty"] = Str(r[8]), ["source"] = Str(r[9]), ["shares"] = shares,
            ["unknown_pct"] = exclusive && !complete ? Math.Round(100 - sum, 2) : -1.0, ["denominator"] = den,
        };
    }

    /// As composições da entidade vigentes em t: em cada lugar e dimensão, a mais recente com data até t.
    public Array<Dictionary> CompositionsOf(long subjectId, long t)
    {
        var latest = new System.Collections.Generic.Dictionary<(long, string), long>();
        foreach (var r in _db.Rows("select id, place_id, dimension from distribution where subject_id = @0 and t <= @1 order by t, id", subjectId, t))
            latest[(Convert.ToInt64(r[1]), Str(r[2]))] = Convert.ToInt64(r[0]);
        return new(latest.Values.Select(Composition).OrderBy(c => (string)c["place"], StringComparer.CurrentCultureIgnoreCase).ThenBy(c => (string)c["dimension"]));
    }
}
