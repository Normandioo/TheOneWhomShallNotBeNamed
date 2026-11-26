using System;
using System.Collections.Generic;
using System.Linq;
using Godot;
using Godot.Collections;

namespace Evron;

/// O que faltava das etapas 0 a 3 do plano de recursos (migração 21): categorias e unidades do catálogo; teor, profundidade, acesso,
/// renovação, validade no tempo e política da reserva das ocorrências; quem conhece cada ocorrência e quem tem direitos sobre ela;
/// a divisão de uma área entre países; capacidades, requisitos e insumos alternativos da produção; o aviso de que o relevo mudou
/// depois de uma geração.
public partial class Registry
{
    const string DetailsMigration = """
        alter table resource_occurrence add column grade real check (grade is null or (grade >= 0 and grade <= 100));
        alter table resource_occurrence add column depth_m real check (depth_m is null or depth_m >= 0);
        alter table resource_occurrence add column access text check (access is null or access in ('facil','medio','dificil'));
        alter table resource_occurrence add column renewal real check (renewal is null or renewal >= 0);
        alter table resource_occurrence add column reserve_policy text not null default 'normal'
            check (reserve_policy in ('normal','reposicao','bloqueada'));
        alter table resource_occurrence add column valid_from integer;
        alter table resource_occurrence add column valid_to integer;

        -- Estado de simulação, fora da linha da ocorrência: desfazer uma edição do autor não pode desfazer a renovação.
        create table occurrence_state(occurrence_id integer primary key, regrown real not null default 0);

        -- Sem chave para a ocorrência: excluí-la (e desfazer) mantém o histórico de quem a conhecia e de quem tinha direitos.
        create table occurrence_knowledge(
            id integer primary key autoincrement,
            occurrence_id integer not null,
            entity_id integer not null references entity(id),
            valid_from integer not null,
            valid_to integer not null,
            estimate real check (estimate is null or estimate >= 0),
            note text,
            check (valid_from < valid_to));
        create index occurrence_knowledge_occurrence on occurrence_knowledge(occurrence_id);
        create table resource_right(
            id integer primary key autoincrement,
            occurrence_id integer not null,
            entity_id integer not null references entity(id),
            kind text not null check (kind in ('controle','acesso','exploracao')),
            valid_from integer not null,
            valid_to integer not null,
            note text,
            check (valid_from < valid_to));
        create index resource_right_occurrence on resource_right(occurrence_id);

        create table capability(id integer primary key autoincrement, name text not null);
        create table settlement_capability(
            settlement_id integer not null references settlement(id),
            capability_id integer not null references capability(id),
            proficiency integer not null check (proficiency >= 1 and proficiency <= 100),
            primary key (settlement_id, capability_id));
        alter table recipe add column capability_id integer;
        create table recipe_requirement(
            recipe_id integer not null references recipe(id),
            good_id integer not null,
            cycles real not null check (cycles > 0),
            primary key (recipe_id, good_id));
        alter table recipe_input add column alt_group integer not null default 0;

        alter table resource_generation add column terrain_hash text;
        """;

    // ---- catálogo ----

    /// As categorias do menu de recursos, na ordem em que aparecem.
    public static readonly string[] Categories = { "mineral", "vegetal", "animal", "manufatura" };

    /// As unidades conhecidas e a dimensão de cada uma. Não há conversão entre elas: cada bem usa só a sua.
    static readonly System.Collections.Generic.Dictionary<string, string> UnitDimension = new()
    {
        ["kg"] = "massa", ["t"] = "massa", ["m³"] = "volume", ["L"] = "volume", ["ha"] = "área", ["km²"] = "área",
        ["unidade"] = "contagem", ["cabeça"] = "contagem", ["kcal"] = "energia",
    };

    /// [{unit, dimension}], na ordem de apresentação.
    public Array<Dictionary> Units() => new(UnitDimension.Select(kv => new Dictionary { ["unit"] = kv.Key, ["dimension"] = kv.Value }));

    /// A dimensão da unidade ("" = não informada; "outra" = texto livre).
    public static string DimensionOf(string unit) => unit == "" ? "" : UnitDimension.GetValueOrDefault(unit, "outra");

    // ---- detalhes da ocorrência ----

    /// Teor (%), profundidade (m), acesso, renovação por ano, política da reserva e validade no tempo. NaN e "" = não informado;
    /// long.MinValue em validFrom e long.MaxValue em validTo = sempre. Mudar a validade é uma mudança no mundo, com data: a ocorrência
    /// passa a existir (ou deixa de existir) naquele instante para a produção. Editar uma sugestão a protege.
    public ResourceEdit SetOccurrenceDetails(long id, double grade, double depthM, string access, double renewal, string policy, long validFrom, long validTo)
    {
        if (!double.IsNaN(grade) && !(grade >= 0 && grade <= 100)) throw new ArgumentException("o teor vai de 0 a 100%");
        if (!double.IsNaN(depthM) && !(depthM >= 0 && double.IsFinite(depthM))) throw new ArgumentException("a profundidade é zero ou mais");
        if (access is not ("" or "facil" or "medio" or "dificil")) throw new ArgumentException("o acesso é fácil, médio ou difícil");
        if (!double.IsNaN(renewal) && !(renewal >= 0 && double.IsFinite(renewal))) throw new ArgumentException("a renovação é zero ou mais");
        if (policy is not ("normal" or "reposicao" or "bloqueada")) throw new ArgumentException("política da reserva desconhecida");
        if (validFrom != Always && validTo != Forever && validFrom >= validTo) throw new ArgumentException("a ocorrência deixa de existir antes de começar");
        return Change("resource_occurrence", OccurrenceColumns, id, () => _db.Run("""
            update resource_occurrence set grade = @0, depth_m = @1, access = @2, renewal = @3, reserve_policy = @4, valid_from = @5, valid_to = @6,
                fixed = case when origin = 'gerada' then 1 else fixed end
            where id = @7
            """, double.IsNaN(grade) ? null : grade, double.IsNaN(depthM) ? null : depthM, access == "" ? null : access,
            double.IsNaN(renewal) ? null : renewal, policy, validFrom == Always ? null : validFrom, validTo == Forever ? null : validTo, id));
    }

    /// {grade, depth_m, access, renewal (NaN/"" = não informado), policy, valid_from, valid_to (Always/Forever = sempre)}.
    public Dictionary OccurrenceDetails(long id)
    {
        var r = _db.Rows("select grade, depth_m, access, renewal, reserve_policy, valid_from, valid_to from resource_occurrence where id = @0", id);
        if (r.Count == 0) throw new ArgumentException($"ocorrência {id} não existe");
        double D(object? o) => o == null ? double.NaN : Convert.ToDouble(o);
        return new Dictionary
        {
            ["grade"] = D(r[0][0]), ["depth_m"] = D(r[0][1]), ["access"] = Str(r[0][2]), ["renewal"] = D(r[0][3]), ["policy"] = Str(r[0][4]),
            ["valid_from"] = r[0][5] == null ? Always : Convert.ToInt64(r[0][5]), ["valid_to"] = r[0][6] == null ? Forever : Convert.ToInt64(r[0][6]),
        };
    }

    // ---- quem conhece e quem tem direitos ----

    /// Um país, cultura, etnia (qualquer cadastro) conhece a ocorrência em [from, to), com a estimativa DELE (NaN = sem número). A
    /// estimativa pode divergir da quantidade real: o autor vê as duas.
    public long AddKnowledge(long occurrenceId, long entityId, long from, long to, double estimate, string note)
    {
        CheckOccurrenceAndEntity(occurrenceId, entityId, from, to);
        if (!double.IsNaN(estimate) && !(estimate >= 0 && double.IsFinite(estimate))) throw new ArgumentException("a estimativa é zero ou mais");
        return _db.Insert("insert into occurrence_knowledge(occurrence_id, entity_id, valid_from, valid_to, estimate, note) values (@0, @1, @2, @3, @4, @5)",
            occurrenceId, entityId, from, to, double.IsNaN(estimate) ? null : estimate, Optional(note));
    }

    public void DeleteKnowledge(long id) => _db.Run("delete from occurrence_knowledge where id = @0", id);

    /// {id, entity_id, entity, kind, from, to, estimate (NaN = sem número), note}, todos os períodos.
    public Array<Dictionary> Knowledge(long occurrenceId) => new(_db.Rows(
            "select id, entity_id, valid_from, valid_to, estimate, note from occurrence_knowledge where occurrence_id = @0 order by valid_from, id", occurrenceId)
        .Select(r => new Dictionary
        {
            ["id"] = Convert.ToInt64(r[0]), ["entity_id"] = Convert.ToInt64(r[1]), ["entity"] = Name(Convert.ToInt64(r[1])), ["kind"] = Kind(Convert.ToInt64(r[1])),
            ["from"] = Convert.ToInt64(r[2]), ["to"] = Convert.ToInt64(r[3]), ["estimate"] = r[4] == null ? double.NaN : Convert.ToDouble(r[4]), ["note"] = Str(r[5]),
        }));

    /// As ocorrências que o cadastro conhece no instante t (o que a ficha e o mapa de um observador podem mostrar).
    public long[] KnownBy(long entityId, long t) => _db.Rows(
            "select distinct occurrence_id from occurrence_knowledge where entity_id = @0 and valid_from <= @1 and @1 < valid_to order by occurrence_id", entityId, t)
        .Select(r => Convert.ToInt64(r[0])).ToArray();

    /// Um direito sobre a ocorrência em [from, to): controle, acesso ou exploração. São vínculos diferentes: controlar não dá a
    /// exploração, e um tratado ou concessão é registrado como outro direito.
    public long AddRight(long occurrenceId, long entityId, string kind, long from, long to, string note)
    {
        if (kind is not ("controle" or "acesso" or "exploracao")) throw new ArgumentException("o direito é controle, acesso ou exploração");
        CheckOccurrenceAndEntity(occurrenceId, entityId, from, to);
        return _db.Insert("insert into resource_right(occurrence_id, entity_id, kind, valid_from, valid_to, note) values (@0, @1, @2, @3, @4, @5)",
            occurrenceId, entityId, kind, from, to, Optional(note));
    }

    public void DeleteRight(long id) => _db.Run("delete from resource_right where id = @0", id);

    /// {id, entity_id, entity, kind (do direito), from, to, note}, todos os períodos.
    public Array<Dictionary> Rights(long occurrenceId) => new(_db.Rows(
            "select id, entity_id, kind, valid_from, valid_to, note from resource_right where occurrence_id = @0 order by valid_from, id", occurrenceId)
        .Select(r => new Dictionary
        {
            ["id"] = Convert.ToInt64(r[0]), ["entity_id"] = Convert.ToInt64(r[1]), ["entity"] = Name(Convert.ToInt64(r[1])), ["kind"] = Str(r[2]),
            ["from"] = Convert.ToInt64(r[3]), ["to"] = Convert.ToInt64(r[4]), ["note"] = Str(r[5]),
        }));

    void CheckOccurrenceAndEntity(long occurrenceId, long entityId, long from, long to)
    {
        if (_db.Scalar("select 1 from resource_occurrence where id = @0", occurrenceId) == null) throw new ArgumentException("a ocorrência não existe");
        if (Kind(entityId) == "") throw new ArgumentException("o cadastro não existe");
        if (from >= to) throw new ArgumentException("o período termina antes de começar");
    }

    // ---- divisão entre países ----

    /// Como uma área de recurso cai sobre os países (o território pintado): {country_id (0 = fora de país), country, km2, share, reserve}.
    /// É uma consulta: a ocorrência continua uma só, com a reserva total; a parte de cada país é proporcional à área.
    public Array<Dictionary> OccurrenceShares(long occurrenceId, Territory resourceLayer, Territory countries)
    {
        var over = resourceLayer.OverlapKm2(countries, (int)occurrenceId);
        double total = over.Values.Sum(v => v.AsDouble());
        var reserve = OccurrenceReserve(occurrenceId);
        double left = reserve["left"].AsDouble();
        return new(over.Select(kv => (Country: kv.Key.AsInt64(), Km2: kv.Value.AsDouble())).OrderByDescending(x => x.Km2).Select(x => new Dictionary
        {
            ["country_id"] = x.Country, ["country"] = x.Country == 0 ? "Fora de país" : Name(x.Country), ["km2"] = x.Km2,
            ["share"] = total > 0 ? x.Km2 / total : 0, ["reserve"] = double.IsNaN(left) || total <= 0 ? double.NaN : left * x.Km2 / total,
        }));
    }

    // ---- relevo mudado depois da geração ----

    /// Uma impressão digital do relevo (FNV-1a sobre os bits das altitudes).
    public static string TerrainHash(Terrain terrain)
    {
        ulong h = 14695981039346656037UL;
        foreach (float v in terrain.H) h = (h ^ (uint)BitConverter.SingleToInt32Bits(v)) * 1099511628211UL;
        return h.ToString("x16");
    }

    /// A última geração aplicada a este recurso usou outro relevo? Então as sugestões dela estão desatualizadas (não são refeitas
    /// sozinhas: o que foi extraído não volta e o que é do autor continua).
    public bool GenerationStale(long typeId, Terrain terrain)
    {
        var saved = _db.Scalar("select terrain_hash from resource_generation where type_id = @0 order by id desc limit 1", typeId);
        return saved is string h && h != TerrainHash(terrain);
    }
}
