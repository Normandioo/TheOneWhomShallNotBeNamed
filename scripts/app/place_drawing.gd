extends RefCounted
## Desenhar o contorno de um lugar (uma região da ficha aberta) clicando ponto a ponto no globo; perto do vértice de outro contorno o ponto
## cola nele. Ao concluir, cria o lugar e liga a entidade a ele (ou troca o contorno do lugar refeito). Main roteia o clique (draw_click).

const EvronGeo = preload("res://scripts/data/evron_geo.gd")

var hub                    # o DomainHub: o banco, a ficha aberta, o mapa
var draw_panel             # a barra do modo desenhar
var drawing := false       # no modo desenhar: o clique no globo marca um ponto do contorno
var _draw_pts: Array[Vector2] = []  # (lat, lon) de cada ponto marcado, na ordem
var _draw_entity := 0      # de quem é a fronteira
var _draw_name := ""
var _draw_role := "territorio"
var _draw_place := 0       # != 0: refazendo o contorno desse lugar
var _draw_message := ""


## Liga ao hub e à barra do modo desenhar; a ficha pede o desenho pelos botões de fronteira.
func setup(domain_hub, panel) -> void:
	hub = domain_hub
	hub.place_drawing = self
	draw_panel = panel
	panel.undo_requested.connect(draw_undo)
	panel.finish_requested.connect(draw_finish)
	panel.cancel_requested.connect(draw_cancel)
	if hub.usable:
		hub.sheet.border_draw_requested.connect(func(n: String, role: String) -> void: start_border(n, role, 0))
		hub.sheet.border_redraw_requested.connect(func(place_id: int, role: String) -> void: start_border("", role, place_id))


## Abrir outra ficha no meio do desenho o perderia: devolve false e avisa na barra.
func allow_open() -> bool:
	if not drawing:
		return true
	_draw_message = "Conclua ou cancele o desenho antes de abrir outro cadastro."
	_refresh_draw()
	return false


## Entra no modo desenhar para a ficha aberta: o clique no globo passa a marcar os pontos do contorno (draw_click). place_id != 0 refaz o
## contorno desse lugar; senão, ao concluir, cria o lugar com o nome dado e liga a entidade a ele com a função (role).
func start_border(place_name: String, role: String, place_id: int = 0) -> void:
	if not hub.usable or drawing or hub.current() == 0:
		return
	if place_id == 0 and place_name.strip_edges() == "":
		hub.sheet.show_border_message("Dê um nome à região antes de desenhar.")
		return
	if hub.territories != null:
		hub.territories.stop_painting()
	drawing = true
	_draw_entity = hub.current()
	_draw_name = place_name.strip_edges()
	_draw_role = role
	_draw_place = place_id
	_draw_pts.clear()
	_draw_message = "Clique no globo para marcar cada ponto; arraste para girar. Perto do vértice de outra fronteira o ponto cola nele."
	_refresh_draw()


## Um clique no globo no modo desenhar: marca um ponto. Se cai a menos de snap_km de um vértice de um contorno desenhado (o que está no mapa),
## cola nesse vértice, para que duas fronteiras vizinhas dividam a borda sem fresta.
func draw_click(dir: Vector3, snap_km: float) -> void:
	if not drawing or dir == Vector3.ZERO:
		return
	var ll := EvronGeo.lat_lon(dir)
	var pt := Vector2(ll.x, ll.y)
	var glued := false
	var best := snap_km
	for it in hub.map_items():
		var vs: PackedFloat64Array = it.vertices
		for i in vs.size() / 2:
			var d := EvronGeo.distance_km(dir, EvronGeo.dir(vs[2 * i], vs[2 * i + 1]))
			if d <= best:
				best = d
				pt = Vector2(vs[2 * i], vs[2 * i + 1])
				glued = true
	if not _draw_pts.is_empty() and _draw_pts[_draw_pts.size() - 1].is_equal_approx(pt):
		_draw_message = "Esse ponto já está marcado."
	else:
		_draw_pts.append(pt)
		_draw_message = "Ponto colado ao vértice de outra fronteira." if glued else "Continue marcando; com 3 pontos já dá para concluir."
	_refresh_draw()


func draw_undo() -> void:
	if drawing and not _draw_pts.is_empty():
		_draw_pts.pop_back()
		_draw_message = "Último ponto desfeito."
		_refresh_draw()


func draw_cancel() -> void:
	if drawing:
		_end_draw()


## Conclui: cria o lugar com o contorno e liga a entidade (ou troca o contorno do lugar que estava sendo refeito). Um contorno que não vale
## (cruza ele mesmo, grande demais, sem área) não é gravado e o desenho continua, para desfazer pontos.
func draw_finish() -> void:
	if not drawing:
		return
	if _draw_pts.size() < 3:
		_draw_message = "Marque ao menos 3 pontos."
		_refresh_draw()
		return
	var flat := PackedFloat64Array()
	for p in _draw_pts:
		flat.append_array([p.x, p.y])
	var done := false
	if _draw_place != 0:
		done = hub.registry.SetPlaceVertices(_draw_place, flat) != null
	else:
		var made = hub.registry.AddPolygonPlace(_draw_name, "regiao", flat, "")
		if made != null:
			done = hub.registry.AddPresence(_draw_entity, int(made), _draw_role, "media") != null
	if not done:
		_draw_message = "Esse contorno não vale: ele cruza ele mesmo, é grande demais ou não tem área. Desfaça pontos ou cancele."
		_refresh_draw()
		return
	var entity := _draw_entity
	_end_draw()
	hub.open(entity)


func _end_draw() -> void:
	drawing = false
	_draw_pts.clear()
	_draw_place = 0
	if hub.map != null:
		hub.map.show_draft([])
	if draw_panel != null:
		draw_panel.hide_panel()


func _refresh_draw() -> void:
	var dirs: Array = []
	for p in _draw_pts:
		dirs.append(EvronGeo.dir(p.x, p.y))
	if hub.map != null:
		hub.map.show_draft(dirs)
	if draw_panel != null:
		draw_panel.show_state("Desenhando fronteira: %s" % (_draw_name if _draw_name != "" else "novo contorno"), _draw_pts.size(), _draw_message)

