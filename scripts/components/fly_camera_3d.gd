class_name FlyCamera3D
extends Camera3D
## Free-flying camera for looking around a scene (showcases, debugging).
## Hold the right mouse button to look; move with the `move_*` actions (WASD / arrows / left stick), up / down
## with `up_key` / `down_key`; Shift flies faster, the mouse wheel changes the speed. `fly_to()` glides to a view.

@export var speed: float = 8.0
@export var fast_multiplier: float = 3.0
@export var look_sensitivity: float = 0.003
@export var up_key: Key = KEY_E
@export var down_key: Key = KEY_Q
@export var min_speed: float = 1.0
@export var max_speed: float = 60.0

var _yaw: float = 0.0
var _pitch: float = 0.0
var _tween: Tween


func _ready() -> void:
	sync_angles()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_RIGHT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if button.pressed else Input.MOUSE_MODE_VISIBLE
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			speed = minf(speed * 1.2, max_speed)
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			speed = maxf(speed / 1.2, min_speed)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_stop_glide()
		var motion := (event as InputEventMouseMotion).relative
		_yaw -= motion.x * look_sensitivity
		_pitch = clampf(_pitch - motion.y * look_sensitivity, -PI * 0.49, PI * 0.49)
		rotation = Vector3(_pitch, _yaw, 0.0)


func _process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var lift := float(Input.is_key_pressed(up_key)) - float(Input.is_key_pressed(down_key))
	if input == Vector2.ZERO and lift == 0.0:
		return
	_stop_glide()
	var fast := fast_multiplier if Input.is_key_pressed(KEY_SHIFT) else 1.0
	var move := global_basis * Vector3(input.x, 0.0, input.y) + Vector3.UP * lift
	global_position += move.limit_length(1.0) * speed * fast * delta


## Glides to `at`, looking at `target`.
func fly_to(at: Vector3, target: Vector3, duration: float = 0.8) -> void:
	_stop_glide()
	var to := Transform3D(Basis.looking_at(target - at), at)
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "global_transform", to, duration)
	_tween.tween_callback(sync_angles)


func _stop_glide() -> void:
	if _tween and _tween.is_running():
		_tween.kill()
		sync_angles()


## Re-reads the look angles after the camera was moved by code.
func sync_angles() -> void:
	_pitch = rotation.x
	_yaw = rotation.y
