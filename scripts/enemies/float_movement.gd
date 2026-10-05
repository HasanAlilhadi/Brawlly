class_name FloatMovement
extends EnemyMovement
## Spirits: float above the ground (bobbing, on every peer) and drift through trees, walls and fences in
## weaving curves — nothing in the world stops them (their collision mask holds units only). Half see-through.

@export var hover: float = 0.35
@export var bob_height: float = 0.12
@export var bob_rate: float = 0.8
## Weaving: how far (radians) and how often (per second) the path swings side to side.
@export var weave: float = 0.6
@export var weave_rate: float = 0.5
## See-through share of the body (0 = solid).
@export var transparency: float = 0.3

var _time: float = 0.0


func setup(owner_enemy: Enemy) -> void:
	super(owner_enemy)
	_time = randf() * 10.0
	if not enemy._is_remote():
		enemy.collision_mask = GameConfig.LAYER_UNITS
	set_see_through(transparency)


func _process(delta: float) -> void:
	if enemy == null or enemy.is_dead:
		return
	_time += delta
	enemy.model.position.y = hover + sin(_time * TAU * bob_rate) * bob_height


func set_see_through(amount: float) -> void:
	for mesh in enemy.model.find_children("*", "GeometryInstance3D", true, false):
		(mesh as GeometryInstance3D).transparency = amount


func chase(target: Node3D, delta: float) -> Vector3:
	var to := flat_to(target)
	var reach := enemy.melee_range + Unit.target_radius(target)
	if to.length() <= reach:
		enemy.face_now(to)
		return Vector3.ZERO
	var swing := sin(_time * TAU * weave_rate) * weave * clampf((to.length() - reach) / 3.0, 0.0, 1.0)
	return to.normalized().rotated(Vector3.UP, swing)


func roam(point: Vector3, _delta: float, pace: float) -> Vector3:
	var to := point - enemy.global_position
	to.y = 0.0
	if to.length() < 0.3:
		return Vector3.ZERO
	return to.normalized().rotated(Vector3.UP, sin(_time * TAU * weave_rate) * weave * 0.5) * (1.0 if to.length() > 3.0 else pace)
