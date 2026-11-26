using System;
using System.Linq;
using Godot;
using Godot.Collections;

namespace Evron;

/// A camada política no banco e a cor de cada país. A camada (o dono de cada pixel, ver Territory) fica numa linha só, comprimida; a cor é uma
/// coluna do cadastro (RGB de 24 bits) e, se o autor não escolheu, sai do id por um passo de matiz áureo: países vizinhos tendem a cores bem diferentes.
public partial class Registry
{
    const string TerritoryMigration = """
        create table territory(
            id integer primary key check (id = 1),
            w integer not null,
            h integer not null,
            data blob not null,
            saved_at integer not null default (unixepoch()));
        alter table entity add column color integer;
        """;

    const string TerritoryBoundaryMigration = "alter table territory add column boundaries blob";

    // Camadas territoriais independentes (especificação 17): uma linha por nível. "provincia" vira tipo de entidade: o CHECK do tipo
    // é reescrito no esquema (afrouxar um CHECK assim é seguro e evita reconstruir entity, referenciada por quase todas as tabelas).
    const string TerritoryLevelsMigration = """
        PRAGMA writable_schema = ON;
        update sqlite_master set sql = replace(sql, 'religiao''))', 'religiao'',''provincia''))')
            where type = 'table' and name = 'entity';
        PRAGMA writable_schema = RESET;
        insert into relation_type values ('provincia_de', 'Província de', 'Províncias', 'provincia', 'pais');
        create table territory_layer(
            level text primary key check (level in ('pais','provincia')),
            w integer not null,
            h integer not null,
            data blob not null,
            boundaries blob,
            saved_at integer not null default (unixepoch()));
        insert into territory_layer(level, w, h, data, boundaries, saved_at) select 'pais', w, h, data, boundaries, saved_at from territory;
        drop table territory;
        """;

    // Terceiro nível: município (dentro de uma província). Mesma técnica de afrouxar os CHECKs.
    const string MunicipalityMigration = """
        PRAGMA writable_schema = ON;
        update sqlite_master set sql = replace(sql, 'provincia''))', 'provincia'',''municipio''))')
            where type = 'table' and name in ('entity', 'territory_layer');
        PRAGMA writable_schema = RESET;
        insert into relation_type values ('municipio_de', 'Município de', 'Municípios', 'municipio', 'provincia');
        """;

    // A camada em tiles (ver TerritoryTiles.cs). A coluna data de territory_layer fica vazia; um mundo anterior ainda com a camada
    // inteira nela é lido de lá e regravado em tiles na próxima gravação.
    const string TerritoryTilesMigration = """
        create table territory_tile(
            level text not null,
            tx integer not null,
            ty integer not null,
            data blob not null,
            primary key (level, tx, ty));
        """;

    // Áreas pintadas de religião, cultura, etnia, raça e idioma: cada uma é uma camada como a dos países (o que predomina em cada pixel).
    const string CulturalLayersMigration = """
        PRAGMA writable_schema = ON;
        update sqlite_master set sql = replace(sql, 'municipio''))', 'municipio'',''religiao'',''cultura'',''etnia'',''raca'',''idioma''))')
            where type = 'table' and name = 'territory_layer';
        PRAGMA writable_schema = RESET;
        """;

    /// As camadas pintáveis. As três primeiras são a hierarquia política, do maior para o menor: cada nível abaixo do primeiro se liga ao
    /// de cima pelo vínculo "<nível>_de" (província de, município de). As outras são áreas de predominância, independentes.
    public static readonly string[] Levels = { "pais", "provincia", "municipio", "religiao", "cultura", "etnia", "raca", "idioma" };
    static readonly string[] Hierarchy = { "pais", "provincia", "municipio" };

    /// O cadastro do nível de cima a que esta província ou município pertence hoje (vínculo "<nível>_de"); 0 se não tem ou não é desses níveis.
    public long TerritoryParent(long id)
    {
        string kind = Kind(id);
        if (System.Array.IndexOf(Hierarchy, kind) < 1) return 0;
        return _db.Scalar("select dst from relation where src = @0 and type = @1 and valid_to = @2 order by valid_from desc limit 1",
            id, kind + "_de", Forever) is object o ? Convert.ToInt64(o) : 0;
    }

    /// TerritoryParent de todas as províncias e municípios numa consulta só: {id: o de cima}. Para quem precisa de muitos (a paleta do
    /// mapa fazia várias consultas por cadastro, e num mundo grande isso aparecia a cada releitura de ficha).
    public Godot.Collections.Dictionary TerritoryParents()
    {
        var parents = new Godot.Collections.Dictionary();
        foreach (var r in _db.Rows("select r.src, r.dst from relation r join entity e on e.id = r.src " +
                                   "where r.type = e.kind || '_de' and r.valid_to = @0 and e.kind in ('provincia', 'municipio') order by r.valid_from", Forever))
            parents[Convert.ToInt64(r[0])] = Convert.ToInt64(r[1]);
        return parents;
    }

    /// Grava a camada dos países (substitui a anterior). Devolve o tamanho gravado, em bytes.
    public long SaveTerritory(Territory t) => SaveTerritoryLevel("pais", t);

    /// Lê a camada dos países. false se não há nenhuma (começa vazio) ou se é de outra grade (não é aplicada).
    public bool LoadTerritory(Territory t) => LoadTerritoryLevel("pais", t);

    /// Grava a camada de um nível ("pais", "provincia" ou "municipio"); as dos outros níveis não mudam. Só os tiles mexidos desde a
    /// última gravação neste banco são regravados (uma camada que não veio deste banco é gravada inteira e substitui a anterior).
    /// Devolve os bytes escritos nos tiles.
    public long SaveTerritoryLevel(string level, Territory t) => SaveTerritories(new[] { (level, t) });

    /// Confirma todos os níveis alterados em uma só transação.
    public bool SaveTerritoryLevels(Dictionary layers)
    {
        try
        {
            SaveTerritories(layers.Select(pair => (pair.Key.AsString(), pair.Value.As<Territory>())).ToArray());
            return true;
        }
        catch (Exception e)
        {
            GD.PushError("Não consegui gravar os territórios: " + e.Message);
            return false;
        }
    }

    private long SaveTerritories((string Level, Territory Map)[] layers)
    {
        long written = _db.Tx(() =>
        {
            long bytes = 0;
            foreach (var (level, map) in layers)
                bytes += WriteTerritoryLevel(CheckLevel(level), map);
            return bytes;
        });
        foreach (var (level, map) in layers)
        {
            map.ClearDirtyTiles();
            map.SyncedKey = $"{_openKey}:{level}";
        }
        return written;
    }

    private long WriteTerritoryLevel(string level, Territory t)
    {
        bool full = t.SyncedKey != $"{_openKey}:{level}";
        long bytes = 0;
        _db.Run("insert into territory_layer(level, w, h, data, boundaries, saved_at) values (@4, @0, @1, @2, @3, unixepoch()) " +
                "on conflict(level) do update set w = @0, h = @1, data = @2, boundaries = @3, saved_at = unixepoch()",
                t.Size.X, t.Size.Y, System.Array.Empty<byte>(), t.PackBoundaries(), level);
        if (full) _db.Run("delete from territory_tile where level = @0", level);
        foreach (var (tx, ty) in t.Tiles(onlyDirty: !full))
        {
            var data = t.PackTile(tx, ty);
            if (data == null)
            {
                if (!full) _db.Run("delete from territory_tile where level = @0 and tx = @1 and ty = @2", level, tx, ty);
                continue;
            }
            _db.Run("insert into territory_tile(level, tx, ty, data) values (@0, @1, @2, @3) " +
                    "on conflict(level, tx, ty) do update set data = @3", level, tx, ty, data);
            bytes += data.Length;
        }
        return bytes;
    }

    public bool LoadTerritoryLevel(string level, Territory t)
    {
        var r = _db.Rows("select w, h, data, boundaries from territory_layer where level = @0", CheckLevel(level));
        if (r.Count == 0) return false;
        int w = Convert.ToInt32(r[0][0]), h = Convert.ToInt32(r[0][1]);
        var legacy = (byte[])r[0][2]!;
        if (legacy.Length > 0)  // mundo anterior aos tiles: a camada inteira numa linha; a próxima gravação a passa para tiles
        {
            if (!t.Restore(legacy, w, h, (byte[]?)r[0][3])) return false;
            t.SyncedKey = null;
            return true;
        }
        var tiles = _db.Rows("select tx, ty, data from territory_tile where level = @0", level)
            .Select(x => (Convert.ToInt32(x[0]), Convert.ToInt32(x[1]), (byte[])x[2]!));
        if (!t.RestoreTiles(w, h, tiles, (byte[]?)r[0][3])) return false;
        t.SyncedKey = $"{_openKey}:{level}";
        return true;
    }

    static string CheckLevel(string level) =>
        System.Array.IndexOf(Levels, level) >= 0 || ResourceTypeOfLevel(level) > 0 ? level : throw new ArgumentException($"nível territorial desconhecido: {level}");

    /// Avisos de inconsistência entre um nível e o de cima (não corrige nada), por exemplo províncias (lower) e países (upper):
    /// "fora" = parte da província em outro país ou fora de qualquer país; "sem_pais" = província pintada sem o vínculo com o de cima;
    /// "lacuna" = terra de um país que tem províncias e não está em nenhuma. Sobreposição dentro de um nível não existe: cada pixel
    /// tem um dono só. Cada aviso: {kind, id, country (o de cima), area_km2}.
    public Array<Dictionary> TerritoryWarnings(Territory countries, Territory provinces) => LevelWarnings("provincia", countries, provinces);

    public Array<Dictionary> LevelWarnings(string lowerLevel, Territory countries, Territory provinces)
    {
        if (System.Array.IndexOf(Levels, CheckLevel(lowerLevel)) < 1) throw new ArgumentException($"{lowerLevel} não tem nível acima");
        if (provinces.Size != countries.Size) throw new ArgumentException("as camadas são de grades diferentes");
        var parent = new System.Collections.Generic.Dictionary<int, int>();
        foreach (var r in _db.Rows("select e.id, (select dst from relation where src = e.id and type = @1 and valid_to = @0 " +
                                   "order by valid_from desc limit 1) from entity e where e.kind = @2 and e.id <= 65535",
                                   Forever, lowerLevel + "_de", lowerLevel))
            parent[Convert.ToInt32(r[0])] = r[1] != null ? Convert.ToInt32(r[1]) : 0;
        var hasProvince = new System.Collections.Generic.HashSet<int>(parent.Values);
        var outside = new System.Collections.Generic.Dictionary<int, double>();
        var gap = new System.Collections.Generic.Dictionary<int, double>();
        int w = countries.Size.X, h = countries.Size.Y;
        for (int y = 0; y < h; y++)
        {
            double cell = Territory.RowCellKm2(y, w, h);
            for (int i = y * w; i < (y + 1) * w; i++)
            {
                int p = provinces.Get(i), c = countries.Get(i);
                if (p != 0 && parent.TryGetValue(p, out int want) && want != 0 && want != c)
                    outside[p] = (outside.TryGetValue(p, out double a) ? a : 0) + cell;
                else if (p == 0 && c != 0 && hasProvince.Contains(c))
                    gap[c] = (gap.TryGetValue(c, out double b) ? b : 0) + cell;
            }
        }
        var list = new Array<Dictionary>();
        foreach (var (p, km2) in outside.OrderBy(kv => kv.Key))
            list.Add(new Dictionary { ["kind"] = "fora", ["id"] = p, ["country"] = parent[p], ["area_km2"] = km2 });
        foreach (var (p, c) in parent.OrderBy(kv => kv.Key))
            if (c == 0 && provinces.AreaKm2(p) > 0)
                list.Add(new Dictionary { ["kind"] = "sem_pais", ["id"] = p, ["country"] = 0, ["area_km2"] = provinces.AreaKm2(p) });
        foreach (var (c, km2) in gap.OrderBy(kv => kv.Key))
            list.Add(new Dictionary { ["kind"] = "lacuna", ["id"] = c, ["country"] = c, ["area_km2"] = km2 });
        return list;
    }

    /// A cor do cadastro (RGB de 24 bits): a escolhida ou a automática.
    public long EntityColor(long id)
    {
        var r = _db.Rows("select color from entity where id = @0", id);
        if (r.Count == 0) throw new ArgumentException($"entidade {id} não existe");
        return r[0][0] != null ? Convert.ToInt64(r[0][0]) : DefaultColor(id);
    }

    /// Escolhe a cor (RGB de 24 bits, 0 a 16777215).
    public void SetEntityColor(long id, long rgb)
    {
        if (rgb < 0 || rgb > 0xFFFFFF) throw new ArgumentException($"cor fora de 0..16777215: {rgb}");
        if (_db.Run("update entity set color = @0 where id = @1", rgb, id) == 0) throw new ArgumentException($"entidade {id} não existe");
    }

    static long DefaultColor(long id)
    {
        double hue = (id * 0.6180339887498949) % 1.0;
        var c = Color.FromHsv((float)hue, 0.45f, 0.92f);
        return ((long)Math.Round(c.R * 255) << 16) | ((long)Math.Round(c.G * 255) << 8) | (long)Math.Round(c.B * 255);
    }

    /// A paleta da camada dos países: id e cor (RGB) de cada país que pode ter território (id até 65535).
    public Array<Dictionary> CountryPalette() => Palette("pais");

    /// A paleta de um nível territorial: as entidades desse tipo que podem ter território (id até 65535).
    /// Na camada de um recurso os donos são as ocorrências em área dele, todas na cor do recurso.
    public Array<Dictionary> Palette(string level) => new(
        (ResourceTypeOfLevel(level) is long type && type > 0
            ? _db.Rows("select o.id, t.rgb from resource_occurrence o join resource_type t on t.id = o.type_id where o.type_id = @0 and o.kind = 'area' order by o.id", type)
            : _db.Rows("select id, color from entity where kind = @0 and id <= 65535 order by id", CheckLevel(level)))
           .Select(r => new Dictionary { ["id"] = Convert.ToInt64(r[0]), ["rgb"] = r[1] != null ? Convert.ToInt64(r[1]) : DefaultColor(Convert.ToInt64(r[0])) }));
}
