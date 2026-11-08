class_name BloodTotemModel
extends Node3D
## A Blood Totem (raised by Malakor's chalice at 66% / 33% health): a bone-and-iron pillar with a skull and a
## pulsing blood orb on top, built in code (~2 m). No clips: an empty AnimationPlayer keeps Unit happy.

var _orb: MeshInstance3D
var _time: float = 0.0


func _init() -> void:
	_box(Vector3(0.7, 0.2, 0.7), Vector3(0, 0.1, 0), Color(0.18, 0.15, 0.17))
	_box(Vector3(0.36, 1.3, 0.36), Vector3(0, 0.85, 0), Color(0.82, 0.78, 0.66))
	for i in 3:
		_box(Vector3(0.46, 0.08, 0.46), Vector3(0, 0.45 + i * 0.38, 0), Color(0.42, 0.09, 0.07))
	_box(Vector3(0.3, 0.28, 0.3), Vector3(0, 1.62, 0.02), Color(0.88, 0.84, 0.72))  # skull
	_box(Vector3(0.22, 0.06, 0.04), Vector3(0, 1.66, 0.17), Color(1.0, 0.15, 0.1), 3.0)  # eyes
	var mesh := SphereMesh.new()
	mesh.radius = 0.2
	mesh.height = 0.4
	_orb = _piece(mesh, Vector3(0, 2.0, 0), Color(0.9, 0.05, 0.12), 3.0)
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	add_child(player)


func _process(delta: float) -> void:
	_time += delta
	if _orb:
		_orb.position.y = 2.0 + sin(_time * 2.4) * 0.08
		_orb.scale = Vector3.ONE * (1.0 + 0.12 * sin(_time * 4.0))


func _box(size: Vector3, at: Vector3, color: Color, glow: float = 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _piece(mesh, at, color, glow)


func _piece(mesh: Mesh, at: Vector3, color: Color, glow: float) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	var piece := MeshInstance3D.new()
	piece.mesh = mesh
	piece.material_override = material
	piece.position = at
	add_child(piece)
	return piece
