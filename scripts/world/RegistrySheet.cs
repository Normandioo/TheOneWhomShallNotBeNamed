using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using Godot;
using Godot.Collections;
using GArray = Godot.Collections.Array;

namespace Evron;

/// A ficha dos cadastros (etapa 4 do plano de domínios): campos definidos como DADOS (as seções da ficha são geradas a partir
/// deles, e o campo personalizado é o mesmo mecanismo), valores com os estados do plano, etiquetas, busca, duplicar, excluir e
/// a criação de uma "sociedade" (país + cultura + etnia ligados). Continua sem tela: a ficha sai como um Dictionary pronto.
public partial class Registry
{
    // Um campo de texto por tópico do plano (seções 4 a 9). Os tópicos que dependem de módulos ainda inexistentes (lugares,
    // demografia, calendários) começam como nota de texto e ganham estrutura nas etapas 3, 5 e 6. O código é "tipo.tópico"; o
    // domínio de cada campo semeado sai do prefixo.
    const string FieldsMigration = """
        create table field_def(
            id integer primary key,
            code text not null unique,
            label text not null,
            hint text,
            type text not null default 'text' check (type in ('text','number','choice','bool')),
            unit text,
            options text,                       -- type 'choice': uma opção por linha
            is_custom integer not null default 0);

        create table field_domain(
            field_id integer not null references field_def(id),
            kind text not null check (kind in ('cultura','pais','raca','etnia','idioma','religiao')),
            primary key (field_id, kind));

        -- Sem linha = "não preenchido". unknown = "desconhecido"; na = "não se aplica"; known com num = 0 é "zero".
        create table field_value(
            entity_id integer not null references entity(id),
            field_id integer not null references field_def(id),
            state text not null check (state in ('known','unknown','na')),
            num real,
            text text,
            primary key (entity_id, field_id));

        create table entity_tag(
            entity_id integer not null references entity(id),
            tag text not null,
            primary key (entity_id, tag));
        create index entity_tag_tag on entity_tag(tag);

        insert into field_def(code, label, hint) values
        ('cultura.identidade',   'Identidade cultural',      'Denominação coletiva e características reconhecidas pela comunidade e por terceiros.'),
        ('cultura.formacao',     'Formação e variantes',     'Origens, culturas de influência e derivadas, variantes regionais, contatos e intercâmbios.'),
        ('cultura.presenca',     'Presença',                 'Regiões de origem, distribuição atual, centros culturais, diásporas e períodos.'),
        ('cultura.valores',      'Valores e convivência',    'Ideais, deveres, virtudes, tabus, etiqueta, hospitalidade, tratamento de estrangeiros e diferenças internas.'),
        ('cultura.familia',      'Família e vida social',    'Parentesco, casamento, herança costumeira, criação de crianças, ritos de passagem e organização comunitária.'),
        ('cultura.material',     'Vida material',            'Vestimentas, arquitetura, alimentação, utensílios, artesanato e relação com recursos e ambiente.'),
        ('cultura.artes',        'Artes e conhecimento',     'Música, dança, literatura, jogos, educação, transmissão oral, técnicas e práticas de cura.'),
        ('cultura.linguagem',    'Linguagem e nomes',        'Idiomas usados, escritas, padrões de nomes, títulos, formas de tratamento e empréstimos.'),
        ('cultura.crencas',      'Crenças e magia',          'Religiões presentes, superstições, tradições mágicas, acesso ao ensino e atitudes diante do sobrenatural.'),
        ('cultura.tempo',        'Tempo cultural',           'Calendários usados, contagem de idade, estações reconhecidas, dias de descanso, festas e ciclos de trabalho.'),

        ('pais.identidade',      'Identidade política',      'Nome oficial, abreviações, gentílicos, símbolos, lema e situação de existência.'),
        ('pais.governo',         'Governo',                  'Forma de governo, fundamento da autoridade, governantes, cargos, sucessão, instituições e centros de decisão.'),
        ('pais.territorio',      'Território',               'Áreas administradas, soberania reconhecida, ocupação efetiva, reivindicações, divisões internas e dependências.'),
        ('pais.assentamentos',   'Assentamentos',            'Capital ou capitais, sedes temporárias, cidades importantes, portos, fortalezas e infraestrutura.'),
        ('pais.populacao',       'População',                'Estimativas por data e área, grupos presentes, migrações, cidadania, acesso a direitos e minorias.'),
        ('pais.direito',         'Direito e sociedade',      'Leis, aplicação da justiça, jurisdições, classes, castas, mobilidade e autonomia comunitária.'),
        ('pais.economia',        'Economia',                 'Atividades, recursos explorados, mercadorias, moedas, tributos, comércio, importações e exportações.'),
        ('pais.conhecimento',    'Conhecimento e magia',     'Técnicas disponíveis, educação, instituições de pesquisa, escolas mágicas, regras e restrições de acesso.'),
        ('pais.relacoes',        'Relações externas',        'Tratados, alianças, guerras, vassalagem, reconhecimento, fronteiras abertas e relações comerciais.'),
        ('pais.tempo',           'Tempo oficial',            'Calendário civil e administrativo, eras e reinados usados na datação, adoções e reformas.'),
        ('pais.cultura_publica', 'Cultura pública',          'Idiomas oficiais ou administrativos, religiões reconhecidas, festas oficiais e políticas sobre os grupos presentes.'),

        ('raca.identificacao',   'Identificação e classificação', 'Nomes próprios e externos, classificação autoral, ancestralidades relacionadas e subgrupos.'),
        ('raca.morfologia',      'Morfologia',               'Aparência e variações, porte, características corporais, sentidos, locomoção e adaptações ambientais.'),
        ('raca.ciclo',           'Ciclo de vida',            'Maturidade, longevidade estimada, fases da vida e particularidades de desenvolvimento.'),
        ('raca.fisiologia',      'Fisiologia',               'Alimentação, sono, respiração, tolerâncias, necessidades ambientais e condições próprias do cenário.'),
        ('raca.reproducao',      'Reprodução e parentesco biológico', 'Modos de reprodução e compatibilidades, somente se definidos; híbridos e descendência não são presumidos.'),
        ('raca.origem',          'Origem e transformações',  'Origens confirmadas, mitos de criação, ancestralidades, transformações e eventos relevantes.'),
        ('raca.mana',            'Mana e capacidades',       'Relação confirmada com mana, aptidões e limitações, variabilidade individual, condições e exceções.'),
        ('raca.distribuicao',    'Distribuição',             'Habitats, áreas de presença histórica e atual, estimativas demográficas e migrações.'),
        ('raca.sociais',         'Relações sociais',         'Etnia, cultura, idioma e religião por vínculos de presença; estatuto jurídico, discriminação ou privilégio.'),

        ('etnia.identificacao',  'Identificação',            'Autodenominação, exônimos, formas históricas, pronúncia e significado dos nomes.'),
        ('etnia.pertencimento',  'Pertencimento',            'Critérios reconhecidos pela comunidade, transmissão de identidade, adoção, integração e identidades sobrepostas.'),
        ('etnia.origem',         'Origem e memória',         'Formação histórica, narrativas de origem, ancestrais reconhecidos, acontecimentos e personagens relevantes.'),
        ('etnia.organizacao',    'Organização interna',      'Subgrupos, clãs, comunidades, lideranças, redes familiares, conselhos e autoridades tradicionais.'),
        ('etnia.racas',          'Raças e ancestralidades',  'Raças presentes, ancestralidades reivindicadas ou confirmadas e variação interna.'),
        ('etnia.praticas',       'Práticas e crenças',       'Culturas, idiomas, religiões, vestimentas e símbolos associados, com espaço para diversidade.'),
        ('etnia.presenca',       'Presença e diáspora',      'Regiões de origem, áreas atuais, comunidades no exterior, deslocamentos e vínculos com lugares.'),
        ('etnia.demografia',     'Demografia',               'População estimada, área e data da estimativa, fonte, crescimento observado e situação das comunidades.'),
        ('etnia.politica',       'Situação política',        'Países onde vive, cidadania, autonomias, reconhecimento, direitos e relações com outras comunidades.'),
        ('etnia.tempo',          'Tempo e identidade',       'Calendários usados, festas identitárias, marcos de origem e formas tradicionais de contar gerações e anos.'),

        ('idioma.identificacao', 'Identificação',            'Nome próprio da língua, nomes externos, abreviação interna e pronúncia.'),
        ('idioma.classificacao', 'Classificação',            'Família, ancestral, descendentes, idiomas relacionados e classificação proposta ou confirmada.'),
        ('idioma.variantes',     'Variantes',                'Dialetos, variedades regionais, registros sociais e formas históricas; língua ou dialeto pode ser disputado.'),
        ('idioma.falantes',      'Falantes e distribuição',  'Falantes nativos e adicionais quando conhecidos, regiões, comunidades, diásporas e estimativas datadas.'),
        ('idioma.estatuto',      'Estatuto e usos',          'Uso oficial, administrativo, litúrgico, comercial, escolar, cotidiano ou secreto, por comunidade, país e período.'),
        ('idioma.escrita',       'Escrita',                  'Sistemas usados, direção, variantes, ortografias, transliteração, fontes e amostras de texto.'),
        ('idioma.gramatica',     'Sons e gramática',         'Inventário sonoro opcional, pronúncia, estrutura silábica, ordem de palavras, flexões e notas gramaticais.'),
        ('idioma.lexico',        'Léxico e nomes',           'Vocabulário, glossários, formação de nomes próprios, títulos, topônimos e numerais.'),
        ('idioma.historia',      'História e contato',       'Mudanças, empréstimos, línguas de contato, reformas ortográficas e políticas de ensino ou proibição.'),
        ('idioma.situacao',      'Situação de uso',          'Uso amplo ou restrito, transmissão, revitalização, uso histórico ou litúrgico.'),
        ('idioma.temporal',      'Vocabulário temporal',     'Tradução de meses, dias, eras, festas, números e formatos de data dos calendários relacionados.'),

        ('religiao.identificacao','Identificação',           'Autodenominação, nomes externos, denominação dos adeptos e símbolos.'),
        ('religiao.crencas',     'Crenças',                  'Doutrina, cosmologia, criação, morte, pós-vida, ética, tabus e relação com o sobrenatural.'),
        ('religiao.divindades',  'Divindades e conceitos',   'Figuras, forças ou conceitos cultuados; papéis, narrativas e interpretações. Pode não haver divindades.'),
        ('religiao.organizacao', 'Organização',              'Correntes, denominações, escolas, cargos, sucessão, ordens, instituições, ou ausência de autoridade central.'),
        ('religiao.textos',      'Textos e transmissão',     'Escrituras, tradição oral, idiomas litúrgicos, autores, interpretações e formas de ensino.'),
        ('religiao.praticas',    'Práticas',                 'Culto, oração, peregrinação, iniciação, casamento, funerais, oferendas e prescrições alimentares ou de vestimenta.'),
        ('religiao.lugares',     'Lugares e objetos',        'Templos, sedes, locais sagrados, relíquias, trajetos de peregrinação e patrimônio.'),
        ('religiao.tempo',       'Tempo religioso',          'Calendários litúrgicos, ciclos, jejuns, festas, dias sagrados, eras e regras de recorrência.'),
        ('religiao.historia',    'História e presença',      'Formação, reformas, cismas, difusão, estimativa de adeptos e distribuição por período.'),
        ('religiao.publica',     'Vida pública',             'Reconhecimento, privilégios, perseguições, relação com governos e presença na educação, justiça e economia.'),
        ('religiao.magia',       'Magia',                    'Interpretação da mana, práticas admitidas ou proibidas, iniciação e relação com escolas mágicas.');

        insert into field_domain(field_id, kind) select id, substr(code, 1, instr(code, '.') - 1) from field_def;
        """;

    static readonly CompareOptions Loose = CompareOptions.IgnoreCase | CompareOptions.IgnoreNonSpace;

    // ---- campos ----

    /// Definições dos campos que se aplicam a esse tipo, na ordem do cadastro (os personalizados vêm depois).
    public Array<Dictionary> FieldsFor(string kind) => new(
        _db.Rows("select d.code, d.label, d.hint, d.type, d.unit, d.options, d.is_custom, d.min_value, d.max_value from field_def d " +
                 "join field_domain f on f.field_id = d.id where f.kind = @0 order by d.is_custom, d.id", kind)
           .Select(r => new Dictionary { ["code"] = Str(r[0]), ["label"] = Str(r[1]), ["hint"] = LimitHint(Str(r[2]), r[7], r[8]), ["type"] = Str(r[3]),
                                         ["unit"] = Str(r[4]), ["options"] = Str(r[5]), ["custom"] = Convert.ToInt64(r[6]) == 1 }));

    static string LimitHint(string hint, object? min, object? max)
    {
        if (min == null && max == null) return hint;
        string range = min != null && max != null ? $"De {Convert.ToDouble(min)} a {Convert.ToDouble(max)}."
            : min != null ? $"No mínimo {Convert.ToDouble(min)}." : $"No máximo {Convert.ToDouble(max)}.";
        return hint == "" ? range : hint + " " + range;
    }

    /// Campo personalizado do autor. type: text | number | choice | bool; options = uma opção por linha (só em choice).
    /// Aplica-se aos tipos de entidade dados (ao menos um). Devolve o código gerado ("custom.N").
    public string AddField(string label, string type, string unit, string options, string[] kinds)
    {
        label = Clean(label);
        if (kinds.Length == 0 || kinds.Any(k => !TypeExists(k))) throw new ArgumentException("o campo precisa de ao menos um tipo de entidade válido");
        if (type == "choice" && options.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).Length < 2)
            throw new ArgumentException("um campo de escolha precisa de ao menos 2 opções");
        return _db.Tx(() =>
        {
            long id = _db.Insert("insert into field_def(code, label, type, unit, options, is_custom) values ('pending', @0, @1, @2, @3, 1)",
                label, type, unit == "" ? null : unit, type == "choice" ? options : null);
            string code = $"custom.{id}";
            _db.Run("update field_def set code = @0 where id = @1", code, id);
            foreach (var k in kinds.Distinct()) _db.Run("insert into field_domain(field_id, kind) values (@0, @1)", id, k);
            return code;
        });
    }

    /// Grava um valor. state: "known" (usa value), "unknown" ou "na". known com texto vazio apaga (volta a "não preenchido").
    /// Número: aceita vírgula decimal; 0 é um valor conhecido. Bool: "true"/"1" ou "false"/"0". Choice: precisa estar nas opções.
    public void SetField(long id, string code, string state, string value)
    {
        if (state != "known" && state != "unknown" && state != "na") throw new ArgumentException($"estado inválido: {state}");
        var d = _db.Rows("select d.id, d.type, d.options, d.min_value, d.max_value from field_def d join field_domain f on f.field_id = d.id join entity e on e.kind = f.kind " +
                         "where d.code = @0 and e.id = @1", code, id);
        if (d.Count == 0) throw new ArgumentException($"o campo {code} não existe ou não se aplica à entidade {id}");
        long fid = Convert.ToInt64(d[0][0]);
        string type = Str(d[0][1]);
        if (state != "known")
        {
            Upsert(id, fid, state, null, null);
            return;
        }
        value = value.Trim();
        if (value.Length == 0) { _db.Run("delete from field_value where entity_id = @0 and field_id = @1", id, fid); return; }
        switch (type)
        {
            case "number":
                if (!double.TryParse(value.Replace(',', '.'), NumberStyles.Float, CultureInfo.InvariantCulture, out double n) || !double.IsFinite(n))
                    throw new ArgumentException($"'{value}' não é um número");
                if (d[0][3] != null && n < Convert.ToDouble(d[0][3])) throw new ArgumentException($"{value} está abaixo do mínimo ({Convert.ToDouble(d[0][3])})");
                if (d[0][4] != null && n > Convert.ToDouble(d[0][4])) throw new ArgumentException($"{value} está acima do máximo ({Convert.ToDouble(d[0][4])})");
                Upsert(id, fid, "known", n, null);
                break;
            case "bool":
                Upsert(id, fid, "known", value is "true" or "1" ? 1 : value is "false" or "0" ? 0 : throw new ArgumentException($"'{value}' não é sim/não"), null);
                break;
            case "choice":
                if (!Str(d[0][2]).Split('\n', StringSplitOptions.TrimEntries).Contains(value)) throw new ArgumentException($"'{value}' não é uma das opções");
                Upsert(id, fid, "known", null, value);
                break;
            default:
                Upsert(id, fid, "known", null, value);
                break;
        }
    }

    /// Estado e valor gravados de um campo ("unfilled" e "" se não há), no mesmo formato da ficha: para a interface mostrar o que ficou de verdade.
    public Dictionary GetField(long id, string code)
    {
        var v = _db.Rows("select d.type, v.state, v.num, v.text from field_value v join field_def d on d.id = v.field_id where v.entity_id = @0 and d.code = @1", id, code);
        if (v.Count == 0) return new Dictionary { ["state"] = "unfilled", ["value"] = "" };
        return new Dictionary { ["state"] = Str(v[0][1]), ["value"] = Str(v[0][1]) == "known" ? FieldText(Str(v[0][0]), v[0][2], v[0][3]) : "" };
    }

    static string FieldText(string type, object? num, object? text) =>
        type == "number" ? Convert.ToDouble(num).ToString(CultureInfo.InvariantCulture)
        : type == "bool" ? (Convert.ToDouble(num) == 1 ? "true" : "false")
        : Str(text);

    void Upsert(long entity, long field, string state, double? num, string? text) =>
        _db.Run("insert into field_value(entity_id, field_id, state, num, text) values (@0, @1, @2, @3, @4) " +
                "on conflict(entity_id, field_id) do update set state = @2, num = @3, text = @4", entity, field, state, num, text);

    // ---- etiquetas ----

    public void AddTag(long id, string tag) => _db.Run("insert or ignore into entity_tag(entity_id, tag) values (@0, @1)", id, Clean(tag));

    public void RemoveTag(long id, string tag) => _db.Run("delete from entity_tag where entity_id = @0 and tag = @1", id, tag);

    public string[] Tags(long id) => _db.Rows("select tag from entity_tag where entity_id = @0 order by tag", id).Select(r => Str(r[0])).ToArray();

    // ---- busca ----

    /// Entidades cujo nome (de qualquer papel e época) contém o texto, sem diferenciar maiúsculas nem acentos. Filtros opcionais:
    /// kind ("" = todos), tag ("" = qualquer) e relatedTo (0 = qualquer; senão só quem tem vínculo com essa entidade no instante t).
    /// Texto vazio lista tudo (até 200). Cada resultado: id, kind, name (principal em t), match (o nome que casou, se não for o principal).
    public Array<Dictionary> Search(string text, string kind, string tag, long relatedTo, long t)
    {
        HashSet<long>? allowed = null;
        if (tag != "") allowed = _db.Rows("select entity_id from entity_tag where tag = @0", tag).Select(r => Convert.ToInt64(r[0])).ToHashSet();
        if (relatedTo != 0)
        {
            var rel = _db.Rows("select dst from relation where src = @0 and valid_from <= @1 and @1 < valid_to " +
                               "union select src from relation where dst = @0 and valid_from <= @1 and @1 < valid_to", relatedTo, t)
                         .Select(r => Convert.ToInt64(r[0])).ToHashSet();
            allowed = allowed == null ? rel : allowed.Intersect(rel).ToHashSet();
        }
        var hits = new System.Collections.Generic.Dictionary<long, (string Kind, string? Display, string? Match)>();
        foreach (var r in _db.Rows("select e.id, e.kind, n.name, n.role, n.valid_from, n.valid_to from entity e join entity_name n on n.entity_id = e.id " +
                                   "where (@0 = '' or e.kind = @0) order by e.id, n.valid_from", kind))
        {
            long id = Convert.ToInt64(r[0]);
            if (allowed != null && !allowed.Contains(id)) continue;
            string name = Str(r[2]);
            bool principalNow = Str(r[3]) == "principal" && Convert.ToInt64(r[4]) <= t && t < Convert.ToInt64(r[5]);
            hits.TryGetValue(id, out var h);
            h.Kind = Str(r[1]);
            if (principalNow) h.Display = name;
            if (Matches(name, text)) h.Match ??= name;
            hits[id] = h;
        }
        return new(hits.Where(p => p.Value.Match != null).OrderBy(p => p.Value.Display ?? p.Value.Match, StringComparer.CurrentCultureIgnoreCase).Take(200)
            .Select(p => new Dictionary { ["id"] = p.Key, ["kind"] = p.Value.Kind, ["name"] = p.Value.Display ?? p.Value.Match ?? "",
                                          ["match"] = p.Value.Match != null && p.Value.Match != p.Value.Display ? p.Value.Match : "" }));
    }

    // ---- ficha ----

    /// Tudo o que a ficha mostra, no instante t: names (todos, com papel e validade), tags, fields (definição + estado + valor)
    /// e links (vínculos válidos em t, nos dois sentidos, com o rótulo certo para cada lado).
    public Dictionary Sheet(long id, long t)
    {
        var e = _db.Rows("select kind, summary from entity where id = @0", id);
        if (e.Count == 0) throw new ArgumentException($"entidade {id} não existe");
        string kind = Str(e[0][0]);

        var names = new GArray();
        foreach (var r in _db.Rows("select n.id, n.name, n.role, n.valid_from, n.valid_to, l.name from entity_name n " +
                                   "left join entity_name l on l.entity_id = n.lang_id and l.role = 'principal' and l.valid_to = @1 " +
                                   "where n.entity_id = @0 order by n.role <> 'principal', n.valid_from, n.id", id, Forever))
            names.Add(new Dictionary { ["id"] = Convert.ToInt64(r[0]), ["name"] = Str(r[1]), ["role"] = Str(r[2]), ["from"] = Convert.ToInt64(r[3]),
                                       ["to"] = Convert.ToInt64(r[4]), ["lang"] = Str(r[5]) });

        var values = _db.Rows("select d.code, v.state, v.num, v.text from field_value v join field_def d on d.id = v.field_id where v.entity_id = @0", id)
                        .ToDictionary(r => Str(r[0]), r => r);
        var fields = new GArray();
        var computedNow = ComputedFields(id, t);
        foreach (var d in FieldsFor(kind))
        {
            string code = (string)d["code"], type = (string)d["type"];
            if (computedNow.ContainsKey(code)) d["computed"] = computedNow[code];
            d["state"] = "unfilled";
            d["value"] = "";
            if (values.TryGetValue(code, out var v))
            {
                d["state"] = Str(v[1]);
                if (Str(v[1]) == "known") d["value"] = FieldText(type, v[2], v[3]);
            }
            fields.Add(d);
        }

        const string nameAt = "(select name from entity_name where entity_id = {0} and role = 'principal' and valid_from <= @1 and @1 < valid_to)";
        var links = new GArray();
        foreach (var r in _db.Rows($"select r.id, r.type, r.src, r.dst, r.valid_from, r.valid_to, t.out_label, t.in_label, " +
                                   $"{string.Format(nameAt, "r.src")}, {string.Format(nameAt, "r.dst")}, es.kind, ed.kind " +
                                   "from relation r join relation_type t on t.code = r.type join entity es on es.id = r.src join entity ed on ed.id = r.dst " +
                                   "where (r.src = @0 or r.dst = @0) and r.valid_from <= @1 and @1 < r.valid_to order by t.out_label, r.id", id, t))
        {
            bool outgoing = Convert.ToInt64(r[2]) == id;
            links.Add(new Dictionary { ["id"] = Convert.ToInt64(r[0]), ["type"] = Str(r[1]), ["outgoing"] = outgoing,
                                       ["label"] = Str(outgoing ? r[6] : r[7]),
                                       ["other_id"] = Convert.ToInt64(outgoing ? r[3] : r[2]), ["other_name"] = Str(outgoing ? r[9] : r[8]),
                                       ["other_kind"] = Str(outgoing ? r[11] : r[10]), ["from"] = Convert.ToInt64(r[4]), ["to"] = Convert.ToInt64(r[5]) });
        }

        return new Dictionary { ["id"] = id, ["kind"] = kind, ["name"] = NameAt(id, t) is { Length: > 0 } n ? n : Name(id), ["summary"] = Str(e[0][1]),
                                ["names"] = names, ["tags"] = Tags(id), ["fields"] = fields, ["links"] = links,
                                ["calendars"] = CalendarsOf(id, t), ["presences"] = PresencesOf(id, t), ["estimates"] = EstimatesOf(id, t),
                                ["compositions"] = CompositionsOf(id, t) };
    }

    /// Tipos de vínculo que uma ficha desse tipo pode criar como origem: code, label e dst_kind ("" = qualquer).
    public Array<Dictionary> LinkTypesFor(string kind) => new(
        _db.Rows("select code, out_label, dst_kind from relation_type where src_kind is null or src_kind = @0 order by out_label", kind)
           .Select(r => new Dictionary { ["code"] = Str(r[0]), ["label"] = Str(r[1]), ["dst_kind"] = Str(r[2]) }));

    /// Remove um vínculo criado por engano (para encerrar um vínculo na história, use EndLink).
    public void DeleteLink(long linkId) => _db.Run("delete from relation where id = @0", linkId);

    // ---- duplicar, excluir, sociedade ----

    /// Nova identidade com o resumo, os valores e as etiquetas da original. Os nomes alternativos e históricos não vão: são da
    /// identidade antiga. copyLinks: reaproveita os vínculos que ainda estão em aberto (aponta para as mesmas entidades).
    public long Duplicate(long id, bool copyLinks, string newName)
    {
        var e = _db.Rows("select kind, summary from entity where id = @0", id);
        if (e.Count == 0) throw new ArgumentException($"entidade {id} não existe");
        if (newName.Trim() == "") newName = "Cópia de " + Name(id);
        return _db.Tx(() =>
        {
            long copy = Create(Str(e[0][0]), newName);
            _db.Run("update entity set summary = @0 where id = @1", e[0][1], copy);
            _db.Run("insert into field_value(entity_id, field_id, state, num, text) select @1, field_id, state, num, text from field_value where entity_id = @0", id, copy);
            _db.Run("insert into entity_tag(entity_id, tag) select @1, tag from entity_tag where entity_id = @0", id, copy);
            if (copyLinks)
            {
                _db.Run("insert into presence(entity_id, place_id, role, valid_from, valid_to, certainty, note) select @1, place_id, role, valid_from, valid_to, certainty, note from presence where entity_id = @0 and valid_to = @2", id, copy, Forever);
                _db.Run("insert into calendar_use(entity_id, calendar_id, purpose, valid_from, valid_to, priority) select @1, calendar_id, purpose, valid_from, valid_to, priority from calendar_use where entity_id = @0 and valid_to = @2", id, copy, Forever);
                _db.Run("insert into relation(type, src, dst, valid_from, valid_to, note) select type, @1, dst, valid_from, valid_to, note from relation where src = @0 and valid_to = @2", id, copy, Forever);
                _db.Run("insert into relation(type, src, dst, valid_from, valid_to, note) select type, src, @1, valid_from, valid_to, note from relation where dst = @0 and valid_to = @2", id, copy, Forever);
            }
            return copy;
        });
    }

    /// Quantos vínculos (de qualquer época) a exclusão levaria junto: para a interface avisar antes.
    public long AffectedLinks(long id) => Convert.ToInt64(_db.Scalar("select count(*) from relation where src = @0 or dst = @0", id));

    /// Exclusão por erro de criação (não é dissolução histórica): apaga a entidade, seus nomes, valores, etiquetas e vínculos.
    /// Devolve quantos vínculos foram apagados.
    public long Delete(long id)
    {
        long n = AffectedLinks(id);
        _db.Tx(() =>
        {
            _db.Run("delete from relation where src = @0 or dst = @0", id);
            _db.Run("delete from calendar_use where entity_id = @0", id);
            _db.Run("delete from presence where entity_id = @0", id);
            _db.Run("delete from distribution_share where distribution_id in (select id from distribution where subject_id = @0)", id);
            _db.Run("delete from distribution where subject_id = @0", id);
            _db.Run("delete from population_estimate where subject_id = @0", id);
            // Quem era categoria de uma distribuição some dela, e a lista deixa de ser completa (não dá para afirmar que está inteira).
            _db.Run("update distribution set complete = 0 where id in (select distribution_id from distribution_share where category_id = @0)", id);
            _db.Run("delete from distribution_share where category_id = @0", id);
            _db.Run("update entity_name set lang_id = null where lang_id = @0", id);
            _db.Run("delete from entity_name where entity_id = @0", id);
            _db.Run("delete from field_value where entity_id = @0", id);
            _db.Run("delete from entity_tag where entity_id = @0", id);
            _db.Run("delete from entity where id = @0", id);
            return 0;
        });
        return n;
    }

    /// Começo de uma sociedade (a ficha antiga): cria país, cultura e/ou etnia (os tipos pedidos) com o mesmo nome provisório e
    /// os liga entre si. Devolve os ids na ordem de kinds. Idioma, religião e raça não são criados: ninguém precisa inventá-los.
    public Array<long> CreateSociety(string name, string[] kinds)
    {
        if (kinds.Length == 0 || kinds.Any(k => k is not ("pais" or "cultura" or "etnia")) || kinds.Distinct().Count() != kinds.Length)
            throw new ArgumentException("uma sociedade começa por país, cultura e/ou etnia, sem repetir");
        return _db.Tx(() =>
        {
            var made = kinds.ToDictionary(k => k, k => Create(k, name));
            if (made.TryGetValue("pais", out long p) && made.TryGetValue("cultura", out long c)) Link(p, c, "cultura_presente");
            if (made.TryGetValue("pais", out p) && made.TryGetValue("etnia", out long et)) Link(p, et, "etnia_presente");
            if (made.TryGetValue("etnia", out et) && made.TryGetValue("cultura", out c)) Link(et, c, "cultura_presente");
            return new Array<long>(kinds.Select(k => made[k]));
        });
    }

    /// O nome contém o texto, sem diferenciar maiúsculas nem acentos (texto vazio casa com tudo).
    static bool Matches(string name, string text) => text == "" || CultureInfo.InvariantCulture.CompareInfo.IndexOf(name, text, Loose) >= 0;

    static string Str(object? o) => o?.ToString() ?? "";
}
