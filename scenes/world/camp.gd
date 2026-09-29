class_name Camp
extends StaticBody3D
## Orc camp: a tent for small squads (≤ `tent_max_squad`), a house for bigger ones. Spawns a squad of orcs (arranged in rings around the house) and respawns each one
## some time after it dies. Bigger squads get a bigger, tougher house.
## Attacking the camp or any of its orcs (even from range) sends the whole squad after the attacker.
## Destroying the house stops the spawning; the surviving orcs are routed (they fall and drop their
## loot) and the house spills coins.
## Far-away squads are paused to keep the big world cheap on mobile.
##
## Multiplayer: every peer builds the same camps (same names) from the shared seed; only the server
## spawns orcs and runs the logic, clients get health / alive count / destruction via RPC.

signal destroyed(camp: Camp)

const BASE_RADIUS: float = 1.1
const TENT_RADIUS: float = 1.2
const ORC_ICON := preload("res://assets/ui/icons/orc.png")

## What the squad is made of (see resources/data/orc_roster.tres).
@export var roster: EnemyRoster
@export var base_health: float = 250.0
@export var health_per_orc: float = 30.0
## Extra house health per inner-ring guard (giants).
@export var health_per_giant: float = 150.0
## Respawn delay at tier 0 (near the start) and tier 1 (far edges).
@export var respawn_delay_easy: float = 15.0
@export var respawn_delay_hard: float = 9.0
## Orc health/damage multiplier at tier 0 and tier 1 (times the match difficulty).
@export var weak_stat_multiplier: float = 0.75
@export var strong_stat_multiplier: float = 1.35
## No respawns until the camp (or its orcs) has been left alone this long.
@export var calm_before_respawn: float = 8.0
## Coins spilled when the house is destroyed: base + per orc.
@export var coin_bounty_base: int = 15
@export var coin_bounty_per_orc: int = 4
## Orcs are only simulated while a player is within this distance.
@export var activation_range: float = 32.0
## Squads up to this size live in a tent instead of a house.
@export var tent_max_squad: int = 7

## Set before adding to the tree.
var squad_size: int = 3
## 0 = near a spawn (easy) … 1 = far away (hard).
var tier: float = 0.0
## Orcs are their own team.
var team_id: int = GameConfig.ORC_TEAM
var respawn_delay: float = 10.0
var max_health: float
var health: float
var is_dead: bool = false
## Distance from the center to the house walls (used by attackers).
var radius: float = BASE_RADIUS
## Orcs alive (server counts; clients receive it).
var alive: int = 0

var _squad: Array[Enemy] = []
var _spawn_points: Array[Vector3] = []
var _slot_scenes: Array[PackedScene] = []
var _respawn_timers: Array[float] = []
var _active: bool = false
var _check_timer: float = 0.0
var _health_bar: HealthBar3D
var _strength_label: Label3D
var _strength_icon: Sprite3D
var _shake_tween: Tween
var _last_attacked_ms: int = -100000
var _last_hit_peer: int = 0
var _hit_times: Dictionary = {}  # peer -> last hit time (ms)
var _sync_timer: float = 0.0
var _started: bool = false

@onready var _house: Node3D = $House
@onready var _ruins: Node3D = $Ruins
## Height of the health bar / orc counter over the building.
var _marker_height: float = 3.6


## House scale for a squad size: small camps 1.0, big ones up to 1.45.
static func scale_for_squad(size: int) -> float:
	return 1.0 + clampf((size - 5) / 20.0, 0.0, 1.0) * 0.45


func _ready() -> void:
	_slot_scenes = roster.compose(squad_size)
	var inner := 0
	for entry in roster.entries:
		if entry.inner_ring:
			inner += entry.count_for(squad_size)
	max_health = base_health + health_per_orc * squad_size + health_per_giant * inner
	health = max_health
	if squad_size <= tent_max_squad:
		_use_tent()
	respawn_delay = lerpf(respawn_delay_easy, respawn_delay_hard, tier) * GameConfig.orc_respawn_scale
	radius = (TENT_RADIUS if _house == $Tent else BASE_RADIUS) * scale.x
	alive = squad_size
	add_to_group(&"camps")
	_ruins.visible = false
	_health_bar = HealthBar3D.new()
	_health_bar.width = 1.4
	_health_bar.height = 0.12
	_health_bar.fill_color = Color(0.95, 0.55, 0.15)
	_health_bar.position = Vector3(0, _marker_height, 0)
	add_child(_health_bar)
	_build_strength_marker()
	_squad.resize(squad_size)
	_respawn_timers.resize(squad_size)
	_spawn_points = _ring_points(squad_size)
	_check_timer = randf() * 0.5


## Small squad: a tent (lower, a bit wider) replaces the house, with a matching collision box.
func _use_tent() -> void:
	$House.hide()
	_house = $Tent
	_house.show()
	var box := BoxShape3D.new()
	box.size = Vector3(2.3, 1.8, 2.0)
	var collision := $CollisionShape3D as CollisionShape3D
	collision.shape = box
	collision.position.y = 0.9
	_marker_height = 2.6


## Server: spawn the squad (called by main when the match starts).
func start() -> void:
	if _started or not multiplayer.is_server():
		return
	_started = true
	for i in squad_size:
		_spawn(i)
	_set_active(_is_player_near())


## Spawn spots in rings around the house (bigger squads get more rings).
func _ring_points(count: int) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var ring := 0
	while points.size() < count:
		var ring_radius := radius + 1.3 + ring * 0.9
		var capacity := floori(TAU * ring_radius / 0.95)
		var in_ring := mini(capacity, count - points.size())
		var start_angle := randf() * TAU
		for i in in_ring:
			var angle := start_angle + TAU * i / in_ring
			points.append(global_position + Vector3(cos(angle), 0.0, sin(angle)) * ring_radius)
		ring += 1
	return points


func _physics_process(delta: float) -> void:
	if not _started:
		return
	_check_timer -= delta
	if _check_timer <= 0.0:
		_check_timer = 0.5
		_set_active(_is_player_near())
	_sync_timer -= delta
	if _sync_timer <= 0.0 and not is_dead:
		_sync_timer = 0.25
		if Net.is_online():
			_net_state.rpc(health, alive)
	if is_dead or not _active:
		return
	if Time.get_ticks_msec() - _last_attacked_ms < calm_before_respawn * 1000.0:
		return  # under attack: fallen orcs stay down so the camp can be cleared
	for i in squad_size:
		if _squad[i] == null and _respawn_timers[i] > 0.0:
			_respawn_timers[i] -= delta
			if _respawn_timers[i] <= 0.0:
				_spawn(i)


func _spawn(slot: int) -> void:
	var spawn_pos := _spawn_points[slot] + Vector3(randf_range(-0.2, 0.2), 0.0, randf_range(-0.2, 0.2))
	var strength := lerpf(weak_stat_multiplier, strong_stat_multiplier, tier) * GameConfig.orc_strength
	var enemy := NetSpawn.unit(&"enemy", spawn_pos, {
		"scene": _slot_scenes[slot].resource_path,
		"camp": get_path(),
		"strength": strength,
		"coins": 1.0 + tier,
	}) as Enemy
	if enemy == null:
		return
	enemy.died.connect(_on_enemy_died.bind(slot))
	_squad[slot] = enemy
	_apply_run_state(enemy, _active)
	_update_alive()


func _on_enemy_died(_unit: Unit, slot: int) -> void:
	_squad[slot] = null
	_respawn_timers[slot] = respawn_delay
	_update_alive()


func _update_alive() -> void:
	var count := 0
	for enemy in _squad:
		if enemy and not enemy.is_dead:
			count += 1
	alive = count
	_update_strength()


## Downed players still count (only `is_dead` doesn't), or their orcs would freeze mid-fight.
func _is_player_near() -> bool:
	for node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if is_instance_valid(player) and not player.is_dead and global_position.distance_to(player.global_position) < activation_range:
			return true
	return false


## Pauses orcs while players are far away, except orcs chasing someone or walking home.
func _set_active(active: bool) -> void:
	_active = active
	for enemy in _squad:
		if enemy:
			_apply_run_state(enemy, active or enemy.is_busy())


## Running orcs think and are targetable ("active_enemies"); paused ones cost nothing.
func _apply_run_state(enemy: Enemy, run: bool) -> void:
	enemy.process_mode = Node.PROCESS_MODE_INHERIT if run else Node.PROCESS_MODE_DISABLED
	if run:
		enemy.add_to_group(&"active_enemies")
	else:
		enemy.remove_from_group(&"active_enemies")


## True if `peer` (or their soldiers) hit this camp within the last `seconds`.
func attacked_recently_by(peer: int, seconds: float = 5.0) -> bool:
	return Time.get_ticks_msec() - int(_hit_times.get(peer, -100000)) < seconds * 1000.0


## The camp or one of its orcs was attacked: the whole squad hunts the attacker.
func alert(attacker: Node3D) -> void:
	if is_dead or GameConfig.is_gone(attacker):
		return
	_last_attacked_ms = Time.get_ticks_msec()
	for enemy in _squad:
		if enemy and not enemy.is_dead:
			enemy.provoke(attacker)
	_set_active(_active)


func take_damage(amount: float, attacker: Node3D = null, is_melee: bool = true, crit: bool = false) -> void:
	if is_dead or not multiplayer.is_server():
		return
	HitFx.report_hit(self, minf(amount, health), attacker, crit, is_melee)
	alert(attacker)
	var peer := GameConfig.owner_peer_of(attacker)
	if peer != 0:
		_last_hit_peer = peer
		_hit_times[peer] = Time.get_ticks_msec()
	health = maxf(health - amount, 0.0)
	_show_health()
	if health <= 0.0:
		_destroy()


func _destroy() -> void:
	# Without their camp the surviving orcs are routed: they fall and drop their loot (soldiers are
	# bought at the barracks, not won here).
	for enemy in _squad:
		if enemy and not enemy.is_dead:
			enemy.die()
	_squad.fill(null)
	MatchStats.add(_last_hit_peer, &"camps")
	_spill_bounty()
	_net_destroyed.rpc(_last_hit_peer)


func _player_by_peer(peer: int) -> Player:
	for player in get_tree().get_nodes_in_group(&"players"):
		if (player as Player).peer_id == peer:
			return player
	return null


func _spill_bounty() -> void:
	var total := coin_bounty_base + coin_bounty_per_orc * squad_size
	var piles := clampi(total / 10, 3, 8)
	for i in piles:
		Pickup.drop(get_parent(), global_position + Vector3(randf_range(-1.5, 1.5), 0, radius + 1.0),
				Pickup.Kind.COIN, total / piles + (1 if i < total % piles else 0))


# --- Visuals / replication ----------------------------------------------------------

@rpc("authority", "call_remote", "unreliable_ordered")
func _net_state(new_health: float, new_alive: int) -> void:
	if new_health < health:
		_shake()
	health = new_health
	alive = new_alive
	_health_bar.set_ratio(health / max_health)
	_update_strength()


## Destruction on every peer (visuals, groups, `destroyed` signal). `by_peer` = who destroyed it.
@rpc("authority", "call_local", "reliable")
func _net_destroyed(by_peer: int) -> void:
	if is_dead:
		return
	is_dead = true
	health = 0.0
	alive = 0
	_last_hit_peer = by_peer
	collision_layer = 0
	_health_bar.hide()
	_strength_label.hide()
	HitFx.flash(global_position + Vector3(0, 1.0, 0), HitFx.BIG_SMOKE, Color(0.9, 0.85, 0.75, 0.9), 3.5 * scale.x, 0.9, Vector2(0.4, 1.5), false)
	_strength_icon.hide()
	var tween := create_tween()
	tween.tween_property(_house, "scale", Vector3(1.2, 0.05, 1.2), 0.35).set_ease(Tween.EASE_IN)
	tween.tween_callback(_house.hide)
	tween.tween_callback(_ruins.show)
	destroyed.emit(self)


## Peer who destroyed this camp (valid after `destroyed`).
func destroyed_by() -> int:
	return _last_hit_peer


func _show_health() -> void:
	_health_bar.set_ratio(health / max_health)
	_shake()


func _shake() -> void:
	HitFx.burst(global_position + Vector3(randf_range(-0.6, 0.6), 1.4 * scale.y, radius * 0.8), HitFx.Kind.WOOD, 8)
	if _shake_tween:
		_shake_tween.kill()
	_house.scale = Vector3(1.08, 0.94, 1.08)
	_shake_tween = create_tween()
	_shake_tween.tween_property(_house, "scale", Vector3.ONE, 0.18)


## Orc icon + number of orcs alive, floating over the roof so players can pick their fights.
func _build_strength_marker() -> void:
	var height := (_marker_height + 0.5) / scale.y
	_strength_icon = Sprite3D.new()
	_strength_icon.texture = ORC_ICON
	_strength_icon.pixel_size = 0.012 / scale.x
	_strength_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_strength_icon.no_depth_test = true
	_strength_icon.position = Vector3(-0.35 / scale.x, height, 0)
	add_child(_strength_icon)
	_strength_label = Label3D.new()
	_strength_label.font_size = 72
	_strength_label.outline_size = 16
	_strength_label.pixel_size = 0.006 / scale.x
	_strength_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_strength_label.no_depth_test = true
	_strength_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_strength_label.position = Vector3(0.05 / scale.x, height, 0)
	add_child(_strength_label)
	_update_strength()


func _update_strength() -> void:
	if _strength_label:
		_strength_label.text = str(alive)
