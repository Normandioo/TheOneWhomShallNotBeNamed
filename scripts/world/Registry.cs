using System;
using System.Linq;
using Godot;
using Godot.Collections;

namespace Evron;

/// Os cadastros do mundo (etapa 1 do plano de domínios): seis tipos de entidade com ID estável, nomes com papel e validade,
/// e vínculos tipados, dirigidos e datados. Sem tela e sem nó: quem mostra e quem edita só chama estes métodos.
/// Tempo = segundos int64 do relógio universal; a validade é [início, fim): long.MinValue/MaxValue = sem limite.
/// Nada além do nome é obrigatório. Erros de uso (tipo inválido, nome vazio, vínculo fora do tipo) lançam exceção.
public partial class Registry : RefCounted
{
    public const long Forever = long.MaxValue;
    public const long Always = long.MinValue;

    static readonly string[] Migrations =
    {
        """
        create table world(id integer primary key, name text not null);
        insert into world(id, name) values (1, 'Evron');

        create table entity(
            id integer primary key,
            world_id integer not null references world(id),
            kind text not null check (kind in ('cultura','pais','raca','etnia','idioma','religiao')),
            summary text,
            created_at integer not null default (unixepoch()));  -- data REAL de criação, não a do mundo

        -- Um nome com papel e validade. 'principal' é o nome de exibição (um por vez); os demais papéis mantêm
        -- gentílico, etnônimo, exônimo etc. distintos mesmo com o mesmo texto. Novo papel = nova migração.
        create table entity_name(
            id integer primary key,
            entity_id integer not null references entity(id),
            name text not null,
            role text not null check (role in ('principal','alternativo','historico','autodenominacao','exonimo',
                'oficial','popular','gentilico','etnonimo','denominacao_coletiva')),
            lang_id integer references entity(id),
            valid_from integer not null,
            valid_to integer not null,
            check (valid_from < valid_to));
        create index entity_name_entity on entity_name(entity_id, role);
        create index entity_name_text on entity_name(name collate nocase);

        -- Tipos de vínculo como dados: src_kind/dst_kind NULL = qualquer tipo de entidade. out_label é o que a ficha da
        -- origem escreve ao listar os destinos; in_label, o que a ficha do destino escreve ao listar as origens.
        create table relation_type(
            code text primary key,
            out_label text not null,
            in_label text not null,
            src_kind text,
            dst_kind text);
        insert into relation_type values
            ('idioma_oficial',       'Idioma oficial',           'Idioma oficial de',        'pais',   'idioma'),
            ('idioma_ancestral',     'Idioma ancestral de',      'Idioma ancestral',         'idioma', 'idioma'),
            ('religiao_reconhecida', 'Religião reconhecida',     'Reconhecida por',          'pais',   'religiao'),
            ('cultura_presente',     'Cultura presente',         'Cultura presente em',      null,     'cultura'),
            ('etnia_presente',       'Etnia presente',           'Etnia presente em',        null,     'etnia'),
            ('raca_presente',        'Raça presente',            'Raça presente em',         null,     'raca'),
            ('idioma_falado',        'Idioma falado',            'Idioma falado em',         null,     'idioma'),
            ('religiao_presente',    'Religião presente',        'Religião presente em',     null,     'religiao');

        create table relation(
            id integer primary key,
            type text not null references relation_type(code),
            src integer not null references entity(id),
            dst integer not null references entity(id),
            valid_from integer not null,
            valid_to integer not null,
            note text,
            check (valid_from < valid_to),
            check (src <> dst));
        create index relation_src on relation(src, type);
        create index relation_dst on relation(dst, type);
        """,
        FieldsMigration,  // RegistrySheet.cs
        CalendarsMigration,  // RegistryCalendar.cs
        PlacesMigration,  // RegistryPlaces.cs
        BordersMigration,  // RegistryPlaces.cs
        TerritoryMigration,  // RegistryTerritory.cs
        TerritoryBoundaryMigration,  // RegistryTerritory.cs
        TerritoryLevelsMigration,  // RegistryTerritory.cs
        MunicipalityMigration,  // RegistryTerritory.cs
        TerritoryTilesMigration,  // RegistryTerritory.cs
        EntityTypesMigration,  // RegistryTypes.cs
        MapLayersMigration,  // RegistryTypes.cs
        RulesMigration,  // RegistryRules.cs
        CulturalLayersMigration,  // RegistryTerritory.cs
        TerrainTilesMigration,  // RegistryTerrain.cs
        PopulationMigration,  // RegistryPlaces.cs
        ResourcesMigration,  // RegistryResources.cs
        PaintedShapesMigration,  // RegistryResources.cs
        GenerationMigration,  // RegistryGeneration.cs
        ProductionMigration,  // RegistryProduction.cs
        DetailsMigration,  // RegistryDetails.cs
        DivisionNamesMigration,  // RegistryDivisions.cs
    };

    WorldDb _db = new();
    string _openKey = "";  // muda a cada Open: diz se os tiles gravados de uma camada são os deste banco

    public void Open(string path)
    {
        _db.Open(path);
        _openKey = Guid.NewGuid().ToString("N");
        _layerOf = null;
        try
        {
            long version = _db.SchemaVersion();
            // Antes de mudar o esquema de um mundo que já existe, uma cópia dele ao lado (a migração não tem volta).
            if (path != ":memory:" && version > 0 && version < Migrations.Length)
            {
                string copy = $"{path}.antes-v{version}";
                if (!System.IO.File.Exists(copy)) _db.Run("vacuum into @0", copy);
            }
            _db.Migrate(Migrations);
            CreateUndoTriggers();
        }
        catch { _db.Close(); throw; }  // um banco recusado não fica aberto: as chamadas seguintes falham em vez de escrever nele
    }

    /// Só para testes de migração: cria/abre o banco aplicando apenas as `version` primeiras migrações (um mundo de uma versão antiga).
    public void OpenAtVersion(string path, int version)
    {
        _db.Open(path);
        _openKey = Guid.NewGuid().ToString("N");
        try { _db.Migrate(Migrations[..Math.Clamp(version, 0, Migrations.Length)]); CreateUndoTriggers(); }
        catch { _db.Close(); throw; }
    }

    /// O banco está aberto (Open não foi recusado)?
    public bool IsOpen() => _db.IsOpen();

    public void Close() => _db.Close();

    // ---- entidades ----

    /// Cria o registro só com o nome (provisório que seja). O mundo é o único, por enquanto.
    public long Create(string kind, string name)
    {
        name = Clean(name);
        return _db.Tx(() =>
        {
            long id = _db.Insert("insert into entity(world_id, kind) values (1, @0)", kind);
            _db.Run("insert into entity_name(entity_id, name, role, valid_from, valid_to) values (@0, @1, 'principal', @2, @3)",
                id, name, Always, Forever);
            return id;
        });
    }

    public string Kind(long id) => _db.Scalar("select kind from entity where id = @0", id)?.ToString() ?? "";

    public long Count(string kind) => Convert.ToInt64(_db.Scalar("select count(*) from entity where kind = @0", kind));

    public void SetSummary(long id, string text) => _db.Run("update entity set summary = @0 where id = @1", text, id);

    public string Summary(long id) => _db.Scalar("select summary from entity where id = @0", id)?.ToString() ?? "";

    // ---- nomes ----

    /// Nome principal de hoje (o que não tem fim).
    public string Name(long id) =>
        _db.Scalar("select name from entity_name where entity_id = @0 and role = 'principal' and valid_to = @1", id, Forever)?.ToString() ?? "";

    /// Nome principal que valia no instante t; vazio se não havia.
    public string NameAt(long id, long t) =>
        _db.Scalar("select name from entity_name where entity_id = @0 and role = 'principal' and valid_from <= @1 and @1 < valid_to", id, t)?.ToString() ?? "";

    /// Correção de cadastro: troca o texto do nome atual, sem criar história (o povo não mudou de nome).
    public void Correct(long id, string name) =>
        _db.Run("update entity_name set name = @0 where entity_id = @1 and role = 'principal' and valid_to = @2", Clean(name), id, Forever);

    /// Mudança histórica: o nome atual vale até t e o novo vale de t em diante.
    public void RenameAt(long id, string name, long t)
    {
        name = Clean(name);
        _db.Tx(() =>
        {
            var cur = _db.Rows("select id, valid_from from entity_name where entity_id = @0 and role = 'principal' and valid_to = @1", id, Forever);
            if (cur.Count == 0 || Convert.ToInt64(cur[0][1]) >= t) throw new ArgumentException($"renomear {id} em {t}: o nome atual começa depois disso");
            _db.Run("update entity_name set valid_to = @0 where id = @1", t, cur[0][0]);
            _db.Run("insert into entity_name(entity_id, name, role, valid_from, valid_to) values (@0, @1, 'principal', @2, @3)", id, name, t, Forever);
            return 0;
        });
    }

    /// Outro nome (alternativo, gentílico, exônimo...) sem limite de tempo. langId 0 = idioma não informado.
    public long AddName(long id, string name, string role, long langId) => AddNameDuring(id, name, role, langId, Always, Forever);

    public long AddNameDuring(long id, string name, string role, long langId, long from, long to)
    {
        if (langId != 0 && Kind(langId) != "idioma") throw new ArgumentException($"{langId} não é um idioma");
        return _db.Insert("insert into entity_name(entity_id, name, role, lang_id, valid_from, valid_to) values (@0, @1, @2, @3, @4, @5)",
            id, Clean(name), role, langId == 0 ? null : langId, from, to);
    }

    /// Todos os nomes da entidade com esse papel, em qualquer época.
    public string[] NamesWithRole(long id, string role) =>
        _db.Rows("select name from entity_name where entity_id = @0 and role = @1 order by valid_from", id, role).Select(r => (string)r[0]!).ToArray();

    /// Entidades que têm esse nome (qualquer papel, qualquer época), sem diferenciar maiúsculas.
    public Array<long> Find(string text) =>
        new(_db.Rows("select distinct entity_id from entity_name where name = @0 collate nocase order by entity_id", text).Select(r => Convert.ToInt64(r[0])));

    // ---- vínculos ----

    public long Link(long src, long dst, string type) => LinkDuring(src, dst, type, Always, Forever);

    /// Vínculo src --type--> dst válido em [from, to). Recusa tipo desconhecido, tipos de entidade fora do que o vínculo
    /// aceita e repetição sobreposta do mesmo vínculo (a mesma entidade é reutilizada, não duplicada).
    public long LinkDuring(long src, long dst, string type, long from, long to)
    {
        var t = _db.Rows("select src_kind, dst_kind from relation_type where code = @0", type);
        if (t.Count == 0) throw new ArgumentException($"tipo de vínculo desconhecido: {type}");
        if (t[0][0] is string sk && sk != Kind(src)) throw new ArgumentException($"{type} exige origem '{sk}', mas {src} é '{Kind(src)}'");
        // "Município de" aceita a província ou, direto, o país (a província é opcional).
        if (t[0][1] is string dk && dk != Kind(dst) && !(type == "municipio_de" && Kind(dst) == "pais")) throw new ArgumentException($"{type} exige destino '{dk}', mas {dst} é '{Kind(dst)}'");
        long dup = Convert.ToInt64(_db.Scalar(
            "select count(*) from relation where type = @0 and src = @1 and dst = @2 and valid_from < @4 and @3 < valid_to", type, src, dst, from, to));
        if (dup > 0) throw new ArgumentException($"vínculo {type} {src}->{dst} já existe nesse período");
        return _db.Insert("insert into relation(type, src, dst, valid_from, valid_to) values (@0, @1, @2, @3, @4)", type, src, dst, from, to);
    }

    /// Encerra um vínculo sem fim em t (o fim é excluído: em t ele já não vale).
    public void EndLink(long linkId, long t)
    {
        int n = _db.Run("update relation set valid_to = @0 where id = @1 and valid_to = @2 and valid_from < @0", t, linkId, Forever);
        if (n == 0) throw new ArgumentException($"vínculo {linkId} não está em aberto antes de {t}");
    }

    /// Entidades ligadas a id por esse tipo de vínculo no instante t. incoming = true lê no sentido contrário (quem aponta para id).
    public Array<long> Linked(long id, string type, long t, bool incoming)
    {
        string me = incoming ? "dst" : "src", other = incoming ? "src" : "dst";
        return new(_db.Rows($"select {other} from relation where type = @0 and {me} = @1 and valid_from <= @2 and @2 < valid_to order by {other}", type, id, t)
            .Select(r => Convert.ToInt64(r[0])));
    }

    static string Clean(string name)
    {
        name = name.Trim();
        if (name.Length == 0) throw new ArgumentException("o nome não pode ser vazio");
        return name;
    }
}
