extends Control
## O brasão do cadastro: um sol de raios ondulados em volta de um medalhão com um escudo na cor do cadastro. Só desenha.

const RAYS := 18
const SUN := Color("#b8706a")
const RING := Color("#e3a9a0")

var color := Color("#6e86d8"):
	set(value):
		color = value
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(88, 88)


func _draw() -> void:
	var c := size / 2.0
	var outer := minf(size.x, size.y) / 2.0 - 1.0
	var inner := outer * 0.69
	var step := TAU / RAYS
	for i in RAYS:
		var a0 := i * step - PI / 2.0
		var a1 := a0 + step * 0.5
		var a2 := a0 + step
		var tip := c + Vector2.from_angle(a1 + step * 0.18) * outer
		var wave1 := c + Vector2.from_angle(a0 + step * 0.18) * (inner + outer) * 0.51
		var wave2 := c + Vector2.from_angle(a1 + step * 0.55) * (inner + outer) * 0.48
		var pts := PackedVector2Array()
		pts.append(c + Vector2.from_angle(a0) * inner)
		for k in range(1, 6):
			pts.append(_bezier(c + Vector2.from_angle(a0) * inner, wave1, tip, k / 5.0))
		for k in range(1, 6):
			pts.append(_bezier(tip, wave2, c + Vector2.from_angle(a2) * inner, k / 5.0))
		draw_colored_polygon(pts, SUN)
	draw_circle(c, inner * 1.02, SUN)
	draw_circle(c, inner * 0.9, Color("#3a1f22"))
	draw_arc(c, inner * 0.74, 0.0, TAU, 48, RING, 1.0)
	var s := inner * 0.5  # o escudo
	var shield := PackedVector2Array([c + Vector2(-s, -s * 0.9), c + Vector2(s, -s * 0.9), c + Vector2(s, s * 0.15),
		c + Vector2(0, s * 1.0), c + Vector2(-s, s * 0.15)])
	draw_colored_polygon(shield, color)
	draw_polyline(shield + PackedVector2Array([shield[0]]), Color("#f0e0d0"), 1.5)
	var star := PackedVector2Array()
	for k in 10:
		var r := s * (0.5 if k % 2 == 0 else 0.22)
		star.append(c + Vector2(0, -s * 0.15) + Vector2.from_angle(-PI / 2.0 + k * PI / 5.0) * r)
	draw_colored_polygon(star, Color("#f4ebd3"))


func _bezier(p0: Vector2, p1: Vector2, p2: Vector2, t: float) -> Vector2:
	return p0.lerp(p1, t).lerp(p1.lerp(p2, t), t)
