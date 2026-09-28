class_name Minimap
extends Control
## Whole-world map: camps (red = active, grey = destroyed; bigger = more orcs), soldiers and players
## (arrows pointing where they face, in their player colors; you are white), plus everything in the "tracked" group
## (treasure goblin, Warlord, downed teammates, pings) as diamonds in their marker color.

@export var background: Color = Color(0.16, 0.3, 0.14, 0.85)
@export var grid_color: Color = Color(1, 1, 1, 0.07)
@export var camp_color: Color = Color(0.95, 0.25, 0.2)
@export var ruin_color: Color = Color(0.5, 0.5, 0.48)
@export var ally_color: Color = Color(0.35, 0.65, 1.0)
@export var player_color: Color = Color.WHITE

var _player: Node3D
var _camps: Array[Camp] = []
var _redraw_timer: float = 0.0


func setup(player: Node3D, camps: Array[Camp]) -> void:
	_player = player
	_camps = camps
	queue_redraw()


func _process(delta: float) -> void:
	_redraw_timer -= delta
	if _redraw_timer <= 0.0:
		_redraw_timer = 0.15
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var k := size.x / 160.0  # marker scale (drawn for a 160 px map)
	draw_rect(rect, background)
	# Faint quarter grid so distances read at a glance.
	for i in range(1, 4):
		var f := i / 4.0
		draw_line(Vector2(size.x * f, 0), Vector2(size.x * f, size.y), grid_color, 1.0)
		draw_line(Vector2(0, size.y * f), Vector2(size.x, size.y * f), grid_color, 1.0)
	draw_rect(rect, Color(0, 0, 0, 0.35), false, 2.0)
	for camp in _camps:
		if not is_instance_valid(camp):
			continue
		# Bigger squares = bigger squads, so players can plan their route.
		var half := (3.0 + clampf(camp.squad_size / 4.0, 0.0, 5.0)) * k
		var at := _to_map(camp.global_position)
		var box := Rect2(at - Vector2(half, half), Vector2(half, half) * 2.0)
		draw_rect(box.grow(1.5), Color(0, 0, 0, 0.55))
		draw_rect(box, ruin_color if camp.is_dead else camp_color)
		if camp.is_dead:
			draw_line(box.position, box.end, Color(0, 0, 0, 0.6), 1.5)
			draw_line(Vector2(box.end.x, box.position.y), Vector2(box.position.x, box.end.y), Color(0, 0, 0, 0.6), 1.5)
	for ally in get_tree().get_nodes_in_group(&"allies"):
		if not ally.is_inside_tree():
			continue
		var color: Color = ally.get("unit_color")
		draw_circle(_to_map((ally as Node3D).global_position), 2.2 * k, color if color.a > 0.0 else ally_color)
	for other in get_tree().get_nodes_in_group(&"players"):
		if other == _player or other.get("is_dead") or not other.is_inside_tree():
			continue
		var color: Color = other.get("unit_color")
		_draw_arrow(other as Node3D, 5.0 * k, color if color.a > 0.0 else ally_color)
	for node in get_tree().get_nodes_in_group(&"tracked"):
		var tracked := node as Node3D
		if tracked == null or not tracked.is_inside_tree():
			continue
		var at := _to_map(tracked.global_position)
		var half := (7.0 if tracked.is_in_group(&"bosses") else 5.0) * k
		draw_colored_polygon(_diamond(at, half + 1.5), Color(0, 0, 0, 0.7))
		draw_colored_polygon(_diamond(at, half), tracked.get_meta(&"marker_color", Color.WHITE))
	if is_instance_valid(_player) and _player.is_inside_tree():
		_draw_arrow(_player, 6.5 * k, player_color)


## A player as an arrow pointing where they face (dark outline).
func _draw_arrow(unit: Node3D, length: float, color: Color) -> void:
	var at := _to_map(unit.global_position)
	var facing: Vector3 = unit.call("facing") if unit.has_method("facing") else Vector3.BACK
	var dir := Vector2(facing.x, facing.z).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.DOWN
	var side := dir.orthogonal()
	var points := PackedVector2Array([at + dir * length, at - dir * length * 0.6 + side * length * 0.7,
			at - dir * length * 0.25, at - dir * length * 0.6 - side * length * 0.7])
	var outline := PackedVector2Array()
	for point in points:
		outline.append(at + (point - at) * 1.35)
	draw_colored_polygon(outline, Color(0, 0, 0, 0.65))
	draw_colored_polygon(points, color)


static func _diamond(at: Vector2, half: float) -> PackedVector2Array:
	return PackedVector2Array([at + Vector2(0, -half), at + Vector2(half, 0), at + Vector2(0, half), at + Vector2(-half, 0)])


func _to_map(world_pos: Vector3) -> Vector2:
	var span := GameConfig.world_half * 2.0
	return Vector2(
		(world_pos.x / span + 0.5) * size.x,
		(world_pos.z / span + 0.5) * size.y)
