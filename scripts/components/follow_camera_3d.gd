class_name FollowCamera3D
extends Camera3D
## Fixed-angle camera that smoothly follows a target (top-down / isometric-style games).
## Set `target`, then call `snap()` once to jump there without smoothing.
## `shake(strength, duration)` adds a short screen shake (hits, explosions).
## `fov` applies to the screen's short side (width in portrait, height in landscape), so a phone and a
## desktop monitor see about the same area of the world.

@export var target: Node3D
@export var offset: Vector3 = Vector3(0, 7.0, 3.8)
@export var smoothing: float = 8.0

var _shake_strength: float = 0.0
var _shake_time: float = 0.0
var _shake_duration: float = 0.0
var _base_position: Vector3


func _ready() -> void:
	fit_fov_to_short_side(self)
	get_viewport().size_changed.connect(func() -> void: fit_fov_to_short_side(self))
	if target:
		snap()


## Makes `camera.fov` cover the viewport's shorter side. Call again when the window is resized.
static func fit_fov_to_short_side(camera: Camera3D) -> void:
	var size := camera.get_viewport().get_visible_rect().size
	camera.keep_aspect = Camera3D.KEEP_WIDTH if size.x < size.y else Camera3D.KEEP_HEIGHT


func snap() -> void:
	global_position = target.global_position + offset
	_base_position = global_position
	look_at(target.global_position, Vector3.UP)


## Short random shake that fades out. Stronger shakes override weaker ones in progress.
func shake(strength: float = 0.15, duration: float = 0.2) -> void:
	if strength >= _shake_strength * (_shake_time / maxf(_shake_duration, 0.001)):
		_shake_strength = strength
		_shake_duration = duration
		_shake_time = duration


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	var goal := target.global_position + offset
	_base_position = _base_position.lerp(goal, 1.0 - exp(-smoothing * delta)) if _base_position != Vector3.ZERO else global_position
	var jitter := Vector3.ZERO
	if _shake_time > 0.0:
		_shake_time -= delta
		var amount := _shake_strength * maxf(_shake_time / _shake_duration, 0.0)
		jitter = Vector3(randf_range(-1.0, 1.0), randf_range(-0.5, 0.5), randf_range(-1.0, 1.0)) * amount
	global_position = _base_position + jitter
