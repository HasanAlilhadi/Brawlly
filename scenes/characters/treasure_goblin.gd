class_name TreasureGoblin
extends Unit
## World event: a golden goblin with a fist full of coins. It runs from anyone who comes close (fast
## sprints with short rests to catch its breath), spills coins with every hit, drops a jackpot when
## caught and escapes if nobody catches it in time. Spawned by WorldEvents (server).

## Server: the goblin is gone — `caught` by `by_peer`, or it escaped.
signal finished(goblin: TreasureGoblin, caught: bool, by_peer: int)

const TARGET_GROUPS: Array[StringName] = [&"player_units"]
const TAUNTS: PackedStringArray = ["Hehehe!", "Too slow!", "Catch me!", "Mine, mine!", "Nyah nyah!", "Shiny!"]

@export var flee_range: float = 9.0
@export var flee_speed: float = 4.7
@export var wander_speed: float = 2.0
## Seconds of sprinting before it has to catch its breath, and how long it rests.
@export var sprint_time: float = 2.6
@export var rest_time: float = 1.2
@export var rest_speed: float = 0.9
## Seconds before it escapes.
@export var lifetime: float = 55.0
@export var coins_per_hit_min: int = 2
@export var coins_per_hit_max: int = 4
@export var jackpot_coins: int = 45
@export_range(0.0, 1.0) var taunt_chance: float = 0.35

## Replicated: a new value shows a speech bubble on every peer.
var taunt_seq: int = 0:
	set(value):
		if value != taunt_seq:
			taunt_seq = value
			if is_node_ready():
				_show_taunt()

var _age: float = 0.0
var _think_timer: float = 0.0
var _stamina: float = 0.0
var _resting: float = 0.0
var _threat: Node3D
var _wander_point: Vector3
var _escaping: bool = false
var _bubble: Label3D
var _bubble_tween: Tween


func _ready() -> void:
	super()
	add_to_group(&"goblins")
	add_to_group(&"active_enemies")
	set_meta(&"marker_color", Color(1.0, 0.82, 0.2))
	set_meta(&"marker_label", "Treasure Goblin")
	add_to_group(&"tracked")
	_stamina = sprint_time
	_wander_point = global_position
	_build_bubble()


func _get_move_input(delta: float) -> Vector3:
	_age += delta
	if _age > lifetime:
		_escape()
		return Vector3.ZERO
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = 0.2
		_threat = find_nearest(TARGET_GROUPS, flee_range)
		if _threat == null and (global_position.distance_to(_wander_point) < 0.6 or randf() < 0.05):
			var angle := randf() * TAU
			_wander_point = GameConfig.clamp_to_world(global_position + Vector3(cos(angle), 0.0, sin(angle)) * 6.0)
	if _resting > 0.0:
		_resting -= delta
		move_speed = rest_speed
		if _resting <= 0.0:
			_stamina = sprint_time
	if _threat == null:
		if _resting <= 0.0:
			move_speed = wander_speed
		var to := _wander_point - global_position
		to.y = 0.0
		return steer(to.normalized() * 0.6, delta) if to.length() > 0.3 else Vector3.ZERO
	if _resting <= 0.0:
		move_speed = flee_speed
		_stamina -= delta
		if _stamina <= 0.0:
			_resting = rest_time
			if randf() < 0.5:
				taunt_seq += 1
	return steer(_flee_direction(), delta)


## Away from the threat, bending along the world edge instead of running into it.
func _flee_direction() -> Vector3:
	var away := global_position - _threat.global_position
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 0.001 else Vector3.FORWARD
	var ahead := global_position + away * 6.0
	var edge := GameConfig.world_half - 4.0
	if absf(ahead.x) > edge:
		away.x *= -0.3
		away.z += signf(away.z if away.z != 0.0 else 1.0)
	if absf(ahead.z) > edge:
		away.z *= -0.3
		away.x += signf(away.x if away.x != 0.0 else 1.0)
	return away.normalized()


func _on_damaged(_attacker: Node3D) -> void:
	if not multiplayer.is_server() or is_dead:
		return
	Pickup.drop(get_parent(), global_position, Pickup.Kind.COIN, randi_range(coins_per_hit_min, coins_per_hit_max))
	_resting = 0.0
	_stamina = sprint_time  # a hit gives it a burst of panic
	if randf() < taunt_chance:
		taunt_seq += 1


func _on_died() -> void:
	remove_from_group(&"tracked")
	remove_from_group(&"active_enemies")
	if not multiplayer.is_server():
		return
	var players := get_tree().get_nodes_in_group(&"players").size()
	var total := roundi(jackpot_coins * (1.0 + 0.25 * (players - 1)))
	for i in 6:
		Pickup.drop(get_parent(), global_position, Pickup.Kind.COIN, total / 6 + (1 if i < total % 6 else 0))
	Pickup.drop(get_parent(), global_position, Pickup.Kind.HEALTH, 40)
	Pickup.drop(get_parent(), global_position, Pickup.Kind.ARROWS, 8)
	Pickup.drop(get_parent(), global_position, Pickup.Kind.SPEARS, 3)
	finished.emit(self, true, last_attacker_peer)


func _escape() -> void:
	if _escaping or not multiplayer.is_server():
		return
	_escaping = true
	_net_poof.rpc()
	finished.emit(self, false, 0)
	get_tree().create_timer(0.35).timeout.connect(queue_free)


@rpc("authority", "call_local", "reliable")
func _net_poof() -> void:
	HitFx.burst(global_position + Vector3(0, 0.5, 0), HitFx.Kind.LEAVES, 16)
	remove_from_group(&"tracked")
	model.hide()
	_health_bar.hide()


func _build_bubble() -> void:
	_bubble = Label3D.new()
	_bubble.font_size = 52
	_bubble.outline_size = 12
	_bubble.pixel_size = 0.006
	_bubble.modulate = Color(1.0, 0.9, 0.35)
	_bubble.outline_modulate = Color(0.25, 0.12, 0.0, 0.95)
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.no_depth_test = true
	_bubble.position = Vector3(0, health_bar_height + 0.3, 0)
	_bubble.visible = false
	add_child(_bubble)


func _show_taunt() -> void:
	_bubble.text = TAUNTS[taunt_seq % TAUNTS.size()]
	_bubble.visible = true
	_bubble.scale = Vector3.ONE * 0.3
	if _bubble_tween:
		_bubble_tween.kill()
	_bubble_tween = create_tween()
	_bubble_tween.tween_property(_bubble, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_bubble_tween.tween_interval(1.2)
	_bubble_tween.tween_callback(_bubble.hide)
