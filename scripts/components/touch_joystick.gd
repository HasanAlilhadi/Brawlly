class_name TouchJoystick
extends Control
## Floating virtual joystick. Touch anywhere inside this control to place it, drag to steer.
## Multi-touch safe: it only tracks the finger that started inside its rect.
## Read `output` (Vector2, length 0..1, screen axes: +x right, +y down).

@export var radius: float = 110.0
@export var knob_radius: float = 46.0
@export_range(0.0, 0.9) var dead_zone: float = 0.12
## Where the idle hint is drawn, as a fraction of this control's size.
@export var idle_anchor: Vector2 = Vector2(0.35, 0.72)
@export var base_color: Color = Color(1, 1, 1, 0.14)
@export var knob_color: Color = Color(1, 1, 1, 0.55)
@export var ring_color: Color = Color(1, 1, 1, 0.3)
## Optional skin: drawn instead of the flat circles (the knob highlight shows while dragging).
@export var pad_texture: Texture2D
@export var knob_texture: Texture2D
@export var knob_held_texture: Texture2D

var output: Vector2 = Vector2.ZERO

var _touch_index: int = -1
var _center: Vector2
var _knob: Vector2


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _touch_index == -1 and get_global_rect().has_point(touch.position):
			_touch_index = touch.index
			_center = touch.position
			_knob = touch.position
			_update_output()
			get_viewport().set_input_as_handled()
		elif not touch.pressed and touch.index == _touch_index:
			release()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _touch_index:
			_knob = drag.position
			_update_output()
			get_viewport().set_input_as_handled()


func release() -> void:
	_touch_index = -1
	output = Vector2.ZERO
	queue_redraw()


func _update_output() -> void:
	var offset := _knob - _center
	if offset.length() > radius:
		# Drag the base along so the stick never "sticks" at the edge.
		_center = _knob - offset.normalized() * radius
		offset = _knob - _center
	output = offset / radius
	if output.length() < dead_zone:
		output = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	var to_local := get_global_transform().affine_inverse()
	var base: Vector2
	var knob: Vector2
	if _touch_index == -1:
		base = size * idle_anchor
		knob = base
	else:
		base = to_local * _center
		knob = to_local * _knob
	if pad_texture and knob_texture:
		draw_texture_rect(pad_texture, Rect2(base - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false)
		var knob_rect := Rect2(knob - Vector2(knob_radius, knob_radius), Vector2(knob_radius, knob_radius) * 2.0)
		draw_texture_rect(knob_texture, knob_rect, false)
		if _touch_index != -1 and knob_held_texture:
			draw_texture_rect(knob_held_texture, knob_rect, false)
		return
	draw_circle(base, radius, base_color)
	draw_arc(base, radius, 0.0, TAU, 48, ring_color, 3.0, true)
	draw_circle(knob, knob_radius, knob_color)
