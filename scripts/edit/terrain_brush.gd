## O pincel de terreno: uma pincelada (apertar, arrastar, soltar) vira UM comando na pilha de desfazer.
## Aqui fica o que o resto do GDScript usa (os modos, os nomes, os parâmetros, quando marcar); o trabalho pixel a pixel
## é do BrushKernel (C#), que guarda o "antes" de cada pixel e devolve a edição (TerrainEdit) ao soltar.
##
## Modos (ver o estudo "Pincéis Procedurais de Terreno" no cofre):
##  - Elevar/Rebaixar: forma de colina com ondulação (fbm) em vez de um cone liso; `roughness` mistura o cone e o ruído.
##  - Nivelar: puxa para a altura do ponto inicial, com textura fraca de ruído.
##  - Suavizar: média ponderada; a intensidade decide quanto.
##  - Montanhas: ruído de cristas. SÓ SOMA relevo (nunca baixa o terreno): vale = sem mudança, então o continente
##    não ganha água. Rugosidade alta = cristas finas e altas; baixa = maciços arredondados.
##  - Erosão: erosão térmica. Move material das encostas íngremes (acima do ângulo de repouso) para as vizinhas mais
##    baixas: arredonda picos, entulha vales, conserva a massa.
##  - Vales: erosão hidráulica simplificada. Cada pixel escoa para o vizinho mais baixo; o fluxo acumulado rio abaixo
##    entalha o terreno. Nunca baixa a terra abaixo de 1 m (não cria mar) nem levanta o mar (não cria ilha).

const Terrain = preload("res://scripts/world/Terrain.cs")
const BrushKernel = preload("res://scripts/edit/BrushKernel.cs")
const CommandStack = preload("res://scripts/edit/command_stack.gd")
const EvronGeo = preload("res://scripts/data/evron_geo.gd")

enum Op { RAISE, LOWER, FLATTEN, SMOOTH, MOUNTAINS, ERODE, VALLEYS }  # mesma ordem de BrushKernel.Op
const NAMES := ["Elevar", "Rebaixar", "Nivelar", "Suavizar", "Montanhas", "Erosão", "Vales"]
const MOUNTAIN_CAP := 1.5  # montanhas: uma pincelada sobe no máximo intensidade × ganho × 1,5 em cada pixel (sem platôs)
const MOUNTAIN_GAIN := 6.0 # a intensidade (até 1000) vale ×6 em montanhas: picos de milhares de metros
const SPACING := 0.25      # nova marca do pincel a cada 1/4 do raio percorrido

var op := Op.RAISE
var radius_km := 150.0
var strength := 100.0  # metros por marca no centro (elevar/rebaixar); nivelar/suavizar/erosão: strength/500 por marca
var roughness := 0.5   # 0..1: quanto o ruído manda na forma
var active := false
var seed_value := -1   # -1 = sorteia uma semente nova a cada pincelada (um número fixo repete o mesmo relevo)
## Vales: pixel -> área de captação da última marca (para os testes e para estudar).
var last_flow: Dictionary:
	get:
		return _kernel.LastFlow()

var _kernel := BrushKernel.new()
var _terrain: Terrain
var _stack: CommandStack
var _target := 0.0      # nivelar: a altura do ponto onde a pincelada começou
var _last := Vector3.ZERO


func _init(terrain: Terrain, stack: CommandStack) -> void:
	_terrain = terrain
	_stack = stack
	_kernel.Setup(terrain)


func begin(n: Vector3) -> void:
	active = true
	_target = _terrain.HeightAt(n)
	_kernel.Begin(seed_value if seed_value >= 0 else randi())
	_dab(n)


## Continua a pincelada em n, se andou o bastante desde a última marca.
func drag(n: Vector3) -> void:
	if active and EvronGeo.distance_km(n, _last) >= radius_km * SPACING:
		_dab(n)


## Termina a pincelada e a registra como comando. Retorna quantos pixels de altura mudaram.
func end() -> int:
	active = false
	var edit = _kernel.End(op == Op.VALLEYS)
	if edit == null:
		return 0
	_stack.push("%s terreno (%d pontos)" % [NAMES[op], edit.Count], edit)
	return edit.Count


func _dab(n: Vector3) -> void:
	_last = n
	_kernel.Dab(op, n, radius_km, strength, roughness, _target, MOUNTAIN_GAIN, MOUNTAIN_CAP)
