class_name OffscreenMarkers
extends Control
## Arrows at the screen edge pointing at important 3D things that are off-screen. Put nodes in the
## group `group` (default "tracked") and give them the metas "marker_color" (Color) and
## "marker_label" (String). With `origin` set (e.g. the local player), the distance is shown too.
## Add as a full-rect child of a UI layer; it ignores the mouse.

@export var group: StringName = &"tracked"
## Distance of the arrows from the screen edge.
@export var margin: float = 56.0
@export var arrow_size: float = 18.0
@export var font_size: int = 20

var origin: Node3D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or size.x <= margin * 2.0 or size.y <= margin * 2.0:
		return
	var area := Rect2(Vector2.ZERO, size)
	var inner := area.grow(-margin)
	var center := area.size * 0.5
	var font := get_theme_default_font()
	for node in get_tree().get_nodes_in_group(group):
		var target := node as Node3D
		if target == null or not target.is_inside_tree():
			continue
		var point := target.global_position + Vector3(0, 1.0, 0)
		var behind := camera.is_position_behind(point)
		var local := camera.unproject_position(point) - global_position
		if behind:
			local = center - (local - center)  # mirrored: point the arrow the right way
		elif inner.has_point(local):
			continue
		var dir := local - center
		if dir.length() < 1.0:
			continue
		dir = dir.normalized()
		var reach_x := (inner.size.x * 0.5) / absf(dir.x) if absf(dir.x) > 0.001 else INF
		var reach_y := (inner.size.y * 0.5) / absf(dir.y) if absf(dir.y) > 0.001 else INF
		var at := center + dir * minf(reach_x, reach_y)
		var color: Color = target.get_meta(&"marker_color", Color.WHITE)
		_draw_arrow(at, dir, color)
		var text: String = target.get_meta(&"marker_label", "")
		if is_instance_valid(origin) and origin.is_inside_tree():
			text += "  %dm" % roundi(origin.global_position.distance_to(target.global_position))
		if text != "":
			# Beside the arrow, on the screen side: right-aligned at the right edge, left-aligned at the left.
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var anchor := at - dir * (arrow_size + 10.0)
			var text_at := Vector2(anchor.x - width * (0.5 + 0.5 * dir.x), anchor.y + font_size * (0.35 - 0.6 * dir.y))
			text_at.x = clampf(text_at.x, 4.0, size.x - width - 4.0)
			draw_string_outline(font, text_at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, Color(0, 0, 0, 0.85))
			draw_string(font, text_at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_arrow(at: Vector2, dir: Vector2, color: Color) -> void:
	var side := Vector2(-dir.y, dir.x)
	var tip := at + dir * arrow_size
	var back := at - dir * arrow_size * 0.6
	var outline := PackedVector2Array([tip + dir * 3.0, back + side * (arrow_size * 0.8 + 3.0) - dir * 2.0,
			back - side * (arrow_size * 0.8 + 3.0) - dir * 2.0])
	draw_colored_polygon(outline, Color(0, 0, 0, 0.8))
	draw_colored_polygon(PackedVector2Array([tip, back + side * arrow_size * 0.8, back - side * arrow_size * 0.8]), color)
