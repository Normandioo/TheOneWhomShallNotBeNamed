using System;
using System.Collections.Generic;
using System.Linq;
using Godot;
using Godot.Collections;

namespace Evron;

/// Apagar cadastros: a exclusão de um (Delete) e a de categorias inteiras (Opções → Cadastros) passam pelo mesmo lugar, que limpa tudo o
/// que aponta para um cadastro. O território pintado não está aqui: quem tira os pixels é o editor territorial.
public partial class Registry
{
    // O que aponta para um lugar: sem nenhuma destas linhas, o lugar está solto.
    const string LoosePlaces =
        "from place where not exists (select 1 from presence x where x.place_id = place.id) " +
        "and not exists (select 1 from population_estimate x where x.place_id = place.id) " +
        "and not exists (select 1 from distribution x where x.place_id = place.id)";

    /// Marca os cadastros que vão sair numa tabela temporária e apaga, na ordem que as chaves permitem, tudo o que depende deles.
    /// Chamar dentro de uma transação. Devolve quantos cadastros saíram.
    long DeleteMarked(string where, params object?[] args)
    {
        _db.Run("create temp table if not exists doomed(id integer primary key)");
        _db.Run("delete from doomed");
        _db.Run("insert into doomed(id) select id from entity where " + where, args);
        long count = Convert.ToInt64(_db.Scalar("select count(*) from doomed"));
        const string In = " in (select id from doomed)";
        _db.Run($"delete from relation where src{In} or dst{In}");
        _db.Run("delete from calendar_use where entity_id" + In);
        _db.Run("delete from presence where entity_id" + In);
        _db.Run($"delete from distribution_share where distribution_id in (select id from distribution where subject_id{In})");
        _db.Run("delete from distribution where subject_id" + In);
        // Quem era categoria de uma distribuição some dela, e a lista deixa de ser completa (não dá para afirmar que está inteira).
        _db.Run($"update distribution set complete = 0 where id in (select distribution_id from distribution_share where category_id{In})");
        _db.Run("delete from distribution_share where category_id" + In);
        _db.Run($"update distribution set denominator_id = null where denominator_id in (select id from population_estimate where subject_id{In})");
        foreach (var table in new[] { "population_estimate", "population_total" })
            _db.Run($"delete from {table} where subject_id{In}");
        foreach (var table in new[] { "field_override", "rule_result", "occurrence_knowledge", "resource_right" })
            _db.Run($"delete from {table} where entity_id{In}");
        _db.Run("update entity_name set lang_id = null where lang_id" + In);
        foreach (var table in new[] { "entity_name", "field_value", "entity_tag", "division_name" })
            _db.Run($"delete from {table} where entity_id{In}");
        _db.Run("delete from entity where id" + In);
        _db.Run("delete from doomed");
        return count;
    }

    /// Quantos lugares não estão ligados a nada (nem presença, nem população, nem distribuição).
    public long CountLoosePlaces() => Convert.ToInt64(_db.Scalar("select count(*) " + LoosePlaces));

    /// Os ids dos cadastros desses tipos (para tirar o território deles antes de apagar).
    public long[] IdsOfKinds(string[] kinds) =>
        kinds.SelectMany(k => _db.Rows("select id from entity where kind = @0", k).Select(r => Convert.ToInt64(r[0]))).ToArray();

    /// Apaga todos os cadastros desses tipos, com nomes, vínculos, presenças, população e o resto que dependia deles; loosePlaces apaga
    /// também os lugares que ficarem soltos. Tudo numa transação: ou sai tudo, ou nada. Tipos, campos, regras, calendários, recursos,
    /// povoados e o relevo não são tocados. Devolve {entities, places}.
    public Dictionary DeleteKinds(string[] kinds, bool loosePlaces) => _db.Tx(() =>
    {
        long entities = 0;
        foreach (var kind in kinds.Distinct())
            entities += DeleteMarked("kind = @0", kind);
        long places = 0;
        if (loosePlaces)
        {
            places = CountLoosePlaces();
            _db.Run("delete " + LoosePlaces);
        }
        return new Dictionary { ["entities"] = entities, ["places"] = places };
    });
}
