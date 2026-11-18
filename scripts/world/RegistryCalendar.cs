using System;
using System.Linq;
using Godot;
using Godot.Collections;
using GArray = Godot.Collections.Array;

namespace Evron;

/// Calendários locais (etapa 3 do plano de domínios): o cadastro do calendário, das eras e do uso por entidade, com validade
/// [início, fim). SÓ guarda e consulta: a conversão de datas é de scripts/world/local_calendar.gd, sobre o calendário universal.
/// Um calendário local desta etapa conserva a divisão de meses e dias do universal e varia nomes, numeração dos anos (eras),
/// virada do dia e formato. Calendários com outra duração de ano ou outra sequência de meses são da etapa 7.
public partial class Registry
{
    // calendar: a definição. month_names: 12 nomes, um por linha (NULL = os do calendário universal). day_offset: a virada do dia,
    //   em segundos depois da meia-noite universal. reliability: exata | aproximada | indisponivel (o que o autor garante).
    // era: um marco de contagem. start_instant é o instante universal do marco; o ano do marco é o número first_number e o
    //   número muda a cada virada de ano universal (o marco no meio do ano faz do ano parcial o primeiro). direction up = os
    //   números crescem com o tempo; down = crescem para o passado ("antes de").
    // calendar_era: a era que o calendário usa em cada período (reinados, reformas); a de maior prioridade vale quando há duas.
    // calendar_use: quem usa o calendário, para quê, quando e com que prioridade de exibição. Era e calendário são separados:
    //   várias contagens podem usar os mesmos meses e dias.
    const string CalendarsMigration = """
        create table calendar(
            id integer primary key,
            name text not null,
            description text,
            month_names text,
            day_offset integer not null default 0 check (day_offset >= 0 and day_offset < 86400),
            reliability text not null default 'exata' check (reliability in ('exata','aproximada','indisponivel')),
            source text,
            created_at integer not null default (unixepoch()));

        create table era(
            id integer primary key,
            name text not null,
            abbreviation text,
            start_instant integer not null,
            direction text not null default 'up' check (direction in ('up','down')),
            first_number integer not null default 1);

        create table calendar_era(
            calendar_id integer not null references calendar(id),
            era_id integer not null references era(id),
            valid_from integer not null,
            valid_to integer not null,
            priority integer not null default 0,
            primary key (calendar_id, era_id, valid_from),
            check (valid_from < valid_to));

        create table calendar_use(
            id integer primary key,
            entity_id integer not null references entity(id),
            calendar_id integer not null references calendar(id),
            purpose text not null check (purpose in ('civil','ritual','tradicional','administrativo','outro')),
            valid_from integer not null,
            valid_to integer not null,
            priority integer not null default 0,
            check (valid_from < valid_to));
        create index calendar_use_entity on calendar_use(entity_id);
        create index calendar_use_calendar on calendar_use(calendar_id);
        """;

    // ---- calendários e eras ----

    /// Cria um calendário. monthNames: 12 nomes, um por linha, ou vazio para os nomes do universal. reliability: exata | aproximada | indisponivel.
    public long AddCalendar(string name, string description, string monthNames, long dayOffset, string reliability, string source)
    {
        name = Clean(name);
        string? months = null;
        if (monthNames.Trim() != "")
        {
            var lines = monthNames.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            if (lines.Length != 12) throw new ArgumentException($"são 12 nomes de mês, vieram {lines.Length}");
            months = string.Join("\n", lines);
        }
        return _db.Insert("insert into calendar(name, description, month_names, day_offset, reliability, source) values (@0, @1, @2, @3, @4, @5)",
            name, description == "" ? null : description, months, dayOffset, reliability, source == "" ? null : source);
    }

    /// Cria o calendário com a sua primeira era (válida sempre), tudo ou nada: se a era for inválida, o calendário também não fica.
    public long CreateCalendar(string name, string description, string monthNames, long dayOffset, string reliability, string source,
                               string eraName, string eraAbbreviation, long eraStart, string direction, long firstNumber) =>
        _db.Tx(() =>
        {
            long id = AddCalendar(name, description, monthNames, dayOffset, reliability, source);
            AttachEra(id, AddEra(eraName, eraAbbreviation, eraStart, direction, firstNumber), Always, Forever, 0);
            return id;
        });

    /// Cria um marco de contagem. direction: up | down. firstNumber: o número do ano do marco (1, ou 0 se a contagem tem ano zero).
    public long AddEra(string name, string abbreviation, long startInstant, string direction, long firstNumber) =>
        _db.Insert("insert into era(name, abbreviation, start_instant, direction, first_number) values (@0, @1, @2, @3, @4)",
            Clean(name), abbreviation.Trim() == "" ? null : abbreviation.Trim(), startInstant, direction, firstNumber);

    /// O calendário passa a usar a era em [from, to). Duas eras no mesmo instante: vale a de maior prioridade.
    public void AttachEra(long calendarId, long eraId, long from, long to, long priority) =>
        _db.Run("insert into calendar_era(calendar_id, era_id, valid_from, valid_to, priority) values (@0, @1, @2, @3, @4)", calendarId, eraId, from, to, priority);

    /// Os calendários cadastrados: id, name, reliability e quantas eras (períodos de era) têm.
    public Array<Dictionary> Calendars() => new(
        _db.Rows("select c.id, c.name, c.reliability, (select count(*) from calendar_era e where e.calendar_id = c.id) from calendar c order by c.name collate nocase, c.id")
           .Select(r => new Dictionary { ["id"] = Convert.ToInt64(r[0]), ["name"] = Str(r[1]), ["reliability"] = Str(r[2]), ["eras"] = Convert.ToInt64(r[3]) }));

    /// A definição completa, o que local_calendar.gd precisa para converter: id, name, description, source, month_names
    /// (vazio = universais), day_offset, reliability e eras (um item por período: era_id, name, abbreviation, start, direction,
    /// first, valid_from, valid_to, priority).
    public Dictionary CalendarDef(long id)
    {
        var c = _db.Rows("select name, description, month_names, day_offset, reliability, source from calendar where id = @0", id);
        if (c.Count == 0) throw new ArgumentException($"calendário {id} não existe");
        var months = new GArray();
        foreach (var m in Str(c[0][2]).Split('\n', StringSplitOptions.RemoveEmptyEntries)) months.Add(m);
        var eras = new GArray();
        foreach (var r in _db.Rows("select e.id, e.name, e.abbreviation, e.start_instant, e.direction, e.first_number, ce.valid_from, ce.valid_to, ce.priority " +
                                   "from calendar_era ce join era e on e.id = ce.era_id where ce.calendar_id = @0 order by ce.valid_from, ce.priority desc", id))
            eras.Add(new Dictionary { ["era_id"] = Convert.ToInt64(r[0]), ["name"] = Str(r[1]), ["abbreviation"] = Str(r[2]), ["start"] = Convert.ToInt64(r[3]),
                                      ["direction"] = Str(r[4]), ["first"] = Convert.ToInt64(r[5]), ["valid_from"] = Convert.ToInt64(r[6]),
                                      ["valid_to"] = Convert.ToInt64(r[7]), ["priority"] = Convert.ToInt64(r[8]) });
        return new Dictionary { ["id"] = id, ["name"] = Str(c[0][0]), ["description"] = Str(c[0][1]), ["month_names"] = months,
                                ["day_offset"] = Convert.ToInt64(c[0][3]), ["reliability"] = Str(c[0][4]), ["source"] = Str(c[0][5]), ["eras"] = eras };
    }

    // ---- uso por entidade ----

    /// A entidade passa a usar o calendário para essa finalidade em [from, to). Um calendário serve a várias entidades e uma
    /// entidade usa vários calendários; só se recusa repetir a mesma entidade + calendário + finalidade em períodos sobrepostos.
    /// priority: ordem de exibição (maior primeiro). Devolve o id do uso.
    public long AddCalendarUse(long entityId, long calendarId, string purpose, long from, long to, long priority)
    {
        long dup = Convert.ToInt64(_db.Scalar(
            "select count(*) from calendar_use where entity_id = @0 and calendar_id = @1 and purpose = @2 and valid_from < @4 and @3 < valid_to", entityId, calendarId, purpose, from, to));
        if (dup > 0) throw new ArgumentException("esta entidade já usa este calendário para esta finalidade nesse período");
        return _db.Insert("insert into calendar_use(entity_id, calendar_id, purpose, valid_from, valid_to, priority) values (@0, @1, @2, @3, @4, @5)",
            entityId, calendarId, purpose, from, to, priority);
    }

    /// Uso sem prazo (sempre).
    public long UseCalendar(long entityId, long calendarId, string purpose, long priority) =>
        AddCalendarUse(entityId, calendarId, purpose, Always, Forever, priority);

    /// Encerra um uso em aberto em t (o fim é excluído: em t já não vale), como uma troca de calendário oficial.
    public void EndCalendarUse(long useId, long t)
    {
        int n = _db.Run("update calendar_use set valid_to = @0 where id = @1 and valid_to = @2 and valid_from < @0", t, useId, Forever);
        if (n == 0) throw new ArgumentException($"o uso {useId} não está em aberto antes de {t}");
    }

    /// Apaga um uso criado por engano (para encerrá-lo na história, use EndCalendarUse).
    public void DeleteCalendarUse(long useId) => _db.Run("delete from calendar_use where id = @0", useId);

    /// Os calendários que a entidade usa no instante t, o de maior prioridade primeiro: use_id, calendar_id, name, purpose, priority, from, to.
    public Array<Dictionary> CalendarsOf(long entityId, long t) => new(
        _db.Rows("select u.id, u.calendar_id, c.name, u.purpose, u.priority, u.valid_from, u.valid_to from calendar_use u join calendar c on c.id = u.calendar_id " +
                 "where u.entity_id = @0 and u.valid_from <= @1 and @1 < u.valid_to order by u.priority desc, u.id", entityId, t)
           .Select(r => new Dictionary { ["use_id"] = Convert.ToInt64(r[0]), ["calendar_id"] = Convert.ToInt64(r[1]), ["name"] = Str(r[2]), ["purpose"] = Str(r[3]),
                                         ["priority"] = Convert.ToInt64(r[4]), ["from"] = Convert.ToInt64(r[5]), ["to"] = Convert.ToInt64(r[6]) }));

    /// As entidades que usam o calendário no instante t.
    public Array<long> EntitiesUsing(long calendarId, long t) => new(
        _db.Rows("select distinct entity_id from calendar_use where calendar_id = @0 and valid_from <= @1 and @1 < valid_to order by entity_id", calendarId, t)
           .Select(r => Convert.ToInt64(r[0])));
}
