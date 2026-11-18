## Curva de enchimento do relevo: quanta água (metros de camada global, GEL) é preciso para o mar chegar a cada altitude.
## A água enche o relevo real de baixo para cima (Hellas e as planícies do norte primeiro).
## Construída uma vez a partir da grade de altitudes; depois, sea_level_for() é só uma busca binária.

var _h := PackedFloat64Array()  # altitudes em ordem crescente
var _v := PackedFloat64Array()  # água para encher até _h[k]
var _w := PackedFloat64Array()  # fração da área com altitude <= _h[k]
var _c := PackedFloat64Array()  # soma de altitude × fração de área até k


## heights = altitude de cada célula (m); weights = peso de área de cada célula (cos da latitude).
func setup(heights: PackedFloat32Array, weights: PackedFloat32Array) -> void:
	var n := heights.size()
	var order := range(n)
	order.sort_custom(func(a: int, b: int) -> bool: return heights[a] < heights[b])
	var total := 0.0
	for k in n:
		total += weights[k]
	for a in [_h, _v, _w, _c]:
		a.resize(n)
	var cw := 0.0
	var ch := 0.0
	for k in n:
		var idx: int = order[k]
		_h[k] = heights[idx]
		_v[k] = heights[idx] * cw - ch
		cw += weights[idx] / total
		ch += heights[idx] * weights[idx] / total
		_w[k] = cw
		_c[k] = ch


## Nível do mar (m) em que `gel` metros de água global ficam.
func sea_level_for(gel: float) -> float:
	if gel <= 0.0:
		return _h[0]
	var k := _v.bsearch(gel) - 1  # células 0..k ficam abaixo do nível
	return (gel + _c[k]) / _w[k]
