class_name FollowCamera3D
extends Camera3D
## Fixed-angle camera that smoothly follows a target (top-down / isometric-style games).
## Set `target`, then call `snap()` once to jump there without smoothing.
## `shake(strength, duration)` adds a short screen shake (hits, explosions).
## `zoom` scales `offset` (1 = as set, 1.2 = 20% further out); changes ease in over `zoom_smoothing`.
## `rotate_step(±1)` orbits the camera around the target by exactly 90° (eases in over `turn_smoothing`).
## Screen-space input (sticks, WASD) must then be turned by `view_yaw()`: `to_world(input)`.
## `fov` applies to the screen's short side (width in portrait, height in landscape), so a phone and a
## desktop monitor see about the same area of the world.

const QUARTER_TURN: float = PI / 2.0

@export var target: Node3D
@export var offset: Vector3 = Vector3(0, 7.0, 3.8)
@export var smoothing: float = 8.0
## Multiplier on `offset`: > 1 zooms out. Set it any time; the camera eases to it.
@export var zoom: float = 1.0
@export var zoom_smoothing: float = 4.0
## How fast a 90° turn eases in (higher = snappier).
@export var turn_smoothing: float = 10.0

var _shake_strength: float = 0.0
var _shake_time: float = 0.0
var _shake_duration: float = 0.0
## The point the camera looks at (eases toward the target).
var _focus: Vector3
var _has_focus: bool = false
var _zoom_current: float = 1.0
## Quarter turns around the target (0 = `offset` as set); the view eases to it.
var _turns: int = 0
var _yaw_current: float = 0.0


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
	_zoom_current = zoom
	_yaw_current = _target_yaw()
	_focus = target.global_position
	_has_focus = true
	_apply(Vector3.ZERO)


## Orbits the view by `steps` quarter turns (+1 = counter-clockwise seen from above).
func rotate_step(steps: int = 1) -> void:
	_turns = posmod(_turns + steps, 4)
	# Take the short way round (e.g. 270° → 0° turns 90°, not back 270°).
	var goal := _target_yaw()
	while goal - _yaw_current > PI:
		_yaw_current += TAU
	while _yaw_current - goal > PI:
		_yaw_current -= TAU


## The view's current angle around the up axis (radians; eases during a turn). World = screen rotated by this.
func view_yaw() -> float:
	return _yaw_current


## The view's resting angle (an exact multiple of 90°).
func target_yaw() -> float:
	return _target_yaw()


## A screen-space direction (x right, y down: sticks, WASD) as a flat world direction for this view.
func to_world(screen: Vector2) -> Vector2:
	return screen.rotated(-_yaw_current)


## Short random shake that fades out. Stronger shakes override weaker ones in progress.
func shake(strength: float = 0.15, duration: float = 0.2) -> void:
	if strength >= _shake_strength * (_shake_time / maxf(_shake_duration, 0.001)):
		_shake_strength = strength
		_shake_duration = duration
		_shake_time = duration


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	if not _has_focus:
		_focus = target.global_position
		_has_focus = true
	_focus = _focus.lerp(target.global_position, 1.0 - exp(-smoothing * delta))
	_zoom_current = lerpf(_zoom_current, zoom, 1.0 - exp(-zoom_smoothing * delta))
	var goal := _target_yaw()
	_yaw_current = lerpf(_yaw_current, goal, 1.0 - exp(-turn_smoothing * delta))
	if absf(goal - _yaw_current) < 0.001:
		_yaw_current = goal  # land exactly on the quarter turn
	var jitter := Vector3.ZERO
	if _shake_time > 0.0:
		_shake_time -= delta
		var amount := _shake_strength * maxf(_shake_time / _shake_duration, 0.0)
		jitter = Vector3(randf_range(-1.0, 1.0), randf_range(-0.5, 0.5), randf_range(-1.0, 1.0)) * amount
	_apply(jitter)


func _target_yaw() -> float:
	return _turns * QUARTER_TURN


## Camera at the focus + the (zoomed, turned) offset, looking back along it.
func _apply(jitter: Vector3) -> void:
	var arm := offset.rotated(Vector3.UP, _yaw_current) * _zoom_current
	global_position = _focus + arm + jitter
	global_basis = Basis.looking_at(-arm, Vector3.UP)
