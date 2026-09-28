class_name TouchButton
extends Control
## Round on-screen button with multi-touch support (works while another finger holds the joystick).
## Poll `is_held`, or use the `pressed` / `released` signals.

signal pressed
signal released

@export var icon: Texture2D
@export var icon_scale: float = 1.6
@export var color: Color = Color(0.1, 0.1, 0.15, 0.45)
@export var held_color: Color = Color(1, 1, 1, 0.45)
@export var ring_color: Color = Color(1, 1, 1, 0.6)
## Small text drawn under the icon (e.g. ammo count).
@export var badge: String = "":
	set(value):
		badge = value
		queue_redraw()
@export var disabled: bool = false:
	set(value):
		disabled = value
		queue_redraw()

var is_held: bool = false

var _touch_index: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventScreenTouch:
		return
	var touch := event as InputEventScreenTouch
	if touch.pressed and _touch_index == -1 and _hit(touch.position):
		_touch_index = touch.index
		is_held = true
		pressed.emit()
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif not touch.pressed and touch.index == _touch_index:
		_touch_index = -1
		is_held = false
		released.emit()
		queue_redraw()


## Forgets the current touch without emitting signals (e.g. when the game pauses mid-press).
func reset() -> void:
	_touch_index = -1
	is_held = false
	queue_redraw()


func _hit(point: Vector2) -> bool:
	var rect := get_global_rect()
	# Slightly generous hit area: thumbs are imprecise.
	return rect.get_center().distance_to(point) <= minf(rect.size.x, rect.size.y) * 0.5 * 1.15


func _draw() -> void:
	var center := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	var fill := held_color if is_held else color
	if disabled:
		fill = Color(fill, fill.a * 0.5)
	draw_circle(center, r, fill)
	draw_arc(center, r - 2.0, 0.0, TAU, 48, Color(ring_color, ring_color.a * (0.4 if disabled else 1.0)), 4.0, true)
	if icon:
		var icon_size := icon.get_size() * icon_scale
		var mod := Color(1, 1, 1, 0.45) if disabled else Color.WHITE
		draw_texture_rect(icon, Rect2(center - icon_size * 0.5 - Vector2(0, r * 0.1 if badge != "" else 0.0), icon_size), false, mod)
	if badge != "":
		var font := get_theme_default_font()
		var font_size := maxi(int(r * 0.32), 16)
		var text_size := font.get_string_size(badge, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var pos := Vector2(center.x - text_size.x * 0.5, center.y + r * 0.62)
		draw_string_outline(font, pos, badge, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, Color(0, 0, 0, 0.8))
		draw_string(font, pos, badge, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
