## A altitude do mundo em memória: metros, float32, equiretangular (EvronGeo), a mesma imagem que o globo desenha.
## Sabe achar os pixels de um disco na esfera (o pincel) e ler e gravar alturas. Não conhece tela nem comandos:
## quem edita guarda o "antes" para desfazer (TerrainBrush).

const EvronGeo = preload("res://scripts/data/evron_geo.gd")

var img: Image
var size: Vector2i
var dirty := false  # mudou desde a última vez que a textura do globo foi atualizada


func _init(height: Image) -> void:
	img = height
	size = height.get_size()


func get_h(idx: int) -> float:
	return img.get_pixel(idx % size.x, idx / size.x).r


func set_h(idx: int, meters: float) -> void:
	img.set_pixel(idx % size.x, idx / size.x, Color(meters, 0.0, 0.0))
	dirty = true


func height_at(n: Vector3) -> float:
	var p := EvronGeo.pixel(n, size)
	return img.get_pixel(p.x, p.y).r


## Grava um conjunto de alturas (índice do pixel -> metros): usado para desfazer e refazer.
func write(values: Dictionary) -> void:
	for idx in values:
		set_h(idx, values[idx])


## Os pixels a menos de `radius_km` (pela superfície) da direção n, com o peso do pincel:
## 1 no centro e 0 na borda, sem degrau ((1 - (d/r)²)²). Dá a volta na longitude 180° e passa pelos polos.
## Retorna [PackedInt32Array índices, PackedFloat32Array pesos].
func disk(n: Vector3, radius_km: float) -> Array:
	var a := radius_km / EvronGeo.RADIUS_KM  # raio angular (rad)
	var ll := EvronGeo.lat_lon(n)
	var lat0 := deg_to_rad(ll.x)
	var idx := PackedInt32Array()
	var weight := PackedFloat32Array()
	var y_top := clampi(int(floorf((0.5 - (lat0 + a) / PI) * size.y)), 0, size.y - 1)
	var y_bottom := clampi(int(floorf((0.5 - (lat0 - a) / PI) * size.y)), 0, size.y - 1)
	var xc := (ll.y / 360.0 + 0.5) * size.x
	for y in range(y_top, y_bottom + 1):
		var lat := PI * (0.5 - (y + 0.5) / size.y)
		# Meia largura em longitude do disco nesta linha (lei dos cossenos); perto do polo, a linha inteira.
		var c := (cos(a) - sin(lat) * sin(lat0)) / maxf(cos(lat) * cos(lat0), 1e-9)
		if c > 1.0:
			continue
		var half_lon := PI if c < -1.0 else acos(c)
		var n_px := mini(int(ceilf(half_lon / TAU * size.x)) + 1, size.x / 2)
		for k in range(-n_px, n_px + 1):
			var x := posmod(int(floorf(xc)) + k, size.x)
			var p := EvronGeo.dir(rad_to_deg(lat), ((x + 0.5) / size.x - 0.5) * 360.0)
			var d := atan2(p.cross(n).length(), p.dot(n)) / a
			if d < 1.0:
				idx.append(y * size.x + x)
				weight.append((1.0 - d * d) * (1.0 - d * d))
	return [idx, weight]


## Direção na esfera do centro do pixel idx.
func dir_of(idx: int) -> Vector3:
	var x := idx % size.x
	var y := idx / size.x
	return EvronGeo.dir(90.0 - (y + 0.5) * 180.0 / size.y, ((x + 0.5) / size.x - 0.5) * 360.0)


## Média das alturas em volta de um pixel (3x3, com a volta na longitude): para o pincel de suavizar.
func neighbor_mean(idx: int) -> float:
	var x := idx % size.x
	var y := idx / size.x
	var s := 0.0
	var count := 0
	for dy in [-1, 0, 1]:
		var yy: int = y + dy
		if yy < 0 or yy >= size.y:
			continue
		for dx in [-1, 0, 1]:
			s += img.get_pixel(posmod(x + dx, size.x), yy).r
			count += 1
	return s / count
