using System;
using System.Linq;
using Godot.Collections;

namespace Evron;

/// Catálogo de recursos e ocorrências (etapa 1 do plano de recursos; contratos em docs/recursos/contratos.md).
/// Tudo é autoral e narrativo: nenhuma regra ambiental limita onde um recurso pode estar. Cada método que grava devolve um
/// ResourceEdit já aplicado, para a pilha de desfazer.
public partial class Registry
{
    // autoincrement: um id excluído nunca vira outro registro (a identidade é estável e o desfazer devolve o mesmo id).
    const string ResourcesMigration = """
        create table resource_type(
            id integer primary key autoincrement,
            world_id integer not null default 1 references world(id),
            name text not null,
            description text,
            category text,
            unit text,
            rgb integer not null,
            created_at integer not null default (unixepoch()));

        create table resource_occurrence(
            id integer primary key autoincrement,
            world_id integer not null default 1 references world(id),
            type_id integer not null references resource_type(id),
            name text,
            lat real not null check (lat >= -90 and lat <= 90),
            lon real not null check (lon >= -180 and lon <= 180),
            radius_km real not null default 0 check (radius_km >= 0),
            vertices text,
            origin text not null default 'manual' check (origin in ('manual','importada','gerada')),
            state text not null default 'narrativo' check (state in ('narrativo','simulado')),
            note text,
            created_at integer not null default (unixepoch()));
        create index resource_occurrence_type on resource_occurrence(type_id);
        """;

    // Ocorrência passa a ser ponto ou ÁREA PINTADA (como os países: uma camada por recurso, o dono do pixel é o id da ocorrência),
    // e as regiões desenhadas ponto a ponto saem do mundo, com os vínculos e números presos a elas.
    const string PaintedShapesMigration = """
        update distribution set denominator_id = null where denominator_id in
            (select id from population_estimate where place_id in (select place_id from place_vertex));
        delete from distribution_share where distribution_id in
            (select id from distribution where place_id in (select place_id from place_vertex));
        delete from distribution where place_id in (select place_id from place_vertex);
        delete from population_estimate where place_id in (select place_id from place_vertex);
        delete from presence where place_id in (select place_id from place_vertex);
        create temp table drawn_place as select distinct place_id from place_vertex;
        drop table place_vertex;
        delete from place where id in (select place_id from drawn_place);
        drop table drawn_place;

        alter table resource_occurrence rename to resource_occurrence_old;
        create table resource_occurrence(
            id integer primary key autoincrement,
            world_id integer not null default 1 references world(id),
            type_id integer not null references resource_type(id),
            name text,
            kind text not null check (kind in ('ponto','area')),
            lat real check (lat >= -90 and lat <= 90),
            lon real check (lon >= -180 and lon <= 180),
            origin text not null default 'manual' check (origin in ('manual','importada','gerada')),
            state text not null default 'narrativo' check (state in ('narrativo','simulado')),
            note text,
            created_at integer not null default (unixepoch()),
            check ((kind = 'ponto') = (lat is not null and lon is not null)));
        insert into resource_occurrence(id, world_id, type_id, name, kind, lat, lon, origin, state, note, created_at)
            select id, world_id, type_id, name, 'ponto', lat, lon, origin, state, note, created_at from resource_occurrence_old;
        drop table resource_occurrence_old;
        create index resource_occurrence_type on resource_occurrence(type_id);

        PRAGMA writable_schema = ON;
        update sqlite_master set sql = replace(sql, '''idioma''))', '''idioma'') or level glob ''recurso:*'')')
            where type = 'table' and name = 'territory_layer';
        PRAGMA writable_schema = RESET;
        """;

    static readonly string[] TypeColumns = { "world_id", "name", "description", "category", "unit", "rgb", "created_at", "rule" };
    static readonly string[] OccurrenceColumns =
        { "world_id", "type_id", "name", "kind", "lat", "lon", "origin", "state", "note", "created_at", "fixed", "generation_id", "gen_lat", "gen_lon", "gen_km", "reserve" };

    /// O prefixo da camada pintável de um recurso: "recurso:<id do tipo>".
    public const string ResourceLevelPrefix = "recurso:";

    static long ResourceTypeOfLevel(string level) =>
        level.StartsWith(ResourceLevelPrefix, StringComparison.Ordinal) &&
        long.TryParse(level.AsSpan(ResourceLevelPrefix.Length), out long id) && id > 0 ? id : 0;

    // Cores bem separadas para os primeiros tipos; o autor pode trocar.
    static readonly long[] ResourcePalette = { 0xE8A33D, 0x4FC3C7, 0xC86BD1, 0x8FD14F, 0xE5655B, 0x6B8CE8, 0xE8D44F, 0xB08D6A };

    // ---- catálogo ----

    /// Cria um tipo de recurso só com o nome.
    public ResourceEdit CreateResourceType(string name)
    {
        name = Clean(name);
        return _db.Tx(() =>
        {
            long n = Convert.ToInt64(_db.Scalar("select count(*) from resource_type"));
            long id = _db.Insert("insert into resource_type(name, rgb) values (@0, @1)", name, ResourcePalette[n % ResourcePalette.Length]);
            return Edit("resource_type", TypeColumns, id, null);
        });
    }

    /// Troca os dados do tipo. Texto vazio = não preenchido; rgb é a cor no mapa (24 bits).
    public ResourceEdit SetResourceType(long id, string name, string description, string category, string unit, long rgb)
    {
        name = Clean(name);
        return Change("resource_type", TypeColumns, id, () => _db.Run(
            "update resource_type set name = @0, description = @1, category = @2, unit = @3, rgb = @4 where id = @5",
            name, Optional(description), Optional(category), Optional(unit), rgb & 0xFFFFFF, id));
    }

    /// Exclui um tipo sem ocorrências (nada some em cascata).
    public ResourceEdit DeleteResourceType(long id)
    {
        long uses = Convert.ToInt64(_db.Scalar("select count(*) from resource_occurrence where type_id = @0", id));
        if (uses > 0) throw new ArgumentException($"o recurso {id} tem {uses} ocorrência(s): exclua-as antes");
        CheckGoodUnused(id);
        return Remove("resource_type", TypeColumns, id);
    }

    /// Os tipos cujo nome contém o texto (sem diferenciar maiúsculas nem acentos); vazio lista todos, por nome.
    public Array<Dictionary> ResourceTypes(string text) =>
        new(_db.Rows("""
                select t.id, t.name, t.description, t.category, t.unit, t.rgb,
                       (select count(*) from resource_occurrence o where o.type_id = t.id)
                from resource_type t order by t.name collate nocase, t.id
                """)
            .Where(r => Matches(Str(r[1]), text))
            .Select(r => new Dictionary
            {
                ["id"] = Convert.ToInt64(r[0]), ["name"] = Str(r[1]), ["description"] = Str(r[2]), ["category"] = Str(r[3]),
                ["unit"] = Str(r[4]), ["rgb"] = Convert.ToInt64(r[5]), ["count"] = Convert.ToInt64(r[6]),
            }));

    // ---- ocorrências ----

    /// Coloca um ponto (um local pequeno, como uma mina), em qualquer lugar do planeta.
    public ResourceEdit AddPoint(long typeId, double lat, double lon)
    {
        CheckPoint(lat, lon);
        return _db.Tx(() =>
        {
            long id = _db.Insert("insert into resource_occurrence(type_id, kind, lat, lon) values (@0, 'ponto', @1, @2)", typeId, lat, lon);
            return Edit("resource_occurrence", OccurrenceColumns, id, null);
        });
    }

    /// Cria uma ocorrência em área, ainda sem pixels: pinta-se na camada do recurso com o id dela como dono.
    public ResourceEdit AddArea(long typeId) => _db.Tx(() =>
    {
        long id = _db.Insert("insert into resource_occurrence(type_id, kind) values (@0, 'area')", typeId);
        // O dono de um pixel tem 2 bytes; o topo da faixa é da prévia de geração e do rascunho territorial.
        if (id >= ResourcePlan.PreviewBase) throw new InvalidOperationException("o mundo chegou ao limite de áreas de recurso");
        return Edit("resource_occurrence", OccurrenceColumns, id, null);
    });

    public ResourceEdit MovePoint(long id, double lat, double lon)
    {
        CheckPoint(lat, lon);
        RequirePoint(id);
        return Change("resource_occurrence", OccurrenceColumns, id, () => _db.Run(
            "update resource_occurrence set lat = @0, lon = @1, fixed = 1 where id = @2", lat, lon, id));
    }

    /// Nome próprio (opcional) e anotação da ocorrência.
    public ResourceEdit SetOccurrenceText(long id, string name, string note) =>
        Change("resource_occurrence", OccurrenceColumns, id, () => _db.Run(
            "update resource_occurrence set name = @0, note = @1, fixed = 1 where id = @2", Optional(name), Optional(note), id));

    /// Cópia de um ponto com identidade nova, no mesmo lugar (mova em seguida). Áreas do mesmo recurso não se sobrepõem.
    public ResourceEdit DuplicatePoint(long id) => _db.Tx(() =>
    {
        RequirePoint(id);
        long copy = _db.Insert("""
            insert into resource_occurrence(world_id, type_id, name, kind, lat, lon, state, note)
            select world_id, type_id, name, kind, lat, lon, state, note from resource_occurrence where id = @0
            """, id);
        return Edit("resource_occurrence", OccurrenceColumns, copy, null);
    });

    /// Apaga o registro. Os pixels de uma área são apagados por quem tem a camada, no mesmo comando de desfazer.
    public ResourceEdit DeleteOccurrence(long id) => Remove("resource_occurrence", OccurrenceColumns, id);

    /// As ocorrências de um tipo (0 = todas), na ordem de criação: {id, type_id, type, rgb, name, kind ("ponto" | "area"),
    /// lat, lon (0 numa área), origin, state, note}.
    public Array<Dictionary> Occurrences(long typeId) =>
        new(_db.Rows("""
                select o.id, o.type_id, t.name, t.rgb, o.name, o.kind, o.lat, o.lon, o.origin, o.state, o.note, o.fixed
                from resource_occurrence o join resource_type t on t.id = o.type_id
                where @0 = 0 or o.type_id = @0 order by o.id
                """, typeId)
            .Select(r => new Dictionary
            {
                ["id"] = Convert.ToInt64(r[0]), ["type_id"] = Convert.ToInt64(r[1]), ["type"] = Str(r[2]), ["rgb"] = Convert.ToInt64(r[3]),
                ["name"] = Str(r[4]), ["kind"] = Str(r[5]), ["lat"] = r[6] == null ? 0.0 : Convert.ToDouble(r[6]),
                ["lon"] = r[7] == null ? 0.0 : Convert.ToDouble(r[7]), ["origin"] = Str(r[8]), ["state"] = Str(r[9]), ["note"] = Str(r[10]), ["fixed"] = Convert.ToInt64(r[11]) == 1,
            }));

    /// O tipo de uma ocorrência; 0 se ela não existe.
    public long OccurrenceType(long id) =>
        _db.Scalar("select type_id from resource_occurrence where id = @0", id) is object o ? Convert.ToInt64(o) : 0;

    /// O nome para mostrar: o próprio ou "Sal, área 3", com o mesmo número da lista do painel (a ordem de criação entre as
    /// ocorrências do mesmo tipo e forma); "" se a ocorrência não existe.
    public string OccurrenceLabel(long id) => _db.Scalar("""
        select coalesce(o.name, t.name || case o.kind when 'area' then ', área ' else ', ponto ' end ||
            (select count(*) from resource_occurrence x where x.type_id = o.type_id and x.kind = o.kind and x.id <= o.id))
        from resource_occurrence o join resource_type t on t.id = o.type_id where o.id = @0
        """, id)?.ToString() ?? "";

    /// Os pontos de um tipo a até toleranceKm de (lat, lon), o mais perto primeiro.
    public long[] PointsAt(long typeId, double lat, double lon, double toleranceKm)
    {
        var here = Vec.FromLatLon(lat, lon);
        return _db.Rows("select id, lat, lon from resource_occurrence where type_id = @0 and kind = 'ponto'", typeId)
            .Select(r => (Id: Convert.ToInt64(r[0]), Km: Vec.Angle(here, Vec.FromLatLon(Convert.ToDouble(r[1]), Convert.ToDouble(r[2]))) * EvronGeo.RadiusKm))
            .Where(x => x.Km <= toleranceKm).OrderBy(x => x.Km).Select(x => x.Id).ToArray();
    }

    // ---- comum ----

    static string? Optional(string text) => text.Trim().Length == 0 ? null : text.Trim();

    static void CheckPoint(double lat, double lon)
    {
        // As comparações são falsas para NaN, então ele também é recusado.
        if (!(lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180)) throw new ArgumentException("coordenadas fora do planeta");
    }

    void RequirePoint(long id)
    {
        if (_db.Scalar("select 1 from resource_occurrence where id = @0 and kind = 'ponto'", id) == null)
            throw new ArgumentException($"a ocorrência {id} não é um ponto");
    }

    object?[]? Snapshot(string table, string[] columns, long id)
    {
        var rows = _db.Rows($"select {string.Join(", ", columns)} from {table} where id = @0", id);
        return rows.Count == 0 ? null : rows[0];
    }

    ResourceEdit Edit(string table, string[] columns, long id, object?[]? before) =>
        ResourceEdit.Done(_db, table, columns, id, before, Snapshot(table, columns, id));

    ResourceEdit Change(string table, string[] columns, long id, Func<int> write) => _db.Tx(() =>
    {
        var before = Snapshot(table, columns, id) ?? throw new ArgumentException($"{table} {id} não existe");
        write();
        return Edit(table, columns, id, before);
    });

    ResourceEdit Remove(string table, string[] columns, long id) =>
        Change(table, columns, id, () => _db.Run($"delete from {table} where id = @0", id));
}
