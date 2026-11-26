using System;
using System.Collections.Generic;
using System.Linq;
using Godot;
using Godot.Collections;

namespace Evron;

/// Produção (etapa 3 do plano de recursos): povoados com trabalhadores, capacidades e estoque; receitas e atividades. A cada mês do
/// calendário cada povoado produz o que dá com o trabalho, a prática, os insumos, as instalações e a reserva ao alcance. Contratos em
/// docs/recursos/contratos.md.
///
/// · Os bens são os tipos de recurso (resource_type), cada um com a sua unidade. Receita e estoque usam a unidade do bem: não há conversão.
/// · Estoque = soma das movimentações (stock_movement). Nunca fica negativo: a produção só consome o que existe, e retirar mais do
///   que há é recusado. O estoque numa data é a soma até ela.
/// · Reserva de uma ocorrência = a quantidade do autor − o extraído + o que se renovou (occurrence_state). Sem quantidade, a
///   ocorrência é narrativa: não dá para extrair dela. A política do autor pode repor a reserva (magia) ou bloqueá-la.
/// · Capacidade: a receita pode exigir que o povoado saiba algo (capability); a prática (1 a 100%) multiplica o rendimento do trabalho.
/// · Requisito: a receita pode exigir um bem no estoque que NÃO é gasto (forno, ferramenta): cada unidade permite N ciclos por mês.
/// · Insumos alternativos: insumos com o mesmo grupo (> 0) se substituem, gastos na ordem em que foram dados.
/// · O mês processado fica registrado (production_run) na MESMA transação dos estoques e da renovação: o mesmo mês não roda duas vezes.
/// · Configuração e intervenções NÃO têm desfazer: as movimentações são histórico. As referências a bens e receitas não têm chave
///   estrangeira: um bem que deixou de existir para a atividade, com aviso.
public partial class Registry
{
    public const string ProductionEngine = "producao-2";  // 2: capacidades, requisitos, alternativas, renovação, validade e política
    const double Eps = 1e-9;

    const string ProductionMigration = """
        alter table resource_occurrence add column reserve real check (reserve is null or reserve >= 0);

        create table settlement(
            id integer primary key autoincrement,
            world_id integer not null default 1 references world(id),
            name text not null,
            lat real not null check (lat >= -90 and lat <= 90),
            lon real not null check (lon >= -180 and lon <= 180),
            workers integer not null default 0 check (workers >= 0),
            reach_km real not null default 50 check (reach_km >= 0 and reach_km <= 1000),
            created_at integer not null default (unixepoch()));

        create table recipe(
            id integer primary key autoincrement,
            name text not null,
            kind text not null check (kind in ('extracao','fabricacao')),
            output_id integer not null,
            output_qty real not null check (output_qty > 0),
            labor_days real not null check (labor_days > 0),
            created_at integer not null default (unixepoch()));
        create table recipe_input(
            recipe_id integer not null references recipe(id),
            good_id integer not null,
            qty real not null check (qty > 0),
            primary key (recipe_id, good_id));

        create table activity(
            id integer primary key autoincrement,
            settlement_id integer not null references settlement(id),
            recipe_id integer not null,
            workers integer not null check (workers >= 0),
            position integer not null);
        create index activity_settlement on activity(settlement_id, position);

        create table production_run(
            id integer primary key autoincrement,
            month_start integer not null,
            month_end integer not null unique,
            engine text not null,
            recorded_at integer not null default (unixepoch()));
        create table stock_movement(
            id integer primary key autoincrement,
            settlement_id integer not null references settlement(id),
            good_id integer not null,
            t integer not null,
            qty real not null check (qty <> 0),
            reason text not null check (reason in ('producao','consumo','intervencao')),
            run_id integer references production_run(id),
            occurrence_id integer,
            note text);
        create index stock_movement_place on stock_movement(settlement_id, good_id);
        create index stock_movement_occurrence on stock_movement(occurrence_id) where occurrence_id is not null;
        create table production_result(
            run_id integer not null references production_run(id),
            activity_id integer not null,
            settlement_id integer not null,
            cycles real not null,
            produced real not null,
            note text not null,
            primary key (run_id, activity_id));
        """;

    // ---- povoados ----

    public long CreateSettlement(string name, double lat, double lon, long workers)
    {
        CheckPoint(lat, lon);
        if (workers < 0) throw new ArgumentException("trabalhadores não podem ser negativos");
        return _db.Insert("insert into settlement(name, lat, lon, workers) values (@0, @1, @2, @3)", Clean(name), lat, lon, workers);
    }

    /// Nome, trabalhadores e alcance (km até onde o povoado chega para extrair). Menos trabalhadores que os já postos em atividades é
    /// aceito: no mês, as atividades de cima na lista ficam com eles e as de baixo ficam sem.
    public void SetSettlement(long id, string name, long workers, double reachKm)
    {
        if (workers < 0) throw new ArgumentException("trabalhadores não podem ser negativos");
        if (!(reachKm >= 0 && reachKm <= 1000)) throw new ArgumentException("o alcance vai de 0 a 1000 km");
        if (_db.Run("update settlement set name = @0, workers = @1, reach_km = @2 where id = @3", Clean(name), workers, reachKm, id) == 0)
            throw new ArgumentException($"povoado {id} não existe");
    }

    public void MoveSettlement(long id, double lat, double lon)
    {
        CheckPoint(lat, lon);
        if (_db.Run("update settlement set lat = @0, lon = @1 where id = @2", lat, lon, id) == 0) throw new ArgumentException($"povoado {id} não existe");
    }

    /// Exclui um povoado criado por engano. Recusa se ele já tem histórico de estoque (o histórico não some).
    public void DeleteSettlement(long id)
    {
        if (Convert.ToInt64(_db.Scalar("select count(*) from stock_movement where settlement_id = @0", id)) > 0)
            throw new ArgumentException("este povoado já tem histórico de estoque e não pode ser excluído");
        _db.Tx(() =>
        {
            _db.Run("delete from activity where settlement_id = @0", id);
            _db.Run("delete from settlement_capability where settlement_id = @0", id);
            return _db.Run("delete from settlement where id = @0", id) == 0 ? throw new ArgumentException($"povoado {id} não existe") : 0;
        });
    }

    /// {id, name, lat, lon, workers, reach_km, assigned (trabalhadores postos em atividades)}, por nome.
    public Array<Dictionary> Settlements() => new(_db.Rows("""
            select s.id, s.name, s.lat, s.lon, s.workers, s.reach_km, coalesce((select sum(a.workers) from activity a where a.settlement_id = s.id), 0)
            from settlement s order by s.name collate nocase, s.id
            """).Select(r => new Dictionary
        {
            ["id"] = Convert.ToInt64(r[0]), ["name"] = Str(r[1]), ["lat"] = Convert.ToDouble(r[2]), ["lon"] = Convert.ToDouble(r[3]),
            ["workers"] = Convert.ToInt64(r[4]), ["reach_km"] = Convert.ToDouble(r[5]), ["assigned"] = Convert.ToInt64(r[6]),
        }));

    // ---- capacidades ----

    /// Cria uma capacidade (o que alguém sabe fazer: "Fundir bronze", "Forjar ferro"). O mesmo nome devolve a que já existe.
    public long CreateCapability(string name)
    {
        name = Clean(name);
        // Sem diferenciar maiúsculas também nas letras acentuadas (o "nocase" do SQLite só dobra as sem acento).
        var same = _db.Rows("select id, name from capability").FirstOrDefault(r =>
            System.Globalization.CultureInfo.InvariantCulture.CompareInfo.Compare(Str(r[1]), name, System.Globalization.CompareOptions.IgnoreCase) == 0);
        return same != null ? Convert.ToInt64(same[0]) : _db.Insert("insert into capability(name) values (@0)", name);
    }

    /// {id, name, users (quantos povoados sabem)}.
    public Array<Dictionary> Capabilities() => new(_db.Rows("""
        select c.id, c.name, (select count(*) from settlement_capability s where s.capability_id = c.id) from capability c order by c.name collate nocase
        """).Select(r => new Dictionary { ["id"] = Convert.ToInt64(r[0]), ["name"] = Str(r[1]), ["users"] = Convert.ToInt64(r[2]) }));

    /// O povoado sabe a capacidade com essa prática (1 a 100). 0 tira.
    public void SetSettlementCapability(long settlementId, long capabilityId, long proficiency)
    {
        if (proficiency < 0 || proficiency > 100) throw new ArgumentException("a prática vai de 0 a 100");
        if (_db.Scalar("select 1 from capability where id = @0", capabilityId) == null) throw new ArgumentException("a capacidade não existe");
        if (_db.Scalar("select 1 from settlement where id = @0", settlementId) == null) throw new ArgumentException("o povoado não existe");
        if (proficiency == 0) _db.Run("delete from settlement_capability where settlement_id = @0 and capability_id = @1", settlementId, capabilityId);
        else _db.Run("insert into settlement_capability(settlement_id, capability_id, proficiency) values (@0, @1, @2) " +
                     "on conflict(settlement_id, capability_id) do update set proficiency = @2", settlementId, capabilityId, proficiency);
    }

    /// {capability_id, name, proficiency} do povoado.
    public Array<Dictionary> SettlementCapabilities(long settlementId) => new(_db.Rows("""
        select c.id, c.name, s.proficiency from settlement_capability s join capability c on c.id = s.capability_id
        where s.settlement_id = @0 order by c.name collate nocase
        """, settlementId).Select(r => new Dictionary { ["capability_id"] = Convert.ToInt64(r[0]), ["name"] = Str(r[1]), ["proficiency"] = Convert.ToInt64(r[2]) }));

    /// Exclui uma capacidade que nenhuma receita exige (tira-a dos povoados que a sabiam).
    public void DeleteCapability(long id)
    {
        if (_db.Scalar("select 1 from recipe where capability_id = @0", id) != null) throw new ArgumentException("há receitas que exigem esta capacidade");
        _db.Tx(() =>
        {
            _db.Run("delete from settlement_capability where capability_id = @0", id);
            return _db.Run("delete from capability where id = @0", id);
        });
    }

    // ---- receitas ----

    /// inputs: good0, qty0, good1, qty1, ... Extração: a saída sai de uma ocorrência do próprio bem ao alcance do povoado.
    public long CreateRecipe(string name, string kind, long outputId, double outputQty, double laborDays, double[] inputs)
    {
        name = Clean(name);
        var pairs = CheckRecipe(kind, outputId, outputQty, laborDays, inputs);
        return _db.Tx(() =>
        {
            long id = _db.Insert("insert into recipe(name, kind, output_id, output_qty, labor_days) values (@0, @1, @2, @3, @4)",
                name, kind, outputId, outputQty, laborDays);
            foreach (var (good, qty) in pairs) _db.Run("insert into recipe_input(recipe_id, good_id, qty) values (@0, @1, @2)", id, good, qty);
            return id;
        });
    }

    public void UpdateRecipe(long id, string name, string kind, long outputId, double outputQty, double laborDays, double[] inputs)
    {
        name = Clean(name);
        var pairs = CheckRecipe(kind, outputId, outputQty, laborDays, inputs);
        _db.Tx(() =>
        {
            if (_db.Run("update recipe set name = @0, kind = @1, output_id = @2, output_qty = @3, labor_days = @4 where id = @5",
                    name, kind, outputId, outputQty, laborDays, id) == 0) throw new ArgumentException($"receita {id} não existe");
            _db.Run("delete from recipe_input where recipe_id = @0", id);
            foreach (var (good, qty) in pairs) _db.Run("insert into recipe_input(recipe_id, good_id, qty) values (@0, @1, @2)", id, good, qty);
            return 0;
        });
    }

    /// O resto da receita: a capacidade exigida (0 = nenhuma), os requisitos (bem, ciclos por unidade por mês; não são gastos) e os
    /// grupos de insumos alternativos (bem, grupo; mesmo grupo > 0 = um substitui o outro, na ordem dada).
    public void SetRecipeExtras(long id, long capabilityId, double[] requirements, double[] groups)
    {
        if (capabilityId != 0 && _db.Scalar("select 1 from capability where id = @0", capabilityId) == null) throw new ArgumentException("a capacidade não existe");
        if (requirements.Length % 2 != 0 || groups.Length % 2 != 0) throw new ArgumentException("os requisitos e os grupos vêm em pares");
        var output = _db.Scalar("select output_id from recipe where id = @0", id) ?? throw new ArgumentException($"receita {id} não existe");
        var reqs = new List<(long, double)>();
        for (int i = 0; i < requirements.Length; i += 2)
        {
            long good = (long)requirements[i];
            if (good != requirements[i] || !GoodExists(good)) throw new ArgumentException("um requisito não existe");
            if (good == Convert.ToInt64(output)) throw new ArgumentException("o bem produzido não pode ser requisito da própria receita");
            if (!(requirements[i + 1] > 0 && double.IsFinite(requirements[i + 1]))) throw new ArgumentException("os ciclos por unidade têm de ser maiores que zero");
            if (reqs.Any(r => r.Item1 == good)) throw new ArgumentException("o mesmo requisito aparece duas vezes");
            reqs.Add((good, requirements[i + 1]));
        }
        _db.Tx(() =>
        {
            _db.Run("update recipe set capability_id = @0 where id = @1", capabilityId == 0 ? null : capabilityId, id);
            _db.Run("delete from recipe_requirement where recipe_id = @0", id);
            foreach (var (good, cycles) in reqs) _db.Run("insert into recipe_requirement(recipe_id, good_id, cycles) values (@0, @1, @2)", id, good, cycles);
            _db.Run("update recipe_input set alt_group = 0 where recipe_id = @0", id);
            for (int i = 0; i < groups.Length; i += 2)
                if (_db.Run("update recipe_input set alt_group = @0 where recipe_id = @1 and good_id = @2", (long)groups[i + 1], id, (long)groups[i]) == 0)
                    throw new ArgumentException("o grupo cita um insumo que a receita não tem");
            return 0;
        });
    }

    List<(long Good, double Qty)> CheckRecipe(string kind, long outputId, double outputQty, double laborDays, double[] inputs)
    {
        if (kind is not ("extracao" or "fabricacao")) throw new ArgumentException("a receita é de extração ou de fabricação");
        if (!GoodExists(outputId)) throw new ArgumentException("o bem produzido não existe");
        if (!(outputQty > 0 && double.IsFinite(outputQty))) throw new ArgumentException("a quantidade produzida tem de ser maior que zero");
        if (!(laborDays > 0 && double.IsFinite(laborDays))) throw new ArgumentException("o trabalho por ciclo tem de ser maior que zero");
        if (inputs.Length % 2 != 0) throw new ArgumentException("os insumos vêm em pares (bem, quantidade)");
        var pairs = new List<(long, double)>();
        for (int i = 0; i < inputs.Length; i += 2)
        {
            long good = (long)inputs[i];
            double qty = inputs[i + 1];
            if (good != inputs[i] || !GoodExists(good)) throw new ArgumentException("um insumo não existe");
            if (good == outputId) throw new ArgumentException("um bem não pode ser insumo da própria receita");
            if (!(qty > 0 && double.IsFinite(qty))) throw new ArgumentException("a quantidade de cada insumo tem de ser maior que zero");
            if (pairs.Any(p => p.Item1 == good)) throw new ArgumentException("o mesmo insumo aparece duas vezes");
            pairs.Add((good, qty));
        }
        return pairs;
    }

    bool GoodExists(long id) => _db.Scalar("select 1 from resource_type where id = @0", id) != null;

    /// Exclui uma receita que nenhuma atividade usa.
    public void DeleteRecipe(long id)
    {
        if (Convert.ToInt64(_db.Scalar("select count(*) from activity where recipe_id = @0", id)) > 0)
            throw new ArgumentException("há atividades usando esta receita: tire-as antes");
        _db.Tx(() =>
        {
            _db.Run("delete from recipe_input where recipe_id = @0", id);
            _db.Run("delete from recipe_requirement where recipe_id = @0", id);
            return _db.Run("delete from recipe where id = @0", id);
        });
    }

    /// {id, name, kind, output_id, output_qty, labor_days, capability_id, capability, inputs: [{good_id, qty, group}],
    /// requirements: [{good_id, cycles}], text (a receita em palavras), ok}.
    public Array<Dictionary> Recipes()
    {
        var goods = GoodNames();
        var caps = _db.Rows("select id, name from capability").ToDictionary(r => Convert.ToInt64(r[0]), r => Str(r[1]));
        var inputs = _db.Rows("select recipe_id, good_id, qty, alt_group from recipe_input order by recipe_id, rowid")
            .GroupBy(r => Convert.ToInt64(r[0])).ToDictionary(g => g.Key, g => g.Select(r => (Good: Convert.ToInt64(r[1]), Qty: Convert.ToDouble(r[2]), Group: Convert.ToInt64(r[3]))).ToList());
        var reqs = _db.Rows("select recipe_id, good_id, cycles from recipe_requirement order by recipe_id, rowid")
            .GroupBy(r => Convert.ToInt64(r[0])).ToDictionary(g => g.Key, g => g.Select(r => (Good: Convert.ToInt64(r[1]), Cycles: Convert.ToDouble(r[2]))).ToList());
        return new(_db.Rows("select id, name, kind, output_id, output_qty, labor_days, capability_id from recipe order by name collate nocase, id").Select(r =>
        {
            long id = Convert.ToInt64(r[0]), output = Convert.ToInt64(r[3]);
            long cap = r[6] == null ? 0 : Convert.ToInt64(r[6]);
            var ins = inputs.GetValueOrDefault(id) ?? new();
            var rqs = reqs.GetValueOrDefault(id) ?? new();
            var inList = new Godot.Collections.Array();
            foreach (var (good, qty, group) in ins) inList.Add(new Dictionary { ["good_id"] = good, ["qty"] = qty, ["group"] = group });
            var reqList = new Godot.Collections.Array();
            foreach (var (good, cycles) in rqs) reqList.Add(new Dictionary { ["good_id"] = good, ["cycles"] = cycles });
            bool ok = goods.ContainsKey(output) && ins.All(i => goods.ContainsKey(i.Good)) && rqs.All(q => goods.ContainsKey(q.Good)) && (cap == 0 || caps.ContainsKey(cap));
            return new Dictionary
            {
                ["id"] = id, ["name"] = Str(r[1]), ["kind"] = Str(r[2]), ["output_id"] = output, ["output_qty"] = Convert.ToDouble(r[4]),
                ["labor_days"] = Convert.ToDouble(r[5]), ["capability_id"] = cap, ["capability"] = caps.GetValueOrDefault(cap, ""),
                ["inputs"] = inList, ["requirements"] = reqList, ["ok"] = ok,
                ["text"] = RecipeText(Str(r[2]), output, Convert.ToDouble(r[4]), Convert.ToDouble(r[5]), ins, rqs, caps.GetValueOrDefault(cap, ""), goods),
            };
        }));
    }

    static string RecipeText(string kind, long output, double qty, double labor, List<(long Good, double Qty, long Group)> inputs,
        List<(long Good, double Cycles)> reqs, string capability, System.Collections.Generic.Dictionary<long, (string Name, string Unit)> goods)
    {
        string Amount(long good, double q) => goods.TryGetValue(good, out var g) ? $"{Num(q)}{(g.Unit != "" ? " " + g.Unit : "")} de {g.Name}" : $"{Num(q)} de (bem que não existe mais)";
        string GoodName(long good) => goods.TryGetValue(good, out var g) ? g.Name : "(bem que não existe mais)";
        var parts = new List<string> { $"{Num(labor)} pessoas-dia" };
        foreach (var group in inputs.GroupBy(i => i.Group == 0 ? -inputs.IndexOf(i) - 1 : i.Group))
            parts.Add(string.Join(" ou ", group.Select(i => Amount(i.Good, i.Qty))));
        string text = string.Join(" e ", parts) + $" → {Amount(output, qty)}";
        if (kind == "extracao") text += " (tirado de uma ocorrência ao alcance)";
        if (capability != "") text += $"; exige saber {capability}";
        if (reqs.Count > 0) text += "; precisa ter " + string.Join(", ", reqs.Select(q => $"{GoodName(q.Good)} (cada um dá {Num(q.Cycles)} vezes por mês)"));
        return text;
    }

    static string Num(double v) => Math.Abs(v - Math.Round(v)) < 1e-9 ? Math.Round(v).ToString("#,0", Pt) : v.ToString("#,0.##", Pt);

    static readonly System.Globalization.CultureInfo Pt = System.Globalization.CultureInfo.GetCultureInfo("pt-BR");

    System.Collections.Generic.Dictionary<long, (string Name, string Unit)> GoodNames() =>
        _db.Rows("select id, name, coalesce(unit, '') from resource_type").ToDictionary(r => Convert.ToInt64(r[0]), r => (Str(r[1]), Str(r[2])));

    // ---- atividades ----

    /// Põe trabalhadores numa receita. Recusa passar do total de trabalhadores do povoado (um trabalhador não fica em duas atividades).
    public long AddActivity(long settlementId, long recipeId, long workers)
    {
        if (_db.Scalar("select 1 from recipe where id = @0", recipeId) == null) throw new ArgumentException("a receita não existe");
        CheckWorkers(settlementId, 0, workers);
        long position = Convert.ToInt64(_db.Scalar("select coalesce(max(position), 0) + 1 from activity where settlement_id = @0", settlementId));
        return _db.Insert("insert into activity(settlement_id, recipe_id, workers, position) values (@0, @1, @2, @3)", settlementId, recipeId, workers, position);
    }

    public void SetActivityWorkers(long id, long workers)
    {
        var r = _db.Rows("select settlement_id from activity where id = @0", id);
        if (r.Count == 0) throw new ArgumentException($"atividade {id} não existe");
        CheckWorkers(Convert.ToInt64(r[0][0]), id, workers);
        _db.Run("update activity set workers = @0 where id = @1", workers, id);
    }

    void CheckWorkers(long settlementId, long exceptActivity, long workers)
    {
        if (workers < 0) throw new ArgumentException("trabalhadores não podem ser negativos");
        var s = _db.Rows("select workers, coalesce((select sum(workers) from activity where settlement_id = @0 and id <> @1), 0) from settlement where id = @0",
            settlementId, exceptActivity);
        if (s.Count == 0) throw new ArgumentException("o povoado não existe");
        long free = Convert.ToInt64(s[0][0]) - Convert.ToInt64(s[0][1]);
        if (workers > free) throw new ArgumentException($"só há {Math.Max(free, 0)} trabalhadores livres neste povoado");
    }

    /// Sobe a atividade uma posição: as de cima ficam primeiro com os trabalhadores e os insumos do mês.
    public void MoveActivityUp(long id)
    {
        _db.Tx(() =>
        {
            var me = _db.Rows("select settlement_id, position from activity where id = @0", id);
            if (me.Count == 0) throw new ArgumentException($"atividade {id} não existe");
            var above = _db.Rows("select id, position from activity where settlement_id = @0 and position < @1 order by position desc limit 1", me[0][0], me[0][1]);
            if (above.Count == 0) return 0;
            _db.Run("update activity set position = @0 where id = @1", above[0][1], id);
            return _db.Run("update activity set position = @0 where id = @1", me[0][1], above[0][0]);
        });
    }

    public void DeleteActivity(long id) => _db.Run("delete from activity where id = @0", id);

    /// As atividades do povoado, na ordem: {id, recipe_id, recipe, text, workers, last (o que aconteceu no último mês processado)}.
    public Array<Dictionary> Activities(long settlementId)
    {
        var recipes = Recipes().ToDictionary(r => (long)r["id"], r => r);
        var last = _db.Rows("""
            select r.activity_id, r.note from production_result r
            where r.settlement_id = @0 and r.run_id = (select max(run_id) from production_result where settlement_id = @0)
            """, settlementId).ToDictionary(r => Convert.ToInt64(r[0]), r => Str(r[1]));
        return new(_db.Rows("select id, recipe_id, workers from activity where settlement_id = @0 order by position, id", settlementId).Select(r =>
        {
            long id = Convert.ToInt64(r[0]), recipe = Convert.ToInt64(r[1]);
            bool known = recipes.TryGetValue(recipe, out var rec);
            return new Dictionary
            {
                ["id"] = id, ["recipe_id"] = recipe, ["workers"] = Convert.ToInt64(r[2]), ["last"] = last.GetValueOrDefault(id, ""),
                ["recipe"] = known ? rec!["name"] : "(receita que não existe mais)", ["text"] = known ? rec!["text"] : "",
            };
        }));
    }

    // ---- estoque ----

    /// O estoque do povoado hoje: {good_id, name, unit, qty}, só os bens com saldo.
    public Array<Dictionary> Stock(long settlementId) => StockAt(settlementId, long.MaxValue);

    /// O estoque do povoado no instante t (a soma das movimentações até t): consultar uma data passada não muda nada.
    public Array<Dictionary> StockAt(long settlementId, long t)
    {
        var goods = GoodNames();
        return new(_db.Rows("select good_id, sum(qty) from stock_movement where settlement_id = @0 and t <= @1 group by good_id having abs(sum(qty)) > 1e-9", settlementId, t)
            .Select(r =>
            {
                long good = Convert.ToInt64(r[0]);
                var (name, unit) = goods.TryGetValue(good, out var g) ? g : ("(bem que não existe mais)", "");
                return new Dictionary { ["good_id"] = good, ["name"] = name, ["unit"] = unit, ["qty"] = Convert.ToDouble(r[1]) };
            }).OrderBy(d => (string)d["name"], StringComparer.Create(Pt, true)));
    }

    /// A soma dos estoques dos povoados que ficam em cada país (pelo território pintado), no instante t. É uma consulta: não há um
    /// segundo estoque que possa ser gasto. {country_id, country, good_id, name, unit, qty}. Povoado fora de país: country_id 0.
    public Array<Dictionary> StockByCountry(Territory countries, Terrain terrain, long t)
    {
        var sums = new System.Collections.Generic.Dictionary<(long Country, long Good), double>();
        var info = new System.Collections.Generic.Dictionary<long, (string Name, string Unit)>();
        foreach (var s in Settlements())
        {
            var p = Vec.FromLatLon((double)s["lat"], (double)s["lon"]);
            long country = countries.OwnerAt(new Vector3((float)p.X, (float)p.Y, (float)p.Z));
            foreach (var item in StockAt((long)s["id"], t))
            {
                long good = (long)item["good_id"];
                sums[(country, good)] = sums.GetValueOrDefault((country, good)) + (double)item["qty"];
                info[good] = ((string)item["name"], (string)item["unit"]);
            }
        }
        return new(sums.OrderBy(kv => kv.Key.Country).ThenBy(kv => info[kv.Key.Good].Name).Select(kv => new Dictionary
        {
            ["country_id"] = kv.Key.Country, ["country"] = kv.Key.Country == 0 ? "Fora de país" : Name(kv.Key.Country),
            ["good_id"] = kv.Key.Good, ["name"] = info[kv.Key.Good].Name, ["unit"] = info[kv.Key.Good].Unit, ["qty"] = kv.Value,
        }));
    }

    double StockOf(long settlementId, long good) =>
        Convert.ToDouble(_db.Scalar("select coalesce(sum(qty), 0) from stock_movement where settlement_id = @0 and good_id = @1", settlementId, good));

    /// Intervenção do autor: põe (qty > 0) ou tira (qty < 0) um bem do estoque, no instante t. Fica no histórico; não tem desfazer
    /// (para corrigir, outra intervenção). Recusa deixar o estoque negativo.
    public void Intervene(long settlementId, long good, double qty, long t, string note)
    {
        if (!(Math.Abs(qty) > Eps && double.IsFinite(qty))) throw new ArgumentException("informe uma quantidade diferente de zero");
        if (!GoodExists(good)) throw new ArgumentException("o bem não existe");
        if (_db.Scalar("select 1 from settlement where id = @0", settlementId) == null) throw new ArgumentException("o povoado não existe");
        _db.Tx(() =>
        {
            double have = StockOf(settlementId, good);
            if (have + qty < -Eps) throw new ArgumentException($"o estoque tem só {Num(have)}: não dá para tirar {Num(-qty)}");
            return _db.Insert("insert into stock_movement(settlement_id, good_id, t, qty, reason, note) values (@0, @1, @2, @3, 'intervencao', @4)",
                settlementId, good, t, qty, Optional(note));
        });
    }

    // ---- reserva das ocorrências ----

    /// A quantidade da ocorrência, na unidade do bem (NaN = desconhecida: volta a ser narrativa). Editar uma sugestão a protege.
    public ResourceEdit SetOccurrenceReserve(long id, double reserve)
    {
        if (!double.IsNaN(reserve) && !(reserve >= 0 && double.IsFinite(reserve))) throw new ArgumentException("a quantidade é zero ou mais");
        return Change("resource_occurrence", OccurrenceColumns, id, () => _db.Run(
            "update resource_occurrence set reserve = @0, fixed = case when origin = 'gerada' then 1 else fixed end where id = @1",
            double.IsNaN(reserve) ? null : reserve, id));
    }

    /// {reserve (a do autor; NaN = desconhecida), extracted (o que já saiu), regrown (o que se renovou), left (NaN se desconhecida), policy}.
    public Dictionary OccurrenceReserve(long id)
    {
        var r = _db.Rows("select reserve, reserve_policy from resource_occurrence where id = @0", id);
        double reserve = r.Count == 0 || r[0][0] == null ? double.NaN : Convert.ToDouble(r[0][0]);
        string policy = r.Count == 0 ? "normal" : Str(r[0][1]);
        double extracted = Extracted(id), regrown = Regrown(id);
        return new Dictionary
        {
            ["reserve"] = reserve, ["extracted"] = extracted, ["regrown"] = regrown, ["policy"] = policy,
            ["left"] = double.IsNaN(reserve) ? double.NaN : policy == "reposicao" ? reserve : Math.Max(reserve - extracted + regrown, 0),
        };
    }

    double Extracted(long occurrence) =>
        Convert.ToDouble(_db.Scalar("select coalesce(sum(qty), 0) from stock_movement where occurrence_id = @0 and reason = 'producao'", occurrence));

    double Regrown(long occurrence) =>
        Convert.ToDouble(_db.Scalar("select coalesce((select regrown from occurrence_state where occurrence_id = @0), 0)", occurrence));

    // ---- o mês ----

    /// Os bens extraídos por alguma atividade: o chamador entrega a camada pintada de cada um (para achar as áreas ao alcance).
    public long[] ExtractedGoods() => _db.Rows("""
        select distinct r.output_id from activity a join recipe r on r.id = a.recipe_id where r.kind = 'extracao'
        """).Select(r => Convert.ToInt64(r[0])).ToArray();

    /// Algum mês já foi processado até este instante (inclusive)?
    public bool MonthDone(long monthEnd) => _db.Scalar("select 1 from production_run where month_end = @0", monthEnd) != null;

    sealed class Draw
    {
        public long Occurrence;
        public double Planned, Taken;
    }

    sealed class Work
    {
        public long Activity, Settlement, Output;
        public double Cycles, OutputQty;
        public System.Collections.Generic.Dictionary<long, double> Use = new();  // bem -> quanto gasta nos ciclos planejados
        public List<Draw> Draws = new();
        public string Reason = "";     // o que limitou
        public bool Extraction;
    }

    /// Processa o mês [start, end) de todos os povoados. layers: id do bem -> Territory (a camada pintada do recurso). Devolve
    /// {ran: false} se esse mês já foi feito (nada muda); senão {ran: true, activities: quantas atividades rodaram}.
    /// O que um mês produz só fica disponível no mês seguinte: assim a ordem das atividades não cria produção em cadeia sem limite.
    public Dictionary RunMonth(long start, long end, Terrain terrain, Dictionary layers)
    {
        if (end <= start) throw new ArgumentException("o mês termina antes de começar");
        if (MonthDone(end)) return new Dictionary { ["ran"] = false };
        double days = (end - start) / 86400.0;
        var goods = GoodNames();
        var recipes = Recipes().ToDictionary(r => (long)r["id"], r => r);
        var maps = new System.Collections.Generic.Dictionary<long, Territory>();
        foreach (var (key, value) in layers) maps[key.AsInt64()] = value.As<Territory>();
        var regrowth = Regrowth(days);                                           // ocorrência -> renovação deste mês
        var left = new System.Collections.Generic.Dictionary<long, double>();  // reserva de cada ocorrência no começo do mês
        var works = new List<Work>();
        string GoodName(long good) => goods.TryGetValue(good, out var g) ? g.Name : "um bem que não existe mais";

        foreach (var s in Settlements())
        {
            long sid = (long)s["id"];
            var stock = Stock(sid).ToDictionary(d => (long)d["good_id"], d => (double)d["qty"]);
            var skills = SettlementCapabilities(sid).ToDictionary(c => (long)c["capability_id"], c => (long)c["proficiency"]);
            long free = (long)s["workers"];
            var here = Vec.FromLatLon((double)s["lat"], (double)s["lon"]);
            foreach (var a in Activities(sid))
            {
                var w = new Work { Activity = (long)a["id"], Settlement = sid };
                works.Add(w);
                if (!recipes.TryGetValue((long)a["recipe_id"], out var rec) || !(bool)rec["ok"])
                {
                    w.Reason = "parou: a receita usa um bem ou uma capacidade que não existe mais";
                    continue;
                }
                long assigned = (long)a["workers"], used = Math.Min(assigned, free);
                free -= used;
                w.Output = (long)rec["output_id"];
                w.OutputQty = (double)rec["output_qty"];
                w.Extraction = (string)rec["kind"] == "extracao";
                double skill = 1;
                long cap = (long)rec["capability_id"];
                if (cap != 0)
                {
                    if (!skills.TryGetValue(cap, out long p))
                    {
                        w.Reason = $"parou: ninguém em {(string)s["name"]} sabe {(string)rec["capability"]}";
                        continue;
                    }
                    skill = p / 100.0;
                }
                double cycles = used * days / (double)rec["labor_days"] * skill;
                w.Reason = used == 0 ? "parou: sem trabalhadores livres" : used < assigned ? $"só {used} de {assigned} pessoas: o povoado não tem mais" : "";
                if (skill < 1 && used > 0 && w.Reason == "") w.Reason = $"prática de {Math.Round(skill * 100)}% em {(string)rec["capability"]}";
                foreach (var q in (Godot.Collections.Array)rec["requirements"])
                {
                    var req = q.AsGodotDictionary();
                    long good = req["good_id"].AsInt64();
                    double limit = stock.GetValueOrDefault(good) * req["cycles"].AsDouble();
                    if (limit < cycles - Eps)
                    {
                        cycles = limit;
                        w.Reason = limit <= Eps ? $"parou: falta {GoodName(good)} (não é gasto, mas é preciso ter)" : $"limitado: poucos {GoodName(good)}";
                    }
                }
                // Insumos: os de grupo 0 sozinhos; os do mesmo grupo se somam (um substitui o outro).
                var groups = ((Godot.Collections.Array)rec["inputs"]).Select(i => i.AsGodotDictionary())
                    .Select(i => (Good: i["good_id"].AsInt64(), Qty: i["qty"].AsDouble(), Group: i["group"].AsInt64())).ToList();
                foreach (var group in groups.GroupBy(i => i.Group == 0 ? -groups.IndexOf(i) - 1 : i.Group))
                {
                    double possible = group.Sum(i => stock.GetValueOrDefault(i.Good) / i.Qty);
                    if (possible < cycles - Eps)
                    {
                        cycles = possible;
                        string names = string.Join(" ou ", group.Select(i => GoodName(i.Good)));
                        w.Reason = possible <= Eps ? $"parou: faltou {names}" : $"limitado: faltou {names}";
                    }
                }
                if (w.Extraction && cycles > Eps)
                {
                    var (sources, why) = Sources(here, (double)s["reach_km"], w.Output, start, terrain, maps, left, regrowth);
                    if (sources.Count == 0 || sources.Sum(o => left[o]) <= Eps)
                    {
                        cycles = 0;
                        w.Reason = why;
                    }
                    else
                    {
                        // Pede o que o trabalho e os insumos permitem, da ocorrência mais perto para a mais longe. O que passa da
                        // reserva fica pedido na mais perto: a divisão abaixo corta na proporção do que cada povoado pediu.
                        double want = cycles * w.OutputQty;
                        foreach (long o in sources)
                        {
                            double take = Math.Min(want, left[o]);
                            if (take > Eps) w.Draws.Add(new Draw { Occurrence = o, Planned = take });
                            want -= take;
                        }
                        if (want > Eps)
                        {
                            var nearest = w.Draws.FirstOrDefault(d => d.Occurrence == sources[0]);
                            if (nearest == null) w.Draws.Insert(0, nearest = new Draw { Occurrence = sources[0] });
                            nearest.Planned += want;
                        }
                    }
                }
                w.Cycles = Math.Max(cycles, 0);
                foreach (var group in groups.GroupBy(i => i.Group == 0 ? -groups.IndexOf(i) - 1 : i.Group))
                {
                    double remaining = w.Cycles;
                    foreach (var (good, qty, _) in group)  // gasta o primeiro da lista; o seguinte só cobre o que faltou
                    {
                        double run = Math.Min(remaining, stock.GetValueOrDefault(good) / qty);
                        if (run <= Eps) continue;
                        w.Use[good] = w.Use.GetValueOrDefault(good) + run * qty;
                        stock[good] = Math.Max(stock.GetValueOrDefault(good) - run * qty, 0);
                        remaining -= run;
                    }
                }
            }
        }

        // Dois povoados na mesma ocorrência: se pedirem mais que a reserva, cada um leva a parte proporcional ao que pediu.
        // Assim a ordem dos povoados no banco não favorece nenhum.
        var shared = new HashSet<long>();
        foreach (var group in works.SelectMany(w => w.Draws.Select(d => (w.Settlement, Draw: d))).GroupBy(x => x.Draw.Occurrence))
        {
            double asked = group.Sum(x => x.Draw.Planned), factor = asked > left[group.Key] + Eps ? left[group.Key] / asked : 1;
            foreach (var x in group) x.Draw.Taken = x.Draw.Planned * factor;
            if (factor < 1 && group.Select(x => x.Settlement).Distinct().Count() > 1) shared.Add(group.Key);
        }
        foreach (var w in works.Where(w => w.Extraction && w.Draws.Count > 0))
        {
            double planned = w.Draws.Sum(d => d.Planned), taken = w.Draws.Sum(d => d.Taken);
            if (taken < planned - Eps)
            {
                double factor = taken / planned;
                w.Cycles *= factor;
                foreach (long good in w.Use.Keys.ToList()) w.Use[good] *= factor;
                w.Reason = w.Draws.Any(d => shared.Contains(d.Occurrence))
                    ? $"limitado: a reserva de {GoodName(w.Output)} foi dividida com outro povoado"
                    : $"limitado: a reserva de {GoodName(w.Output)} ao alcance acabou";
            }
        }

        _db.Tx(() =>
        {
            long run = _db.Insert("insert into production_run(month_start, month_end, engine) values (@0, @1, @2)", start, end, ProductionEngine);
            foreach (var (occurrence, add) in regrowth)
                if (add > Eps)
                    _db.Run("insert into occurrence_state(occurrence_id, regrown) values (@0, @1) on conflict(occurrence_id) do update set regrown = regrown + @1", occurrence, add);
            foreach (var w in works)
            {
                foreach (var (good, qty) in w.Use)
                    if (qty > Eps)
                        _db.Run("insert into stock_movement(settlement_id, good_id, t, qty, reason, run_id) values (@0, @1, @2, @3, 'consumo', @4)",
                            w.Settlement, good, end, -qty, run);
                double made = w.Cycles * w.OutputQty;
                if (made > Eps)
                {
                    if (w.Extraction)
                        foreach (var d in w.Draws.Where(d => d.Taken > Eps))
                            _db.Run("insert into stock_movement(settlement_id, good_id, t, qty, reason, run_id, occurrence_id) values (@0, @1, @2, @3, 'producao', @4, @5)",
                                w.Settlement, w.Output, end, d.Taken, run, d.Occurrence);
                    else
                        _db.Run("insert into stock_movement(settlement_id, good_id, t, qty, reason, run_id) values (@0, @1, @2, @3, 'producao', @4)",
                            w.Settlement, w.Output, end, made, run);
                }
                string unit = goods.TryGetValue(w.Output, out var g) && g.Unit != "" ? " " + g.Unit : "";
                string note = made > Eps ? $"+{Num(made)}{unit} de {GoodName(w.Output)}" + (w.Reason != "" ? $" ({w.Reason})" : "") : w.Reason;
                _db.Run("insert into production_result(run_id, activity_id, settlement_id, cycles, produced, note) values (@0, @1, @2, @3, @4, @5)",
                    run, w.Activity, w.Settlement, w.Cycles, made, note == "" ? "nada produzido" : note);
            }
            return run;
        });
        return new Dictionary { ["ran"] = true, ["activities"] = works.Count };
    }

    /// A renovação do mês de cada ocorrência renovável (por ano × dias ÷ 365), sem passar do que já foi tirado dela.
    System.Collections.Generic.Dictionary<long, double> Regrowth(double days)
    {
        var add = new System.Collections.Generic.Dictionary<long, double>();
        foreach (var r in _db.Rows("select id, renewal from resource_occurrence where renewal > 0 and reserve is not null and reserve_policy = 'normal'"))
        {
            long id = Convert.ToInt64(r[0]);
            double missing = Extracted(id) - Regrown(id);
            if (missing > Eps) add[id] = Math.Min(missing, Convert.ToDouble(r[1]) * days / 365.0);
        }
        return add;
    }

    /// As ocorrências do bem ao alcance que existem no instante t, a mais perto primeiro, e o motivo se não há nenhuma utilizável.
    /// Preenche left com a reserva que resta de cada uma (a do autor − o extraído + o renovado, já com a renovação deste mês).
    (List<long> Sources, string Why) Sources(Vec here, double reachKm, long good, long t, Terrain terrain,
        System.Collections.Generic.Dictionary<long, Territory> maps, System.Collections.Generic.Dictionary<long, double> left,
        System.Collections.Generic.Dictionary<long, double> regrowth)
    {
        var near = new List<(long Id, double Km, object? Reserve, string Policy)>();
        var rows = _db.Rows("""
            select id, kind, lat, lon, reserve, reserve_policy from resource_occurrence
            where type_id = @0 and (valid_from is null or valid_from <= @1) and (valid_to is null or @1 < valid_to)
            """, good, t);
        var disk = new List<int>();
        var weights = new List<float>();
        if (rows.Any(r => Str(r[1]) == "area") && maps.TryGetValue(good, out var map))
        {
            var dir = new Vector3((float)here.X, (float)here.Y, (float)here.Z);
            terrain.DiskInto(dir, Math.Max(reachKm, 0.01), disk, weights);
            disk.Add(terrain.PixelOf(dir));
            var best = new System.Collections.Generic.Dictionary<long, double>();
            foreach (int p in disk)
            {
                long owner = map.Get(p);
                if (owner == 0) continue;
                var c = terrain.DirOf(p);
                double km = Vec.Angle(here, new Vec(c.X, c.Y, c.Z)) * EvronGeo.RadiusKm;
                best[owner] = Math.Min(best.GetValueOrDefault(owner, double.MaxValue), km);
            }
            foreach (var r in rows.Where(r => Str(r[1]) == "area"))
                if (best.TryGetValue(Convert.ToInt64(r[0]), out double km)) near.Add((Convert.ToInt64(r[0]), km, r[4], Str(r[5])));
        }
        foreach (var r in rows.Where(r => Str(r[1]) == "ponto"))
        {
            double km = Vec.Angle(here, Vec.FromLatLon(Convert.ToDouble(r[2]), Convert.ToDouble(r[3]))) * EvronGeo.RadiusKm;
            if (km <= reachKm) near.Add((Convert.ToInt64(r[0]), km, r[4], Str(r[5])));
        }
        string name = Str(_db.Scalar("select name from resource_type where id = @0", good));
        if (near.Count == 0) return (new List<long>(), $"parou: nenhuma ocorrência de {name} a até {Num(reachKm)} km");
        if (near.All(n => n.Policy == "bloqueada")) return (new List<long>(), $"parou: a ocorrência de {name} ao alcance está bloqueada pelo autor");
        var usable = near.Where(n => n.Reserve != null && n.Policy != "bloqueada").OrderBy(n => n.Km).ThenBy(n => n.Id).ToList();
        if (usable.Count == 0) return (new List<long>(), $"parou: a ocorrência de {name} ao alcance não tem quantidade definida (defina em Recursos, aba No mapa)");
        foreach (var n in usable)
            if (!left.ContainsKey(n.Id))
            {
                double reserve = Convert.ToDouble(n.Reserve);
                left[n.Id] = n.Policy == "reposicao" ? reserve  // reposta pelo autor (magia): o extraído não diminui
                    : Math.Max(reserve - Extracted(n.Id) + Regrown(n.Id) + regrowth.GetValueOrDefault(n.Id), 0);
            }
        return (usable.Select(n => n.Id).ToList(), $"parou: a reserva de {name} ao alcance acabou");
    }

    /// Exclui um tipo de recurso só se ninguém o usa: nem ocorrência, nem receita, nem estoque.
    void CheckGoodUnused(long id)
    {
        long uses = Convert.ToInt64(_db.Scalar("""
            select (select count(*) from recipe where output_id = @0) + (select count(*) from recipe_input where good_id = @0)
                 + (select count(*) from recipe_requirement where good_id = @0) + (select count(*) from stock_movement where good_id = @0)
            """, id));
        if (uses > 0) throw new ArgumentException("este recurso é usado em receitas ou estoques: tire-o de lá antes");
    }
}
