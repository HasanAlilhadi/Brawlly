class_name TouchAimStick
extends TouchButton
## Touch button that doubles as an aim stick (twin-stick shooter style):
## press it and drag to aim, release to fire. Drag back to the center to cancel,
## or just tap to fire without aiming (e.g. auto-aim). Multi-touch safe.
## While aiming, `is_aiming` is true and `output` holds the aim (screen axes, length 0..1).

signal aim_released(direction: Vector2)
signal tapped
signal cancelled

## Drag distance (px) for full deflection.
@export var drag_radius: float = 120.0
## Below this fraction of drag_radius the stick counts as centered.
@export_range(0.0, 0.9) var aim_dead_zone: float = 0.25
@export var aim_ring_color: Color = Color(1, 1, 1, 0.18)
@export var knob_color: Color = Color(1, 1, 1, 0.7)

var output: Vector2 = Vector2.ZERO
var is_aiming: bool = false

var _dragged: bool = false
var _touch_pos: Vector2


func _input(event: InputEvent) -> void:
	if event is InputEventScreenDrag and (event as InputEventScreenDrag).index == _touch_index:
		_touch_pos = (event as InputEventScreenDrag).position
		_update_aim()
		get_viewport().set_input_as_handled()
		return
	var was_held := is_held
	super(event)
	if is_held and not was_held:
		_touch_pos = get_global_rect().get_center()
		_dragged = false
		_update_aim()
	elif was_held and not is_held:
		_finish()


## Drops the current aim without firing (e.g. when the game pauses mid-aim).
func reset() -> void:
	super()
	is_aiming = false
	_dragged = false
	output = Vector2.ZERO


func _update_aim() -> void:
	var offset := (_touch_pos - get_global_rect().get_center()) / drag_radius
	output = offset.limit_length(1.0)
	is_aiming = output.length() > aim_dead_zone
	if is_aiming:
		_dragged = true
	queue_redraw()


func _finish() -> void:
	if is_aiming:
		aim_released.emit(output)
	elif _dragged:
		cancelled.emit()
	else:
		tapped.emit()
	is_aiming = false
	_dragged = false
	output = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	super()
	if not is_held:
		return
	var center := size * 0.5
	draw_arc(center, drag_radius, 0.0, TAU, 64, aim_ring_color, 4.0, true)
	var knob_radius := minf(size.x, size.y) * 0.22
	var color := knob_color if (is_aiming or not _dragged) else Color(1, 0.4, 0.4, 0.7)
	draw_circle(center + output * drag_radius, knob_radius, color)
