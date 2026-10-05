class_name Minimap
extends Control
## Whole-world map. Shows only what the local player's side may know:
## - objectives: the King of the Hill zone (holder's color, pulses while contested), the Last Stand circle
##   (its state color, the held share as an arc)
## - gold veins with gold left as small gold dots
## - camps as tent badges (red = active, bigger = more orcs; grey + cross = destroyed)
## - friends only: teammates as arrows pointing where they face (their player colors; you are white) and
##   friendly soldiers as dots. Hostile players and their soldiers are never drawn (versus modes).
## - everything in the "tracked" group (treasure goblin, Warlord, downed teammates, pings): a round badge
##   with the `marker_icon` meta (Texture2D) when set, else a diamond, in its `marker_color`. Bosses pulse.
## The map turns with the camera (`FollowCamera3D.view_yaw()`), so up on the map is always up on screen.

const TENT_ICON := preload("res://assets/ui/icons/game/tent.svg")
const CROWN_ICON := preload("res://assets/ui/icons/game/crown.svg")
const OUTLINE := Color(0, 0, 0, 0.7)

## Set from the map (MapCatalog `minimap`).
@export var background: Color = Color(0.16, 0.3, 0.14, 0.85)
@export var vein_color: Color = Color(1.0, 0.82, 0.25)
@export var grid_color: Color = Color(1, 1, 1, 0.07)
@export var camp_color: Color = Color(0.85, 0.22, 0.18)
@export var ruin_color: Color = Color(0.42, 0.42, 0.4)
@export var ally_color: Color = Color(0.35, 0.65, 1.0)
@export var player_color: Color = Color.WHITE

var _player: Node3D
var _camps: Array[Camp] = []
var _redraw_timer: float = 0.0
var _time: float = 0.0
## Camera turn the map is drawn for (radians).
var _view_yaw: float = 0.0


func setup(player: Node3D, camps: Array[Camp]) -> void:
	clip_contents = true  # mid-turn the rotated world square pokes out of the frame
	_player = player
	_camps = camps
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	_redraw_timer -= delta
	# Redraw every frame while the camera turns, else 10×/s.
	if _redraw_timer <= 0.0 or not is_equal_approx(_camera_yaw(), _view_yaw):
		_redraw_timer = 0.1
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var k := size.x / 160.0  # marker scale (drawn for a 160 px map)
	_view_yaw = _camera_yaw()
	draw_rect(rect, background)
	# Faint quarter grid so distances read at a glance.
	var half := GameConfig.world_half
	for i in range(1, 4):
		var f := (i / 4.0 * 2.0 - 1.0) * half
		draw_line(_to_map(Vector3(f, 0, -half)), _to_map(Vector3(f, 0, half)), grid_color, 1.0)
		draw_line(_to_map(Vector3(-half, 0, f)), _to_map(Vector3(half, 0, f)), grid_color, 1.0)
	_draw_hill(k)
	_draw_hold_circles(k)
	for vein in get_tree().get_nodes_in_group(&"gold_veins"):
		if (vein as GoldVein).gold > 0:
			var spot := _to_map((vein as Node3D).global_position)
			draw_circle(spot, 2.2 * k, OUTLINE)
			draw_circle(spot, 1.5 * k, vein_color)
	for camp in _camps:
		if is_instance_valid(camp):
			_draw_camp(camp, k)
	for ally in get_tree().get_nodes_in_group(&"allies"):
		if not ally.is_inside_tree() or not _is_friend(ally):
			continue
		var color: Color = ally.get("unit_color")
		var at := _to_map((ally as Node3D).global_position)
		draw_circle(at, 2.6 * k, OUTLINE)
		draw_circle(at, 1.9 * k, color if color.a > 0.0 else ally_color)
	for other in get_tree().get_nodes_in_group(&"players"):
		if other == _player or other.get("is_dead") or not other.is_inside_tree() or not _is_friend(other):
			continue
		var color: Color = other.get("unit_color")
		_draw_arrow(other as Node3D, 5.0 * k, color if color.a > 0.0 else ally_color)
	for node in get_tree().get_nodes_in_group(&"tracked"):
		var tracked := node as Node3D
		if tracked and tracked.is_inside_tree():
			_draw_tracked(tracked, k)
	if is_instance_valid(_player) and _player.is_inside_tree():
		# You: a soft halo so the arrow stands out on top of badges.
		draw_circle(_to_map(_player.global_position), 7.5 * k, Color(1, 1, 1, 0.22))
		_draw_arrow(_player, 6.5 * k, player_color)
	draw_rect(rect, Color(0, 0, 0, 0.35), false, 2.0)


## Teammates / our soldiers (and everyone before the local player exists).
func _is_friend(unit: Node) -> bool:
	return not is_instance_valid(_player) or not GameConfig.is_hostile(_player, unit)


# --- Objectives ------------------------------------------------------------------

## King of the Hill: the zone at its real size (never smaller than a badge), in the holder's color.
func _draw_hill(k: float) -> void:
	var hill := get_tree().get_first_node_in_group(&"hill") as Hill
	if hill == null:
		return
	var at := _to_map(hill.global_position)
	var radius := maxf(Hill.RADIUS / (GameConfig.world_half * 2.0) * size.x, 9.0 * k)
	var color := Hill.NEUTRAL
	if hill.holder == -2:
		color = Hill.CONTESTED
	elif hill.holder >= 0:
		color = Net.team_color(hill.holder)
	if hill.holder == -2:
		# Contested: a ring pulses outward.
		var pulse := fmod(_time * 1.5, 1.0)
		draw_arc(at, radius * (1.0 + pulse * 0.6), 0.0, TAU, 40, Color(color, 0.8 * (1.0 - pulse)), 2.0 * k)
	draw_circle(at, radius, Color(color, 0.3))
	draw_arc(at, radius, 0.0, TAU, 40, OUTLINE, 3.2 * k)
	draw_arc(at, radius, 0.0, TAU, 40, color, 1.8 * k)
	_draw_icon(at, radius * 1.1, CROWN_ICON, Color(color, 0.95))


## Last Stand: the circle at its real size in its state color, the held share as a bright arc.
func _draw_hold_circles(k: float) -> void:
	for node in get_tree().get_nodes_in_group(&"hold_circles"):
		var circle := node as HoldCircle
		var at := _to_map(circle.global_position)
		var radius := maxf(HoldCircle.RADIUS / (GameConfig.world_half * 2.0) * size.x, 8.0 * k)
		var color := circle.state_color()
		draw_circle(at, radius, Color(color, 0.28))
		draw_arc(at, radius, 0.0, TAU, 40, OUTLINE, 3.2 * k)
		draw_arc(at, radius, 0.0, TAU, 40, Color(color, 0.7), 1.6 * k)
		if circle.progress > 0.0:
			var start := -PI * 0.5 + _view_yaw
			draw_arc(at, radius, start, start + TAU * circle.progress, 40, color.lightened(0.35), 3.0 * k)


# --- Camps / posts -----------------------------------------------------------------

## A tent badge: bigger = bigger squad, so players can plan their route; ruins are small, grey and crossed.
func _draw_camp(camp: Camp, k: float) -> void:
	var at := _to_map(camp.global_position)
	if camp.is_dead:
		var half := 2.8 * k
		_draw_badge(at, half, ruin_color, TENT_ICON, Color(1, 1, 1, 0.45))
		var cross := Color(0, 0, 0, 0.6)
		draw_line(at + Vector2(-half, -half) * 0.7, at + Vector2(half, half) * 0.7, cross, 1.5 * k)
		draw_line(at + Vector2(half, -half) * 0.7, at + Vector2(-half, half) * 0.7, cross, 1.5 * k)
		return
	_draw_badge(at, (3.2 + clampf(camp.squad_size / 5.0, 0.0, 2.8)) * k, camp_color, TENT_ICON)


# --- Tracked ------------------------------------------------------------------------

func _draw_tracked(tracked: Node3D, k: float) -> void:
	var at := _to_map(tracked.global_position)
	var color: Color = tracked.get_meta(&"marker_color", Color.WHITE)
	var boss := tracked.is_in_group(&"bosses")
	var half := (10.0 if boss else 5.5) * k
	if boss or tracked.is_in_group(&"pings"):
		var pulse := fmod(_time * (0.9 if boss else 1.6), 1.0)
		draw_arc(at, half * (1.1 + pulse * 0.8), 0.0, TAU, 32, Color(color, 0.9 * (1.0 - pulse)), 1.8 * k)
	var icon: Texture2D = tracked.get_meta(&"marker_icon") if tracked.has_meta(&"marker_icon") else null
	if icon == null:
		draw_colored_polygon(_diamond(at, half * 0.85 + 1.5), OUTLINE)
		draw_colored_polygon(_diamond(at, half * 0.85), color)
	elif tracked.get_meta(&"marker_portrait", false):
		# A face: the (round) portrait fills the badge, ringed in the marker color.
		draw_circle(at, half + 1.2 * k, OUTLINE)
		draw_circle(at, half, color)
		draw_circle(at, half - 1.4 * k, Color(0.12, 0.1, 0.08))
		draw_texture_rect(icon, Rect2(at - Vector2.ONE * (half - 1.4 * k), Vector2.ONE * (half - 1.4 * k) * 2.0), false)
	else:
		_draw_badge(at, half, color, icon)


# --- Shapes ------------------------------------------------------------------------

## A colored disc with a dark outline and a white glyph (Game Icon Pack) on top.
func _draw_badge(at: Vector2, radius: float, color: Color, icon: Texture2D, icon_color: Color = Color.WHITE) -> void:
	draw_circle(at, radius + 1.3, OUTLINE)
	draw_circle(at, radius, color)
	_draw_icon(at, radius * 1.25, icon, icon_color)


func _draw_icon(at: Vector2, icon_size: float, icon: Texture2D, color: Color) -> void:
	draw_texture_rect(icon, Rect2(at - Vector2.ONE * icon_size * 0.5, Vector2.ONE * icon_size), false, color)


## A player as an arrow pointing where they face (dark outline).
func _draw_arrow(unit: Node3D, length: float, color: Color) -> void:
	var at := _to_map(unit.global_position)
	var facing: Vector3 = unit.call("facing") if unit.has_method("facing") else Vector3.BACK
	var dir := Vector2(facing.x, facing.z).normalized().rotated(_view_yaw)
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


## World position → map pixel, turned with the camera (the world is centered on the origin).
func _to_map(world_pos: Vector3) -> Vector2:
	var span := GameConfig.world_half * 2.0
	var flat := Vector2(world_pos.x, world_pos.z).rotated(_view_yaw) / span
	return (flat + Vector2(0.5, 0.5)) * size


func _camera_yaw() -> float:
	var camera := get_viewport().get_camera_3d() as FollowCamera3D
	return camera.view_yaw() if camera else 0.0
