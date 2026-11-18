extends "res://tests/test_suite.gd"
## Calendários locais guardados no banco (critérios 7 e 11 do plano de domínios), sem cena: um calendário compartilhado, vários
## por entidade e finalidade, troca de calendário numa data, definição que volta do banco já converte. As linhas "ERROR" das
## recusas são esperadas.

const Calendar = preload("res://scripts/world/calendar.gd")
const LocalCalendar = preload("res://scripts/world/local_calendar.gd")

const FOREVER := 9223372036854775807
const MESES := "Gelo\nNeve\nBrota\nChuva\nFlor\nSol\nCalor\nSeca\nColheita\nNévoa\nGeada\nLonga noite"


func run() -> void:
	var path := out_dir.path_join("calendar_use_suite.db")
	for ext in ["", "-journal"]:
		DirAccess.remove_absolute(path + ext)
	var r = load("res://scripts/world/Registry.cs").new()
	r.Open(path)

	# Definição: validações e o que volta do banco converte (inclusive o instante de 64 bits da era).
	var marco := Calendar.to_seconds(100, 3, 15, 12)
	var aren: int = r.AddCalendar("Calendário de Aren", "Contagem dos arenos", MESES, 6 * 3600, "exata", "Crônicas")
	var era_a: int = r.AddEra("Era de Aren", "EA", marco, "up", 1)
	r.AttachEra(aren, era_a, -9223372036854775807 - 1, FOREVER, 0)
	var def: Dictionary = r.CalendarDef(aren)
	if def.name != "Calendário de Aren" or def.month_names.size() != 12 or def.day_offset != 21600 or def.eras.size() != 1 or def.eras[0].start != marco:
		return fail("a definição não voltou do banco: %s" % [def])
	var l := LocalCalendar.to_local(def, marco)
	if l.status != "exata" or l.year != 1 or l.month_name != "Brota":
		return fail("a definição do banco deveria converter: %s" % [l])
	var n: int = r.Calendars().size()
	r.AddCalendar("Dois nomes", "", "Gelo\nNeve", 0, "exata", "")        # só 2 meses
	r.AddCalendar("Virada às 25h", "", "", 90000, "exata", "")             # a virada do dia fora de 0..86399 s
	r.AddCalendar("Confiável demais", "", "", 0, "certeza", "")            # confiabilidade desconhecida
	r.AddEra("Marco para trás", "", 0, "sideways", 1)                      # direção inválida
	if r.Calendars().size() != n:
		return fail("um calendário inválido foi aceito")
	ok("definição guardada e relida (64 bits) converte; nomes de mês, virada do dia, confiabilidade e direção inválidos recusados")

	# Critério 7: um calendário compartilhado por várias entidades; mais de um por entidade e por finalidade.
	var pais: int = r.Create("pais", "Reino de Aren")
	var etnia: int = r.Create("etnia", "Arenos")
	var religiao: int = r.Create("religiao", "Via do silêncio")
	var lunar: int = r.AddCalendar("Ciclo dos templos", "", "", 0, "aproximada", "")
	var era_t: int = r.AddEra("Era dos templos", "ET", Calendar.to_seconds(50, 1, 1), "up", 1)
	r.AttachEra(lunar, era_t, -9223372036854775807 - 1, FOREVER, 0)
	r.UseCalendar(pais, aren, "civil", 10)
	r.UseCalendar(etnia, aren, "tradicional", 5)
	r.UseCalendar(religiao, aren, "ritual", 0)
	if r.EntitiesUsing(aren, 0) != [pais, etnia, religiao]:
		return fail("o calendário deveria ser usado pelas três entidades: %s" % [r.EntitiesUsing(aren, 0)])
	r.UseCalendar(pais, lunar, "ritual", 1)             # outro calendário, outra finalidade
	r.UseCalendar(pais, lunar, "administrativo", 0)     # o mesmo calendário, outra finalidade
	var usos: Array = r.CalendarsOf(pais, 0)
	if usos.size() != 3 or usos[0].name != "Calendário de Aren" or usos[0].purpose != "civil" or usos[1].purpose != "ritual":
		return fail("o país usa 3 calendários, o de maior prioridade primeiro: %s" % [usos.map(func(u): return u.purpose)])
	r.UseCalendar(pais, aren, "civil", 3)               # repetição: mesma entidade + calendário + finalidade, sem prazo
	if r.CalendarsOf(pais, 0).size() != 3:
		return fail("repetir o mesmo uso nos mesmos períodos deveria ser recusado")
	r.UseCalendar(pais, aren, "inventada", 3)           # finalidade fora da lista
	if r.CalendarsOf(pais, 0).size() != 3:
		return fail("finalidade desconhecida foi aceita")
	ok("critério 7: um calendário em 3 entidades; um país com 3 usos (2 calendários, 3 finalidades) por prioridade; repetição e finalidade inválida recusadas")

	# Critério 11: consultar antes e depois da troca do calendário civil, como a de uma reforma.
	var reino: int = r.Create("pais", "Reino de Dravos")
	var antigo: int = r.AddCalendar("Calendário antigo", "", "", 0, "exata", "")
	var novo: int = r.AddCalendar("Calendário reformado", "", "", 0, "exata", "")
	var uso_antigo: int = r.UseCalendar(reino, antigo, "civil", 0)
	var t_reforma := Calendar.to_seconds(300, 1, 1)
	r.EndCalendarUse(uso_antigo, t_reforma)
	r.AddCalendarUse(reino, novo, "civil", t_reforma, FOREVER, 0)
	var antes: Array = r.CalendarsOf(reino, t_reforma - 1)
	var depois: Array = r.CalendarsOf(reino, t_reforma)
	if antes.size() != 1 or antes[0].calendar_id != antigo or depois.size() != 1 or depois[0].calendar_id != novo:
		return fail("a troca de calendário deveria valer exatamente em %d (fim excluído)" % t_reforma)
	r.AddCalendarUse(reino, antigo, "civil", Calendar.to_seconds(100, 1, 1), t_reforma - 10, 0)  # sobrepõe o uso antigo (que vai de sempre até a reforma)
	r.AddCalendarUse(reino, antigo, "civil", Calendar.to_seconds(100, 1, 1), Calendar.to_seconds(200, 1, 1), 0)  # idem
	if r.CalendarsOf(reino, Calendar.to_seconds(150, 1, 1)).size() != 1:
		return fail("um uso sobreposto foi aceito")
	r.EndCalendarUse(uso_antigo, t_reforma + 5)  # já está encerrado: recusado
	ok("critério 11: antes e depois da troca do calendário civil, fim excluído, usos sobrepostos recusados")

	# A ficha traz os calendários em uso, e duplicar/excluir levam os usos junto.
	var sheet: Dictionary = r.Sheet(pais, 0)
	if sheet.calendars.size() != 3 or sheet.calendars[0].name != "Calendário de Aren":
		return fail("a ficha deveria listar os 3 calendários em uso")
	var copia: int = r.Duplicate(pais, true, "")
	if r.CalendarsOf(copia, 0).size() != 3:
		return fail("duplicar com vínculos deveria copiar os usos de calendário")
	var sem_usos: int = r.Duplicate(pais, false, "Sem usos")
	if r.CalendarsOf(sem_usos, 0).size() != 0:
		return fail("duplicar sem vínculos não copia os usos")
	r.Delete(copia)
	if r.EntitiesUsing(aren, 0).has(copia) or r.EntitiesUsing(aren, 0).size() != 3:
		return fail("excluir a entidade deveria apagar os usos dela")
	ok("a ficha lista os calendários em uso; duplicar copia os usos só com vínculos; excluir os leva junto")

	# Persistência.
	r.Close()
	r.Open(path)
	if r.CalendarsOf(pais, 0).size() != 3 or r.CalendarsOf(reino, t_reforma).size() != 1 or r.CalendarDef(aren).eras[0].start != marco or r.Calendars().size() != n + 3:
		return fail("reabrir perdeu calendários, eras ou usos (calendários=%d)" % r.Calendars().size())
	ok("reabrir conserva calendários, eras e usos")
	r.Close()
