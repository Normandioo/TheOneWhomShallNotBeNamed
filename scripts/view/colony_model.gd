## Modelos 3D simples da colônia (cúpula, módulo, painéis solares e antena) e o marcador de longe.
## Só constrói malhas; quem as posiciona é o ColonyLayer.


## Modelo da colônia, com a base em y = 0 e o eixo Y para cima.
static func build() -> Node3D:
	var models := Node3D.new()
	var dome := SphereMesh.new()
	dome.radius = 0.008
	dome.height = 0.008
	dome.is_hemisphere = true
	_part(models, dome, Vector3.ZERO, Color(0.85, 0.85, 0.9))
	var hab := BoxMesh.new()
	hab.size = Vector3(0.006, 0.004, 0.006)
	_part(models, hab, Vector3(-0.01, 0.002, -0.008), Color(0.75, 0.7, 0.6))
	var panel := BoxMesh.new()
	panel.size = Vector3(0.012, 0.0008, 0.006)
	_part(models, panel, Vector3(0.016, 0.001, -0.004), Color(0.12, 0.18, 0.45))
	_part(models, panel, Vector3(0.016, 0.001, 0.005), Color(0.12, 0.18, 0.45))
	var antenna := CylinderMesh.new()
	antenna.top_radius = 0.0004
	antenna.bottom_radius = 0.0008
	antenna.height = 0.014
	_part(models, antenna, Vector3(-0.008, 0.007, 0.008), Color(0.6, 0.6, 0.6))
	return models


## Marcador luminoso que aparece no lugar do modelo quando o zoom está longe.
static func build_marker(parent: Node3D) -> MeshInstance3D:
	var beacon := BoxMesh.new()
	beacon.size = Vector3(0.02, 0.06, 0.02)
	return _part(parent, beacon, Vector3(0.0, 0.03, 0.0), Color(0.3, 0.9, 1.0), true)


static func _part(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color, glow := false) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi
