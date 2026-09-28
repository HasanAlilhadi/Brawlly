class_name Minimap
extends Control
## Whole-world map: camps (red = active, grey = destroyed; bigger = more orcs), soldiers and players
## (in their player colors; you are white with a dark outline), plus everything in the "tracked" group
## (treasure goblin, Warlord, downed teammates, pings) as diamonds in their marker color.

@export var background: Color = Color(0.12, 0.22, 0.12, 0.6)
@export var camp_color: Color = Color(0.95, 0.25, 0.2)
@export var ruin_color: Color = Color(0.55, 0.55, 0.55)
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
	draw_rect(rect, background)
	draw_rect(rect, Color(1, 1, 1, 0.45), false, 2.0)
	for camp in _camps:
		if is_instance_valid(camp):
			# Bigger squares = bigger squads, so players can plan their route.
			var half := 3.0 + clampf(camp.squad_size / 4.0, 0.0, 5.0)
			draw_rect(Rect2(_to_map(camp.global_position) - Vector2(half, half), Vector2(half, half) * 2.0),
					ruin_color if camp.is_dead else camp_color)
	for ally in get_tree().get_nodes_in_group(&"allies"):
		if not ally.is_inside_tree():
			continue
		var color: Color = ally.get("unit_color")
		draw_circle(_to_map((ally as Node3D).global_position), 2.5, color if color.a > 0.0 else ally_color)
	for other in get_tree().get_nodes_in_group(&"players"):
		if other == _player or other.get("is_dead") or not other.is_inside_tree():
			continue
		var color: Color = other.get("unit_color")
		draw_circle(_to_map((other as Node3D).global_position), 4.5, Color(0, 0, 0, 0.6))
		draw_circle(_to_map((other as Node3D).global_position), 3.5, color if color.a > 0.0 else ally_color)
	for node in get_tree().get_nodes_in_group(&"tracked"):
		var tracked := node as Node3D
		if tracked == null or not tracked.is_inside_tree():
			continue
		var at := _to_map(tracked.global_position)
		var half := 7.0 if tracked.is_in_group(&"bosses") else 5.0
		draw_colored_polygon(_diamond(at, half + 1.5), Color(0, 0, 0, 0.7))
		draw_colored_polygon(_diamond(at, half), tracked.get_meta(&"marker_color", Color.WHITE))
	if is_instance_valid(_player) and _player.is_inside_tree():
		var p := _to_map(_player.global_position)
		draw_circle(p, 5.5, Color(0, 0, 0, 0.6))
		draw_circle(p, 4.0, player_color)


static func _diamond(at: Vector2, half: float) -> PackedVector2Array:
	return PackedVector2Array([at + Vector2(0, -half), at + Vector2(half, 0), at + Vector2(0, half), at + Vector2(-half, 0)])


func _to_map(world_pos: Vector3) -> Vector2:
	var span := GameConfig.world_half * 2.0
	return Vector2(
		(world_pos.x / span + 0.5) * size.x,
		(world_pos.z / span + 0.5) * size.y)
