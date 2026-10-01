class_name TrainingTarget
extends StaticBody3D
## An indestructible practice target. It reports real player damage and hit effects, but never loses health.

@export var title: String = "Training Dummy"

var team_id: int = GameConfig.ORC_TEAM
var radius: float = 0.3
var health_bar_height: float = 0.65
var is_dead: bool = false

var _total_damage: float = 0.0
var _hit_tween: Tween

@onready var _model: Node3D = $Model
@onready var _label: Label3D = $Label
@onready var _collision: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	add_to_group(&"breakable")
	add_to_group(&"active_enemies")  # quick attacks and aim assist can lock onto practice targets
	_fit_hitbox_to_model()
	_label.text = "%s\n∞" % title


func total_damage() -> float:
	return _total_damage


## Use the model's convex hull, not an oversized gameplay box. This keeps sword sectors, spear lanes and
## projectiles honest: damage is accepted only when their physics query touches the visible target.
## The hull is extruded straight up to `GameConfig.HIT_HEIGHT` (same footprint): the target is shorter
## than the height shots fly at (0.55–0.7 m), so thrown spears and arrows would pass over it otherwise.
func _fit_hitbox_to_model() -> void:
	var mesh_node := _model as MeshInstance3D
	if mesh_node == null:
		var meshes := _model.find_children("*", "MeshInstance3D", true, false)
		mesh_node = meshes[0] as MeshInstance3D if not meshes.is_empty() else null
	if mesh_node == null or mesh_node.mesh == null:
		return
	var hull := mesh_node.mesh.create_convex_shape() as ConvexPolygonShape3D
	# In the body's space (the target only turns around Y, so "up" stays up).
	var to_body := global_transform.affine_inverse() * mesh_node.global_transform
	var points := PackedVector3Array()
	for point in hull.points:
		var p := to_body * point
		points.append(p)
		points.append(Vector3(p.x, maxf(p.y, GameConfig.HIT_HEIGHT), p.z))
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	_collision.shape = shape
	_collision.transform = Transform3D.IDENTITY


func take_damage(amount: float, attacker: Node3D = null, is_melee: bool = true, crit: bool = false) -> void:
	if not multiplayer.is_server() or amount <= 0.0:
		return
	_total_damage += amount
	HitFx.report_hit(self, amount, attacker, crit, is_melee)
	HitFx.burst(global_position + Vector3(0, 0.45, 0), HitFx.Kind.WOOD, 9)
	_label.text = "%s\nTotal %d" % [title, roundi(_total_damage)]
	if _hit_tween:
		_hit_tween.kill()
	_model.scale = Vector3(1.12, 0.88, 1.12)
	_model.rotation.z = -0.08 if randf() < 0.5 else 0.08
	_hit_tween = create_tween().set_parallel(true)
	_hit_tween.tween_property(_model, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_hit_tween.tween_property(_model, "rotation:z", 0.0, 0.28).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
