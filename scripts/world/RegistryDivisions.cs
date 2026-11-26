using System;
using System.Collections.Generic;
using System.Linq;
using Godot.Collections;

namespace Evron;

/// Subdivisões: para o autor, província e município são o mesmo tipo de coisa, em dois níveis. O nível é o kind ("provincia" = 1º,
/// "municipio" = 2º, cada um na sua camada pintada); o que muda é o nome que se mostra. Vale o nome próprio da divisão; sem ele, o que
/// o país dá àquele nível; sem isso, "Província" e "Município".
public partial class Registry
{
    const string DivisionNamesMigration = """
        create table division_name(
            entity_id integer not null references entity(id),
            level integer not null check (level in (0, 1, 2)),  -- 0: o nome próprio da divisão; 1 e 2: o que um país dá ao nível
            name text not null,
            primary key (entity_id, level));
        update entity_type set label = 'Subdivisão (1º nível)' where code = 'provincia';
        update entity_type set label = 'Subdivisão (2º nível)' where code = 'municipio';
        """;

    const int DivisionNameLength = 40;

    static int DivisionLevel(string kind) => kind == "provincia" ? 1 : kind == "municipio" ? 2 : 0;

    static string DefaultDivisionName(int level) => level == 1 ? "Província" : "Município";

    string? StoredDivisionName(long id, int level) =>
        _db.Scalar("select name from division_name where entity_id = @0 and level = @1", id, level)?.ToString();

    void StoreDivisionName(long id, int level, string name)
    {
        if (name == "") _db.Run("delete from division_name where entity_id = @0 and level = @1", id, level);
        else _db.Run("insert or replace into division_name(entity_id, level, name) values (@0, @1, @2)", id, level, name);
    }

    static string CleanDivisionName(string name)
    {
        name = name.Trim();
        return name.Length > DivisionNameLength ? name[..DivisionNameLength].Trim() : name;
    }

    /// O país no alto da cadeia de uma divisão; 0 se ela não chega a nenhum.
    public long CountryOf(long id)
    {
        for (int step = 0; step < 2; step++)
        {
            id = TerritoryParent(id);
            if (id == 0) return 0;
            if (Kind(id) == "pais") return id;
        }
        return 0;
    }

    /// Como o país chama o nível (1 ou 2). countryId 0 = o padrão.
    public string LevelName(long countryId, long level) =>
        (countryId != 0 ? StoredDivisionName(countryId, (int)level) : null) ?? DefaultDivisionName((int)level);

    /// Muda o nome do nível no país: vale para todas as divisões dele que não têm nome próprio. "" volta ao padrão.
    public void SetLevelName(long countryId, long level, string name)
    {
        if (Kind(countryId) != "pais" || level is not (1 or 2)) throw new ArgumentException("só um país dá nome aos níveis 1 e 2");
        name = CleanDivisionName(name);
        StoreDivisionName(countryId, (int)level, name == DefaultDivisionName((int)level) ? "" : name);
    }

    /// Como esta divisão se chama ("Estado", "Condado"...); "" se o cadastro não é uma divisão.
    public string DivisionName(long id)
    {
        int level = DivisionLevel(Kind(id));
        return level == 0 ? "" : StoredDivisionName(id, 0) ?? LevelName(CountryOf(id), level);
    }

    /// Dá a esta divisão um nome diferente das outras. "" ou o mesmo nome do nível: volta a seguir o país.
    public void SetDivisionName(long id, string name)
    {
        int level = DivisionLevel(Kind(id));
        if (level == 0) throw new ArgumentException($"o cadastro {id} não é uma divisão");
        name = CleanDivisionName(name);
        StoreDivisionName(id, 0, name == LevelName(CountryOf(id), level) ? "" : name);
    }

    /// O nome escolhido para uma divisão recém-criada: se ela é a primeira do nível no país, o nome passa a ser o do nível.
    public void NameNewDivision(long id, string name)
    {
        int level = DivisionLevel(Kind(id));
        long country = level == 0 ? 0 : CountryOf(id);
        if (country != 0 && StoredDivisionName(country, level) == null && !Subdivisions().Any(p =>
                p.Key != id && p.Value.Level == level && p.Value.Country == country))
            SetLevelName(country, level, name);
        else if (level != 0)
            SetDivisionName(id, name);
    }

    /// Os nomes que o menu oferece: os de sempre e os que o autor já escreveu.
    public string[] DivisionSuggestions() =>
        new[] { "Província", "Estado", "Condado", "Ducado", "Município", "Distrito", "Região" }
            .Concat(_db.Rows("select distinct name from division_name order by name").Select(r => Str(r[0])))
            .Distinct().ToArray();

    record struct Subdivision(int Level, long Parent, long Country, string Label, bool Differs);

    /// Todas as divisões de uma vez: o de cima, o país, o nome que se mostra e se ele é diferente do das outras do nível.
    System.Collections.Generic.Dictionary<long, Subdivision> Subdivisions()
    {
        var parents = new System.Collections.Generic.Dictionary<long, long>();
        foreach (var (child, above) in TerritoryParents()) parents[child.AsInt64()] = above.AsInt64();
        var stored = new System.Collections.Generic.Dictionary<(long, int), string>();
        foreach (var r in _db.Rows("select entity_id, level, name from division_name"))
            stored[(Convert.ToInt64(r[0]), Convert.ToInt32(r[1]))] = Str(r[2]);
        var kinds = new System.Collections.Generic.Dictionary<long, string>();
        foreach (var r in _db.Rows("select id, kind from entity where kind in ('pais', 'provincia', 'municipio')"))
            kinds[Convert.ToInt64(r[0])] = Str(r[1]);
        var all = new System.Collections.Generic.Dictionary<long, Subdivision>();
        foreach (var (id, kind) in kinds)
        {
            int level = DivisionLevel(kind);
            if (level == 0) continue;
            long parent = parents.GetValueOrDefault(id), top = parent;
            if (top != 0 && kinds.GetValueOrDefault(top) != "pais") top = parents.GetValueOrDefault(top);
            if (top != 0 && kinds.GetValueOrDefault(top) != "pais") top = 0;
            string inherited = stored.GetValueOrDefault((top, level)) ?? DefaultDivisionName(level);
            string label = stored.GetValueOrDefault((id, 0)) ?? inherited;
            all[id] = new Subdivision(level, parent, top, label, label != inherited);
        }
        return all;
    }

    /// A árvore dos Registros e das Divisões: TODOS os cadastros em ordem de nome, sem o limite da busca.
    /// {id, kind, name, parent (0 = nenhum), label (o nome da divisão, "" nos outros), differs}.
    public Array<Dictionary> Outline(long t)
    {
        var subdivisions = Subdivisions();
        return new(Matching("", "", "", 0, t).Select(hit =>
        {
            var sub = subdivisions.GetValueOrDefault(hit.Id);
            return new Dictionary { ["id"] = hit.Id, ["kind"] = hit.Kind, ["name"] = hit.Name, ["parent"] = sub.Parent,
                                    ["label"] = sub.Label ?? "", ["differs"] = sub.Differs };
        }));
    }
}
