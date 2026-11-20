using System;
using System.Globalization;
using System.Linq;
using System.Text;
using Godot;
using Godot.Collections;

namespace Evron;

/// Designer de tipos (etapa E2 da especificação): tipos de entidade, limites de campo e tipos de vínculo criados pelo usuário, como
/// dados. O tipo de uma entidade deixa de ser uma lista fixa no esquema e passa a ser uma linha de entity_type.
public partial class Registry
{
    // O CHECK fixo de entity.kind e de field_domain.kind vira uma referência a entity_type (reescrita no esquema: os dados já valem,
    // porque a tabela nasce com todos os tipos que o CHECK aceitava).
    const string EntityTypesMigration = """
        create table entity_type(
            code text primary key,
            label text not null,
            builtin integer not null default 0,
            created_at integer not null default (unixepoch()));
        insert into entity_type(code, label, builtin) values
            ('cultura', 'Cultura', 1), ('pais', 'País', 1), ('raca', 'Raça', 1), ('etnia', 'Etnia', 1), ('idioma', 'Idioma', 1),
            ('religiao', 'Religião', 1), ('provincia', 'Província', 1), ('municipio', 'Município', 1);
        PRAGMA writable_schema = ON;
        update sqlite_master set sql = replace(sql,
            'check (kind in (''cultura'',''pais'',''raca'',''etnia'',''idioma'',''religiao'',''provincia'',''municipio''))',
            'references entity_type(code)') where type = 'table' and name = 'entity';
        update sqlite_master set sql = replace(sql,
            'check (kind in (''cultura'',''pais'',''raca'',''etnia'',''idioma'',''religiao''))',
            'references entity_type(code)') where type = 'table' and name = 'field_domain';
        PRAGMA writable_schema = RESET;
        alter table field_def add column min_value real;
        alter table field_def add column max_value real;
        """;

    // As camadas do mapa de presenças como dados: cada tipo de entidade aparece em uma camada (ou em nenhuma). As 6 de fábrica com as
    // cores de antes; o usuário cria outras e escolhe quais tipos vão para elas.
    const string MapLayersMigration = """
        create table map_layer(
            code text primary key,
            label text not null,
            rgb integer not null,
            builtin integer not null default 0);
        insert into map_layer(code, label, rgb, builtin) values
            ('politica', 'Fronteira política', 15889229, 1), ('cultural', 'Presença cultural', 15912013, 1),
            ('etnica', 'Distribuição étnica', 7592320, 1), ('linguistica', 'Área linguística', 6737138, 1),
            ('religiosa', 'Presença religiosa', 12553458, 1), ('racial', 'Habitat de raça', 15892671, 1);
        alter table entity_type add column layer text references map_layer(code);
        update entity_type set layer = case code
            when 'pais' then 'politica' when 'provincia' then 'politica' when 'municipio' then 'politica' when 'cultura' then 'cultural'
            when 'etnia' then 'etnica' when 'idioma' then 'linguistica' when 'religiao' then 'religiosa' when 'raca' then 'racial' end;
        """;

    /// As camadas do mapa de presenças, as de fábrica primeiro: {code, label, rgb, builtin, kinds (os tipos que ela mostra)}.
    public Array<Dictionary> MapLayers()
    {
        var kinds = _db.Rows("select layer, code from entity_type where layer is not null order by rowid")
            .GroupBy(r => Str(r[0])).ToDictionary(g => g.Key, g => g.Select(r => Str(r[1])).ToArray());
        return new(_db.Rows("select code, label, rgb, builtin from map_layer order by builtin desc, rowid")
            .Select(r => new Dictionary { ["code"] = Str(r[0]), ["label"] = Str(r[1]), ["rgb"] = Convert.ToInt64(r[2]),
                                          ["builtin"] = Convert.ToInt64(r[3]) == 1,
                                          ["kinds"] = kinds.TryGetValue(Str(r[0]), out var k) ? k : System.Array.Empty<string>() }));
    }

    /// Cria uma camada do mapa de presenças (cor RGB de 24 bits) e passa para ela os tipos dados (cada tipo fica numa camada só).
    /// Devolve o código.
    public string CreateMapLayer(string label, long rgb, string[] kinds)
    {
        label = Clean(label);
        if (rgb < 0 || rgb > 0xFFFFFF) throw new ArgumentException($"cor fora de 0..16777215: {rgb}");
        if (kinds.Any(k => !TypeExists(k))) throw new ArgumentException("tipo de entidade inexistente");
        if (_db.Scalar("select 1 from map_layer where label = @0 collate nocase", label) != null)
            throw new ArgumentException($"já existe uma camada chamada {label}");
        return _db.Tx(() =>
        {
            string code = UniqueCode(Slug(label, "camada"), c => _db.Scalar("select 1 from map_layer where code = @0", c) != null);
            _db.Run("insert into map_layer(code, label, rgb) values (@0, @1, @2)", code, label, rgb);
            foreach (var k in kinds.Distinct()) _db.Run("update entity_type set layer = @0 where code = @1", code, k);
            _layerOf = null;
            return code;
        });
    }

    /// Os tipos de entidade: os de fábrica primeiro, depois os criados, na ordem de criação. {code, label, builtin}.
    public Array<Dictionary> EntityTypes() => new(
        _db.Rows("select code, label, builtin from entity_type order by builtin desc, rowid")
           .Select(r => new Dictionary { ["code"] = Str(r[0]), ["label"] = Str(r[1]), ["builtin"] = Convert.ToInt64(r[2]) == 1 }));

    bool TypeExists(string code) => _db.Scalar("select 1 from entity_type where code = @0", code) != null;

    /// Cria um tipo de entidade com esse nome. Devolve o código gerado (do nome, sem acentos; único).
    public string CreateEntityType(string label)
    {
        label = Clean(label);
        if (_db.Scalar("select 1 from entity_type where label = @0 collate nocase", label) != null)
            throw new ArgumentException($"já existe um tipo chamado {label}");
        string code = UniqueCode(Slug(label, "tipo"), TypeExists);
        _db.Run("insert into entity_type(code, label) values (@0, @1)", code, label);
        return code;
    }

    /// Cria um tipo de vínculo. srcKind/dstKind: o tipo de entidade de cada ponta ("" = qualquer). outLabel é o que a ficha da origem
    /// escreve; inLabel, o que a ficha do destino escreve. Devolve o código.
    public string CreateRelationType(string outLabel, string inLabel, string srcKind, string dstKind)
    {
        outLabel = Clean(outLabel);
        inLabel = Clean(inLabel);
        foreach (var k in new[] { srcKind, dstKind })
            if (k != "" && !TypeExists(k)) throw new ArgumentException($"tipo de entidade inexistente: {k}");
        string code = UniqueCode(Slug(outLabel, "vinculo"), c => _db.Scalar("select 1 from relation_type where code = @0", c) != null);
        _db.Run("insert into relation_type(code, out_label, in_label, src_kind, dst_kind) values (@0, @1, @2, @3, @4)",
            code, outLabel, inLabel, srcKind == "" ? null : srcKind, dstKind == "" ? null : dstKind);
        return code;
    }

    /// Validação de um campo numérico personalizado: valor mínimo e máximo (NaN = sem limite).
    public void SetFieldLimits(string code, double min, double max)
    {
        var r = _db.Rows("select type, is_custom from field_def where code = @0", code);
        if (r.Count == 0) throw new ArgumentException($"campo inexistente: {code}");
        if (Str(r[0][0]) != "number" || Convert.ToInt64(r[0][1]) != 1) throw new ArgumentException("só campos numéricos personalizados têm limites");
        if (!double.IsNaN(min) && !double.IsNaN(max) && min > max) throw new ArgumentException("o mínimo é maior que o máximo");
        _db.Run("update field_def set min_value = @0, max_value = @1 where code = @2",
            double.IsNaN(min) ? null : min, double.IsNaN(max) ? null : max, code);
    }

    /// O código a partir do nome: minúsculas, sem acentos, só letras, dígitos e "_".
    static string Slug(string text, string fallback)
    {
        var sb = new StringBuilder();
        foreach (char c in text.Normalize(NormalizationForm.FormD))
        {
            if (CharUnicodeInfo.GetUnicodeCategory(c) == UnicodeCategory.NonSpacingMark) continue;
            char l = char.ToLowerInvariant(c);
            if (l is >= 'a' and <= 'z' or >= '0' and <= '9') sb.Append(l);
            else if (sb.Length > 0 && sb[^1] != '_') sb.Append('_');
        }
        string s = sb.ToString().Trim('_');
        return s == "" ? fallback : s.Length > 40 ? s[..40] : s;
    }

    static string UniqueCode(string baseCode, Func<string, bool> taken)
    {
        string code = baseCode;
        for (int i = 2; taken(code); i++) code = $"{baseCode}_{i}";
        return code;
    }
}
