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
