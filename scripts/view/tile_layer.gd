extends Node3D
## Uma camada em blocos sobre a esfera: lê a pirâmide de data/evron/tiles/<nome>/ (tools/build_tiles.py) e mostra,
## em cada região visível, o bloco do nível em que um texel ocupa ~1 pixel da tela. Só esses blocos ficam na memória.
##
## - Escolha (a cada quadro): árvore de quatro filhos a partir dos 2 blocos do nível 0. Um bloco atrás do horizonte
##   some; um bloco grande demais na tela desce para os filhos, mas só quando os 4 já chegaram: até lá ele mesmo
##   aparece. Assim nunca abre buraco, e o nível 0 (sempre carregado) cobre o planeta inteiro.
## - Carga: os arquivos são lidos em threads (WorkerThreadPool); a textura é criada no quadro, poucas por vez.
## - Cache: no máximo MAX_CACHE blocos; os usados há mais tempo saem primeiro (o nível 0 nunca sai).
## O nó fica no centro do planeta, sem rotação: o referencial é o do planeta (EvronGeo).

const EvronGeo = preload("res://scripts/data/evron_geo.gd")
const TILE_SHADER = preload("res://shaders/globe_tile.gdshader")

const ROOT := "res://data/evron/tiles/"
const MAX_CACHE := 160            # ~1,3 MiB de GPU por bloco de 512 px com mipmaps: ~210 MiB no máximo
const UPLOADS_PER_FRAME := 4      # texturas criadas por quadro (cada uma custa alguns ms)
const DETAIL := 1.0               # desce de nível quando 1 texel passa de DETAIL pixels na tela
const SEGMENTS := [64, 48, 32]    # divisões do pedaço de esfera por nível (o resto usa o último): a corda dos
                                  # blocos grandes afundaria quilômetros e o globo de baixo apareceria por cima

var radius := 1.0
var levels := 0
var tile_px := 512
var name_id := ""

var drawn: Array[String] = []     # blocos na tela no último quadro (para os testes e as medições)
var _tiles := {}                  # chave "z/y/x" -> {"node": MeshInstance3D, "used": int}
var _loading := {}                # chave -> id da tarefa
var _ready_images: Array = []     # [chave, Image] vindos das threads
var _mutex := Mutex.new()
var _frame := 0
var _height_tex: Texture2D
var _river_tex: Texture2D


## Abre a pirâmide `tile_set` (pasta em data/evron/tiles/). O nível 0 é carregado na hora: cobre o planeta todo.
func open(tile_set: String, globe_radius: float, height_tex: Texture2D, river_tex: Texture2D) -> bool:
	close()
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(ROOT + tile_set + "/manifest.json"))
	if manifest == null:
		push_error("pirâmide de blocos não encontrada: " + tile_set)
		return false
	name_id = tile_set
	levels = int(manifest["levels"])
	tile_px = int(manifest["tile"])
	radius = globe_radius
	_height_tex = height_tex
	_river_tex = river_tex
	for x in 2:
		var key := _key(0, 0, x)
		_add_tile(key, _load_image(key))
	return true


## Fecha a pirâmide e libera tudo (espera as threads que ainda estão lendo).
func close() -> void:
	for task in _loading.values():
		WorkerThreadPool.wait_for_task_completion(task)
	_loading.clear()
	_ready_images.clear()
	for t in _tiles.values():
		t["node"].queue_free()
	_tiles.clear()
	drawn.clear()
	name_id = ""


func _exit_tree() -> void:
	close()


## Um quadro: escolhe os blocos para a câmera, cria as texturas que chegaram e limpa o cache.
func update(cam: Camera3D) -> void:
	if name_id == "":
		return
	_frame += 1
	_upload_ready()
	var focal := cam.get_viewport().get_visible_rect().size.y / (2.0 * tan(deg_to_rad(cam.fov) / 2.0))
	var want := {}
	for x in 2:
		_select(0, 0, x, cam.global_position, focal, want)
	drawn.clear()
	for key in _tiles:
		var on: bool = want.has(key)
		_tiles[key]["node"].visible = on
		if on:
			drawn.append(key)
	_evict(want)


## Memória de GPU aproximada dos blocos carregados, em MiB (RGBA8 + mipmaps).
func gpu_mib() -> float:
	return _tiles.size() * tile_px * tile_px * 4 * 4.0 / 3.0 / 1048576.0


func loaded_count() -> int:
	return _tiles.size()


## O nível mais detalhado entre os blocos na tela.
func max_drawn_level() -> int:
	var m := -1
	for key in drawn:
		m = maxi(m, int(key.get_slice("/", 0)))
	return m


# --- Escolha dos blocos ---------------------------------------------------------------------------------------

func _select(z: int, y: int, x: int, cam_pos: Vector3, focal: float, want: Dictionary) -> void:
	var key := _key(z, y, x)
	var b := _bounds(z, y, x)
	var center := EvronGeo.dir((b.y + b.w) / 2.0, (b.x + b.z) / 2.0)
	var half := _half_angle(b, center)
	var dist := cam_pos.length()
	# Atrás do horizonte: o ângulo até o bloco passa do horizonte (acos(R/d)) mais o raio angular do bloco.
	var horizon := acos(clampf(radius / dist, -1.0, 1.0))
	if acos(clampf(center.dot(cam_pos / dist), -1.0, 1.0)) > horizon + half:
		return
	_tiles[key]["used"] = _frame
	if z + 1 < levels and _texel_px(b, center, half, cam_pos, focal) > DETAIL:
		var children := [_key(z + 1, 2 * y, 2 * x), _key(z + 1, 2 * y, 2 * x + 1),
			_key(z + 1, 2 * y + 1, 2 * x), _key(z + 1, 2 * y + 1, 2 * x + 1)]
		var all_in := true
		for c in children:
			if not _tiles.has(c):
				all_in = false
				_request(c)
		if all_in:
			for dy in 2:
				for dx in 2:
					_select(z + 1, 2 * y + dy, 2 * x + dx, cam_pos, focal, want)
			return
	want[key] = true


## Pixels da tela ocupados por um texel do bloco, no ponto do bloco mais perto da câmera.
func _texel_px(b: Vector4, center: Vector3, half: float, cam_pos: Vector3, focal: float) -> float:
	var lat_mid := deg_to_rad((b.y + b.w) / 2.0)
	var texel := deg_to_rad(b.z - b.x) * radius * maxf(cos(lat_mid), 0.05) / tile_px
	var nearest := maxf(cam_pos.distance_to(center * radius) - half * radius, radius * 1e-4)
	return texel / nearest * focal


## Ângulo do centro do bloco até o canto mais distante (raio angular, para o teste do horizonte).
func _half_angle(b: Vector4, center: Vector3) -> float:
	var m := 1.0
	for lat in [b.y, b.w, (b.y + b.w) / 2.0]:
		for lon in [b.x, b.z]:
			m = minf(m, center.dot(EvronGeo.dir(lat, lon)))
	return acos(clampf(m, -1.0, 1.0))


## Limites do bloco em graus: Vector4(lon0, lat0, lon1, lat1).
func _bounds(z: int, y: int, x: int) -> Vector4:
	var dlon := 360.0 / float(2 << z)
	var dlat := 180.0 / float(1 << z)
	return Vector4(-180.0 + x * dlon, 90.0 - (y + 1) * dlat, -180.0 + (x + 1) * dlon, 90.0 - y * dlat)


# --- Carga e cache ---------------------------------------------------------------------------------------------

func _request(key: String) -> void:
	if _loading.has(key) or _tiles.has(key):
		return
	_loading[key] = WorkerThreadPool.add_task(func() -> void:
		var img := _load_image(key)
		_mutex.lock()
		_ready_images.append([key, img])
		_mutex.unlock())


func _load_image(key: String) -> Image:
	var z := key.get_slice("/", 0)
	var path := ProjectSettings.globalize_path("%s%s/%s/%s_%s.jpg" % [ROOT, name_id, z, key.get_slice("/", 1), key.get_slice("/", 2)])
	var img := Image.load_from_file(path)
	if img != null:
		img.generate_mipmaps()  # na thread: de longe o bloco não cintila
	return img


func _upload_ready() -> void:
	_mutex.lock()
	var batch := _ready_images.slice(0, UPLOADS_PER_FRAME)
	_ready_images = _ready_images.slice(UPLOADS_PER_FRAME)
	_mutex.unlock()
	for item in batch:
		var key: String = item[0]
		WorkerThreadPool.wait_for_task_completion(_loading[key])
		_loading.erase(key)
		if item[1] == null:
			push_error("bloco não encontrado: %s/%s" % [name_id, key])
		else:
			_add_tile(key, item[1])


func _add_tile(key: String, img: Image) -> void:
	var z := int(key.get_slice("/", 0))
	var mat := ShaderMaterial.new()
	mat.shader = TILE_SHADER
	mat.set_shader_parameter("tile", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("height_map", _height_tex)
	mat.set_shader_parameter("river_map", _river_tex)
	var node := MeshInstance3D.new()
	node.mesh = _patch(_bounds(z, int(key.get_slice("/", 1)), int(key.get_slice("/", 2))), SEGMENTS[mini(z, SEGMENTS.size() - 1)])
	node.material_override = mat
	node.visible = false
	add_child(node)
	_tiles[key] = {"node": node, "used": _frame}


## Tira do cache os blocos usados há mais tempo, sem mexer no nível 0 nem no que está na tela.
func _evict(want: Dictionary) -> void:
	if _tiles.size() <= MAX_CACHE:
		return
	var old: Array = []
	for key in _tiles:
		if not want.has(key) and not key.begins_with("0/"):
			old.append([_tiles[key]["used"], key])
	old.sort()
	for i in mini(_tiles.size() - MAX_CACHE, old.size()):
		_tiles[old[i][1]]["node"].queue_free()
		_tiles.erase(old[i][1])


## Pedaço de esfera do bloco: grade de `seg` x `seg`, UV de 0 a 1 de oeste para leste e de norte para sul.
func _patch(b: Vector4, seg: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for j in seg + 1:
		var lat := lerpf(b.w, b.y, float(j) / seg)
		for i in seg + 1:
			var n := EvronGeo.dir(lat, lerpf(b.x, b.z, float(i) / seg))
			verts.append(n * radius)
			normals.append(n)
			uvs.append(Vector2(float(i) / seg, float(j) / seg))
	for j in seg:
		for i in seg:
			var a := j * (seg + 1) + i
			idx.append_array([a, a + 1, a + seg + 1, a + 1, a + seg + 2, a + seg + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _key(z: int, y: int, x: int) -> String:
	return "%d/%d/%d" % [z, y, x]
