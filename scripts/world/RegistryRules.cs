using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.Json.Nodes;
using Godot.Collections;

namespace Evron;

/// Regras (etapa E3; aceite 6 a 8). Uma regra é um grafo de nós DECLARATIVO (JSON versionado), nunca código: o núcleo valida a definição e a
/// avalia com um interpretador de poucos nós, com limite de tamanho e profundidade. A regra calcula um campo numérico das entidades de um
/// tipo, numa data do mundo t. Cada execução fica registrada (versão da regra e do runtime, data, quando) com o resultado de cada entidade.
/// Fixação autoral: um valor fixado pelo autor para um período sempre prevalece; a execução guarda o que a regra calcularia e sinaliza
/// quando diverge, sem nunca substituir a decisão.
/// Modos: manual (só roda quando o autor executa), automático (a ficha mostra o valor calculado na data mostrada, a cada data, sem
/// gravar execução) e desativado.
///
/// Definição: {"version": 1, "kind": tipo, "field": código do campo alvo, "expr": nó}. Nós:
///   {"op": "const", "value": n}            número fixo
///   {"op": "field", "code": "custom.N"}     outro campo numérico da própria entidade
///   {"op": "links", "type": código}         quantos vínculos desse tipo a entidade tem (como origem) vigentes em t
///   {"op": "population"}                    população em t: a estimativa numérica mais recente até t (o meio da faixa); com estimativas em
///                                           vários lugares, a do lugar de maior estimativa (somar lugares repetiria gente onde se sobrepõem)
///   {"op": "area"}                          área em km²: o território pintado (país, província, município); sem ele, o maior lugar
///                                           em que a entidade está presente em t
///   {"op": "distance", "to": id}            km entre o lugar principal da entidade e o de outra, em t (capital, sede ou origem;
///                                           senão o primeiro lugar)
///   {"op": "add"|"sub"|"mul"|"div"|"min"|"max", "a": nó, "b": nó}
///   {"op": "if", "cond": {"op": "gt"|"ge"|"lt"|"le"|"eq"|"ne", "a": nó, "b": nó}, "then": nó, "else": nó}
public partial class Registry
{
    public const int RuleFormatVersion = 1;
    public const string RuleRuntimeVersion = "1";
    const int RuleMaxNodes = 200;
    const int RuleMaxDepth = 24;

    const string RulesMigration = """
        create table rule(
            id integer primary key,
            name text not null,
            mode text not null default 'manual' check (mode in ('manual','automatico','desativado')),
            created_at integer not null default (unixepoch()));
        create table rule_version(
            rule_id integer not null references rule(id),
            version integer not null,
            definition text not null,
            created_at integer not null default (unixepoch()),
            primary key (rule_id, version));
        create table rule_run(
            id integer primary key,
            rule_id integer not null references rule(id),
            rule_version integer not null,
            runtime text not null,
            t integer not null,
            recorded_at integer not null default (unixepoch()));
        create table rule_result(
            run_id integer not null references rule_run(id),
            entity_id integer not null references entity(id),
            computed real,                       -- o que a regra calculou (null = erro)
            value real,                          -- o que vale: o calculado ou o fixado
            status text not null check (status in ('calculado','fixado','erro')),
            note text,
            primary key (run_id, entity_id));
        -- Fixação autoral: o valor de um campo de uma entidade num período, decidido pelo autor; nenhuma regra o substitui.
        create table field_override(
            id integer primary key,
            entity_id integer not null references entity(id),
            field_id integer not null references field_def(id),
            num real not null,
            reason text,
            valid_from integer not null,
            valid_to integer not null,
            recorded_at integer not null default (unixepoch()),
            check (valid_from < valid_to));
        create index field_override_entity on field_override(entity_id, field_id);
        """;

    static readonly HashSet<string> MathOps = new() { "add", "sub", "mul", "div", "min", "max" };
    static readonly HashSet<string> CompareOps = new() { "gt", "ge", "lt", "le", "eq", "ne" };

    // As camadas territoriais carregadas (nível -> camada), para o nó "area": o DomainHub as entrega ao ligar o território.
    readonly System.Collections.Generic.Dictionary<string, Territory> _territories = new();

    /// Entrega ao Registry a camada de um nível, para as regras lerem a área pintada.
    public void UseTerritory(string level, Territory layer) => _territories[CheckLevel(level)] = layer;

    static readonly string[] MainRoles = { "capital", "sede", "origem" };

    /// O ponto do lugar principal da entidade em t: capital, sede ou origem; senão o primeiro lugar. null se não está em lugar nenhum.
    Vec? MainPoint(long entity, long t)
    {
        var ps = PresencesOf(entity, t);
        if (ps.Count == 0) return null;
        var main = ps.OrderBy(p => System.Array.IndexOf(MainRoles, (string)p["role"]) is int i && i >= 0 ? i : MainRoles.Length).First();
        return Vec.FromLatLon((double)main["lat"], (double)main["lon"]);
    }

    // ---- definição ----

    /// Confere uma definição sem gravar: "" se vale, senão o primeiro problema (em português, para mostrar ao autor).
    public string ValidateRule(string definition)
    {
        try { CheckRule(definition); return ""; }
        catch (ArgumentException e) { return e.Message; }
    }

    (JsonObject Root, string Kind, long FieldId) CheckRule(string definition)
    {
        JsonObject? root;
        try { root = JsonNode.Parse(definition) as JsonObject; }
        catch (Exception) { throw new ArgumentException("a definição não é um JSON válido"); }
        if (root == null) throw new ArgumentException("a definição precisa ser um objeto");
        if ((int?)root["version"] is not int v || v > RuleFormatVersion) throw new ArgumentException("versão da definição desconhecida");
        string kind = (string?)root["kind"] ?? "";
        if (!TypeExists(kind)) throw new ArgumentException($"tipo de entidade inexistente: {kind}");
        long fieldId = NumericFieldOf(kind, (string?)root["field"] ?? "", "o campo calculado");
        int count = 0;
        try { CheckNode(root["expr"], kind, 0, ref count); }
        catch (Exception e) when (e is InvalidOperationException or FormatException) { throw new ArgumentException("um nó tem um valor do tipo errado"); }
        return (root, kind, fieldId);
    }

    long NumericFieldOf(string kind, string code, string what)
    {
        var r = _db.Rows("select d.id, d.type from field_def d join field_domain f on f.field_id = d.id where d.code = @0 and f.kind = @1", code, kind);
        if (r.Count == 0) throw new ArgumentException($"{what} ({code}) não existe para esse tipo");
        if (Str(r[0][1]) != "number") throw new ArgumentException($"{what} ({code}) não é numérico");
        return Convert.ToInt64(r[0][0]);
    }

    void CheckNode(JsonNode? node, string kind, int depth, ref int count)
    {
        if (++count > RuleMaxNodes) throw new ArgumentException($"a regra passa de {RuleMaxNodes} nós");
        if (depth > RuleMaxDepth) throw new ArgumentException($"a regra passa de {RuleMaxDepth} níveis");
        if (node is not JsonObject n) throw new ArgumentException("falta um nó");
        string op = (string?)n["op"] ?? "";
        switch (op)
        {
            case "const":
                if ((double?)n["value"] is not double c || !double.IsFinite(c)) throw new ArgumentException("número fixo inválido");
                break;
            case "field":
                NumericFieldOf(kind, (string?)n["code"] ?? "", "o campo lido");
                break;
            case "links":
                if (_db.Scalar("select 1 from relation_type where code = @0", (string?)n["type"] ?? "") == null)
                    throw new ArgumentException($"tipo de vínculo inexistente: {(string?)n["type"]}");
                break;
            case "population":
            case "area":
                break;
            case "distance":
                if ((double?)n["to"] is not double to || to != Math.Floor(to) || _db.Scalar("select 1 from entity where id = @0", (long)to) == null)
                    throw new ArgumentException("a distância precisa de uma entidade de destino que exista");
                break;
            case "if":
                if (n["cond"] is not JsonObject cond || !CompareOps.Contains((string?)cond["op"] ?? ""))
                    throw new ArgumentException("a condição precisa comparar (maior, menor, igual...)");
                CheckNode(cond["a"], kind, depth + 1, ref count);
                CheckNode(cond["b"], kind, depth + 1, ref count);
                CheckNode(n["then"], kind, depth + 1, ref count);
                CheckNode(n["else"], kind, depth + 1, ref count);
                break;
            default:
                if (!MathOps.Contains(op)) throw new ArgumentException($"nó desconhecido: {op}");
                CheckNode(n["a"], kind, depth + 1, ref count);
                CheckNode(n["b"], kind, depth + 1, ref count);
                break;
        }
    }

    /// Grava uma regra nova (id 0) ou uma nova versão de uma existente; versões antigas ficam (para reproduzir execuções). Devolve o id.
    public long SaveRule(long id, string name, string definition)
    {
        name = Clean(name);
        CheckRule(definition);
        return _db.Tx(() =>
        {
            if (id == 0) id = _db.Insert("insert into rule(name) values (@0)", name);
            else if (_db.Run("update rule set name = @0 where id = @1", name, id) == 0) throw new ArgumentException($"regra {id} não existe");
            long next = Convert.ToInt64(_db.Scalar("select coalesce(max(version), 0) + 1 from rule_version where rule_id = @0", id));
            _db.Run("insert into rule_version(rule_id, version, definition) values (@0, @1, @2)", id, next, definition);
            return id;
        });
    }

    public void SetRuleMode(long id, string mode)
    {
        if (mode is not ("manual" or "automatico" or "desativado")) throw new ArgumentException($"modo desconhecido: {mode}");
        if (_db.Run("update rule set mode = @0 where id = @1", mode, id) == 0) throw new ArgumentException($"regra {id} não existe");
    }

    /// O que a ficha mostra em t para os campos de uma entidade: o valor das regras automáticas do tipo dela (calculado na hora, sem
    /// gravar) e os valores fixados. code -> {value, computed, status ("calculado"|"fixado"|"erro"), note, rule (nome; "" se só fixado)}.
    public Dictionary ComputedFields(long entity, long t)
    {
        var result = new Dictionary();
        string kind = Kind(entity);
        foreach (var r in _db.Rows("select r.name, v.definition from rule r join rule_version v on v.rule_id = r.id where r.mode = 'automatico' " +
                                   "and v.version = (select max(version) from rule_version where rule_id = r.id) order by r.id"))
        {
            JsonObject root;
            string ruleKind;
            long fieldId;
            try { (root, ruleKind, fieldId) = CheckRule(Str(r[1])); }
            catch (ArgumentException) { continue; }  // uma regra que deixou de valer (campo apagado) não derruba a ficha
            if (ruleKind != kind) continue;
            double? computed = null;
            string note = "";
            try { computed = Eval(root["expr"]!, entity, t); }
            catch (ArgumentException ex) { note = ex.Message; }
            string code = Str(_db.Scalar("select code from field_def where id = @0", fieldId));
            result[code] = Shown(entity, fieldId, t, computed, note, Str(r[0]));
        }
        foreach (var p in _db.Rows("select distinct d.id, d.code from field_override o join field_def d on d.id = o.field_id " +
                                   "where o.entity_id = @0 and o.valid_from <= @1 and @1 < o.valid_to", entity, t))
            if (!result.ContainsKey(Str(p[1]))) result[Str(p[1])] = Shown(entity, Convert.ToInt64(p[0]), t, null, "", "");
        return result;
    }

    Dictionary Shown(long entity, long fieldId, long t, double? computed, string note, string rule)
    {
        var pin = _db.Rows("select num, reason from field_override where entity_id = @0 and field_id = @1 and valid_from <= @2 and @2 < valid_to " +
                           "order by recorded_at desc, id desc limit 1", entity, fieldId, t);
        if (pin.Count > 0)
        {
            double v = Convert.ToDouble(pin[0][0]);
            string why = Str(pin[0][1]);
            if (computed != null && Math.Abs(computed.Value - v) > 1e-9)
                why = (why == "" ? "" : why + "; ") + $"a regra calcularia {computed.Value.ToString(CultureInfo.InvariantCulture)}";
            return new Dictionary { ["value"] = v, ["computed"] = computed ?? double.NaN, ["status"] = "fixado", ["note"] = why, ["rule"] = rule };
        }
        return new Dictionary { ["value"] = computed ?? double.NaN, ["computed"] = computed ?? double.NaN,
                                ["status"] = computed != null ? "calculado" : "erro", ["note"] = note, ["rule"] = rule };
    }

    /// As regras: {id, name, mode, version, definition (a da versão mais nova)}.
    public Array<Dictionary> Rules() => new(
        _db.Rows("select r.id, r.name, r.mode, v.version, v.definition from rule r join rule_version v on v.rule_id = r.id " +
                 "where v.version = (select max(version) from rule_version where rule_id = r.id) order by r.id")
           .Select(r => new Dictionary { ["id"] = Convert.ToInt64(r[0]), ["name"] = Str(r[1]), ["mode"] = Str(r[2]),
                                         ["version"] = Convert.ToInt64(r[3]), ["definition"] = Str(r[4]) }));

    // ---- fixação autoral ----

    /// Fixa o valor de um campo numérico de uma entidade de from até to (Forever = sem fim). Devolve o id da fixação.
    public long PinField(long entityId, string code, double value, long from, long to, string reason)
    {
        if (!double.IsFinite(value)) throw new ArgumentException("valor inválido");
        long fid = NumericFieldOf(Kind(entityId), code, "o campo fixado");
        return _db.Insert("insert into field_override(entity_id, field_id, num, reason, valid_from, valid_to) values (@0, @1, @2, @3, @4, @5)",
            entityId, fid, value, reason, from, to);
    }

    public void UnpinField(long overrideId) => _db.Run("delete from field_override where id = @0", overrideId);

    double? PinnedAt(long entityId, long fieldId, long t) =>
        _db.Scalar("select num from field_override where entity_id = @0 and field_id = @1 and valid_from <= @2 and @2 < valid_to " +
                   "order by recorded_at desc, id desc limit 1", entityId, fieldId, t) is object o ? Convert.ToDouble(o) : null;

    // ---- execução ----

    /// Executa a versão mais nova da regra na data t, para cada entidade do tipo. Grava a execução e devolve
    /// {run_id, version, results: [{entity_id, name, computed, value, status, note}]}. Uma regra desativada não executa.
    public Dictionary RunRule(long id, long t)
    {
        var rule = _db.Rows("select r.mode, v.version, v.definition from rule r join rule_version v on v.rule_id = r.id where r.id = @0 " +
                            "order by v.version desc limit 1", id);
        if (rule.Count == 0) throw new ArgumentException($"regra {id} não existe");
        if (Str(rule[0][0]) == "desativado") throw new ArgumentException("a regra está desativada");
        long version = Convert.ToInt64(rule[0][1]);
        var (root, kind, fieldId) = CheckRule(Str(rule[0][2]));
        return _db.Tx(() =>
        {
            long run = _db.Insert("insert into rule_run(rule_id, rule_version, runtime, t) values (@0, @1, @2, @3)", id, version, RuleRuntimeVersion, t);
            var results = new Array<Dictionary>();
            foreach (var e in _db.Rows("select id from entity where kind = @0 order by id", kind))
            {
                long entity = Convert.ToInt64(e[0]);
                double? computed = null;
                string note = "";
                try { computed = Eval(root["expr"]!, entity, t); }
                catch (ArgumentException ex) { note = ex.Message; }
                double? pinned = PinnedAt(entity, fieldId, t);
                string status = pinned != null ? "fixado" : computed != null ? "calculado" : "erro";
                if (pinned != null && computed != null && Math.Abs(pinned.Value - computed.Value) > 1e-9)
                    note = $"a regra calcularia {computed.Value.ToString(CultureInfo.InvariantCulture)}; vale o fixado";
                double? value = pinned ?? computed;
                _db.Run("insert into rule_result(run_id, entity_id, computed, value, status, note) values (@0, @1, @2, @3, @4, @5)",
                    run, entity, computed, value, status, note == "" ? null : note);
                results.Add(new Dictionary { ["entity_id"] = entity, ["name"] = Name(entity), ["computed"] = computed ?? double.NaN,
                                             ["value"] = value ?? double.NaN, ["status"] = status, ["note"] = note });
            }
            return new Dictionary { ["run_id"] = run, ["version"] = version, ["results"] = results };
        });
    }

    double Eval(JsonNode node, long entity, long t)
    {
        var n = (JsonObject)node;
        string op = (string)n["op"]!;
        switch (op)
        {
            case "const": return (double)n["value"]!;
            case "field":
            {
                var v = _db.Rows("select v.state, v.num from field_value v join field_def d on d.id = v.field_id where v.entity_id = @0 and d.code = @1",
                    entity, (string)n["code"]!);
                if (v.Count == 0 || Str(v[0][0]) != "known")
                    throw new ArgumentException($"o campo {Str(_db.Scalar("select label from field_def where code = @0", (string)n["code"]!))} não está preenchido");
                return Convert.ToDouble(v[0][1]);
            }
            case "links":
                return Convert.ToDouble(_db.Scalar("select count(*) from relation where src = @0 and type = @1 and valid_from <= @2 and @2 < valid_to",
                    entity, (string)n["type"]!, t));
            case "population":
            {
                var latest = new System.Collections.Generic.Dictionary<long, double>();
                foreach (var r in _db.Rows("select place_id, low, high from population_estimate where subject_id = @0 and t <= @1 and low is not null " +
                                           "order by t, id", entity, t))
                    latest[Convert.ToInt64(r[0])] = (Convert.ToDouble(r[1]) + Convert.ToDouble(r[2])) / 2;
                if (latest.Count == 0) throw new ArgumentException("sem estimativa numérica de população até essa data");
                return latest.Values.Max();
            }
            case "area":
            {
                if (_territories.TryGetValue(Kind(entity), out var layer) && entity <= Territory.MaxOwner && layer.AreaKm2((int)entity) > 0)
                    return layer.AreaKm2((int)entity);
                double best = PresencesOf(entity, t).Select(p => (double)p["area_km2"]).DefaultIfEmpty(0).Max();
                if (best <= 0) throw new ArgumentException("sem território pintado nem lugar com área nessa data");
                return best;
            }
            case "distance":
            {
                long other = (long)(double)n["to"]!;
                var (a, b) = (MainPoint(entity, t), MainPoint(other, t));
                if (a == null || b == null) throw new ArgumentException($"{Name(a == null ? entity : other)} não está em nenhum lugar nessa data");
                return Vec.Angle(a.Value, b.Value) * EvronGeo.RadiusKm;
            }
            case "if":
            {
                var c = (JsonObject)n["cond"]!;
                double a = Eval(c["a"]!, entity, t), b = Eval(c["b"]!, entity, t);
                bool yes = (string)c["op"]! switch
                {
                    "gt" => a > b, "ge" => a >= b, "lt" => a < b, "le" => a <= b, "eq" => Math.Abs(a - b) < 1e-9, _ => Math.Abs(a - b) >= 1e-9,
                };
                return Eval(yes ? n["then"]! : n["else"]!, entity, t);
            }
            default:
            {
                double a = Eval(n["a"]!, entity, t), b = Eval(n["b"]!, entity, t);
                double r = op switch
                {
                    "add" => a + b, "sub" => a - b, "mul" => a * b, "min" => Math.Min(a, b), "max" => Math.Max(a, b),
                    _ => b == 0 ? throw new ArgumentException("divisão por zero") : a / b,
                };
                if (!double.IsFinite(r)) throw new ArgumentException("o resultado não é um número finito");
                return r;
            }
        }
    }
}
