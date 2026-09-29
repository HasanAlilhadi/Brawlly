class_name Warlord
extends Enemy
## World event boss: marches from far away toward `quarry` (a player) with a warband that grows on
## the way. Hitting it or its warband sends them all after the attacker. When it falls, its surviving
## warband is routed (they fall and drop their loot, like a destroyed camp's squad) and it spills a pile of
## coins. Spawned by WorldEvents (server).
## Fighting: prefers players over soldiers (most of all whoever is hurting it) and only switches when a
## clearly better target shows up; charges at targets a few meters away when the way is clear (so it
## can't be kited forever), stomps when foes crowd around it (sooner when surrounded), and once, at half
## health, roars for reinforcements.

## Server: the Warlord fell; `by_peer` landed the final blow.
signal defeated(warlord: Warlord, by_peer: int)
## Server: at half health it called for reinforcements.
signal rallied(warlord: Warlord)

## Its face on the minimap (rendered by tools/render_portrait.gd).
const PORTRAIT := preload("res://assets/ui/icons/portraits/warlord.png")

## Orc scenes the warband is made of (picked at random).
@export var warband_scenes: Array[PackedScene] = []
@export var warband_start: int = 6
@export var warband_max: int = 14
## Seconds between reinforcements (2 orcs each).
@export var reinforce_interval: float = 25.0
@export var stomp_interval: float = 7.0
@export var stomp_radius: float = 4.0
@export var stomp_damage: float = 22.0
@export var bounty_coins: int = 120
@export_group("Charge")
@export var charge_min_distance: float = 5.0
@export var charge_max_distance: float = 13.0
@export var charge_speed_multiplier: float = 2.6
@export var charge_time: float = 1.2
@export var charge_cooldown: float = 9.0
@export_group("Stomp")
## Seconds between stomps while at least this many foes are within stomp_radius.
@export var crowded_foes: int = 3
@export var crowded_stomp_interval: float = 4.5
@export_group("")
## Extra orcs called in at half health.
@export var rally_orcs: int = 3

## The player it marches toward (server; re-picked if they're gone).
var quarry: Node3D
## Orc stat multiplier for its warband (set by WorldEvents).
var band_strength: float = 1.0
## Replicated: a new value plays the stomp shockwave on every peer.
var stomp_seq: int = 0:
	set(value):
		if value != stomp_seq:
			stomp_seq = value
			if is_node_ready():
				_stomp_visuals()
## Replicated: a new value shows the roar (charges, rally) on every peer.
var roar_seq: int = 0:
	set(value):
		if value != roar_seq:
			roar_seq = value
			if is_node_ready():
				_roar_visuals()

var _band: Array[Enemy] = []
var _band_timer: float = 0.0
var _stomp_timer: float = 3.0
var _reinforce_timer: float = 0.0
var _title: Label3D
var _roar_label: Label3D
var _roar_tween: Tween
var _charging: float = 0.0
var _charge_timer: float = 4.0
var _rallied: bool = false
## Who hurt it recently: node -> time (ms) of their last hit.
var _attackers: Dictionary = {}


func _ready() -> void:
	super()
	add_to_group(&"bosses")
	set_meta(&"marker_color", Color(1.0, 0.3, 0.25))
	set_meta(&"marker_label", "Orc Warlord")
	set_meta(&"marker_icon", PORTRAIT)
	set_meta(&"marker_portrait", true)
	add_to_group(&"tracked")
	_reinforce_timer = reinforce_interval
	_build_title()
	_build_roar_label()


## Server: spawn the starting warband around it.
func raise_warband(count: int) -> void:
	for i in count:
		_add_band_orc()


func _add_band_orc(ignore_cap: bool = false) -> void:
	if warband_scenes.is_empty() or (_band.size() >= warband_max and not ignore_cap):
		return
	var angle := randf() * TAU
	var spot := GameConfig.clamp_to_world(global_position + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(2.5, 4.0))
	var orc := NetSpawn.unit(&"enemy", spot, {
		"scene": (warband_scenes.pick_random() as PackedScene).resource_path,
		"warlord": get_path(),
		"strength": band_strength,
		"coins": 1.5,
	}) as Enemy
	if orc == null:
		return
	orc.add_to_group(&"active_enemies")
	_band.append(orc)


## The Warlord or one of its warband was attacked: everyone hunts the attacker.
func alert(attacker: Node3D) -> void:
	provoke(attacker)
	for orc in _band:
		if is_instance_valid(orc) and not orc.is_dead:
			orc.provoke(attacker)


func _get_move_input(delta: float) -> Vector3:
	_band_timer -= delta
	if _band_timer <= 0.0:
		_band_timer = 0.5
		_lead_band()
	_reinforce_timer -= delta
	if _reinforce_timer <= 0.0:
		_reinforce_timer = reinforce_interval
		_add_band_orc()
		_add_band_orc()
	_stomp_timer -= delta
	if _stomp_timer <= 0.0:
		_stomp_timer = 1.0  # nobody close: check again soon
		var close := _foes_within(stomp_radius)
		if close > 0:
			_stomp()
			_stomp_timer = crowded_stomp_interval if close >= crowded_foes else stomp_interval
	_update_charge(delta)
	if not _rallied and health <= max_health * 0.5:
		_rally()
	return super(delta)


## Rushes at a target a few meters away when nothing is in the way.
func _update_charge(delta: float) -> void:
	_charge_timer -= delta
	if _charging > 0.0:
		_charging -= delta
		move_speed = _base_speed * (charge_speed_multiplier if _charging > 0.0 else (provoked_speed_multiplier if is_provoked() else 1.0))
		return
	if _charge_timer > 0.0 or GameConfig.is_gone(target) or _action_time > 0.0:
		return
	var dist := flat_distance_to(target)
	if dist < charge_min_distance or dist > charge_max_distance or not _clear_path_to(target):
		return
	_charging = charge_time
	_charge_timer = charge_cooldown
	roar_seq += 1


func _clear_path_to(node: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.8, 0),
			node.global_position + Vector3(0, 0.8, 0), GameConfig.LAYER_WORLD, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _rally() -> void:
	_rallied = true
	for i in rally_orcs:
		_add_band_orc(true)
	roar_seq += 1
	rallied.emit(self)


func _on_damaged(attacker: Node3D) -> void:
	if attacker:
		_attackers[attacker] = Time.get_ticks_msec()
	super(attacker)
	alert(attacker)  # even a far-away archer brings the whole warband


## Fights the best foe nearby (see `_threat_score`); keeps hunting someone who provoked it from
## range; otherwise marches on its quarry (never leashed to a home).
func _think() -> void:
	home = global_position
	var best := _best_foe()
	if best:
		var switch := GameConfig.is_gone(target) or flat_distance_to(target) > aggro_range + 5.0 \
				or (_target_lock <= 0.0 and best != target and _threat_score(best) < _threat_score(target) - 3.0)
		if switch:
			target = best
			lock_target()
		alert(target)  # the whole warband joins the fight
		return
	if is_provoked():
		if GameConfig.is_gone(target):
			_calm_down()
		else:
			return
	if GameConfig.is_gone(quarry):
		quarry = find_nearest([&"players"], INF)
	if quarry:
		_wander_point = quarry.global_position
		_returning = true  # full speed
	else:
		_returning = false


## Warband orcs keep their spot around the Warlord as it walks.
func _lead_band() -> void:
	for i in range(_band.size() - 1, -1, -1):
		if not is_instance_valid(_band[i]) or _band[i].is_dead:
			_band.remove_at(i)
	for i in _band.size():
		var angle := TAU * i / maxf(_band.size(), 1.0) + model.rotation.y
		_band[i].follow_point(global_position + Vector3(cos(angle), 0.0, sin(angle)) * 3.2)


## Lower = more worth attacking: close, a player (they lead the soldiers), hurting it right now.
func _threat_score(node: Node3D) -> float:
	var score := flat_distance_to(node)
	if node is Player:
		score -= 5.0
	if Time.get_ticks_msec() - int(_attackers.get(node, -100000)) < 5000:
		score -= 3.0
	return score


func _best_foe() -> Node3D:
	for key in _attackers.keys():
		if not is_instance_valid(key):
			_attackers.erase(key)
	var best: Node3D = null
	var best_score := INF
	for node in get_tree().get_nodes_in_group(&"player_units"):
		var foe := node as Node3D
		if GameConfig.is_gone(foe) or not GameConfig.is_hostile(self, foe) or flat_distance_to(foe) > aggro_range:
			continue
		var score := _threat_score(foe)
		if score < best_score:
			best_score = score
			best = foe
	return best


func _foes_within(distance: float) -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group(&"player_units"):
		var foe := node as Node3D
		if not GameConfig.is_gone(foe) and GameConfig.is_hostile(self, foe) and flat_distance_to(foe) < distance:
			count += 1
	return count


func _stomp() -> void:
	play_action("attack-kick-right", 0.5 / anim_speed, ARM_BOTH)
	stomp_seq += 1
	for node in get_tree().get_nodes_in_group(&"player_units"):
		var unit := node as Node3D
		if GameConfig.is_gone(unit) or not GameConfig.is_hostile(self, unit):
			continue
		if unit.global_position.distance_to(global_position) < stomp_radius:
			unit.take_damage(stomp_damage * band_strength, self, true)


## Shockwave: a ring of dirt and a camera shake for anyone near.
func _stomp_visuals() -> void:
	for i in 10:
		var angle := TAU * i / 10.0
		HitFx.burst(global_position + Vector3(cos(angle), 0.1, sin(angle)) * stomp_radius * 0.7, HitFx.Kind.WOOD, 5)
	var camera := HitFx.camera
	if is_instance_valid(camera) and camera.target and camera.target.global_position.distance_to(global_position) < stomp_radius * 3.0:
		camera.shake(0.25, 0.35)


func _on_died() -> void:
	super()
	remove_from_group(&"tracked")
	remove_from_group(&"bosses")
	_title.hide()
	if not multiplayer.is_server():
		return
	# Without their chief the warband is routed: they fall and drop their loot.
	for orc in _band:
		if is_instance_valid(orc) and not orc.is_dead:
			orc.die()
	_band.clear()
	for i in 10:
		Pickup.drop(get_parent(), global_position + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5)),
				Pickup.Kind.COIN, bounty_coins / 10)
	defeated.emit(self, last_attacker_peer)


func _roar_visuals() -> void:
	_roar_label.visible = true
	_roar_label.scale = Vector3.ONE * 0.4
	if _roar_tween:
		_roar_tween.kill()
	_roar_tween = create_tween()
	_roar_tween.tween_property(_roar_label, "scale", Vector3.ONE * 1.2, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_roar_tween.tween_interval(0.8)
	_roar_tween.tween_callback(_roar_label.hide)
	var camera := HitFx.camera
	if is_instance_valid(camera) and camera.target and camera.target.global_position.distance_to(global_position) < 14.0:
		camera.shake(0.12, 0.3)


func _build_roar_label() -> void:
	_roar_label = Label3D.new()
	_roar_label.text = "RAAAGH!"
	_roar_label.font_size = 80
	_roar_label.outline_size = 18
	_roar_label.pixel_size = 0.006
	_roar_label.modulate = Color(1.0, 0.35, 0.2)
	_roar_label.outline_modulate = Color(0.15, 0.0, 0.0, 0.95)
	_roar_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_roar_label.no_depth_test = true
	_roar_label.position = Vector3(0, health_bar_height + 0.9, 0)
	_roar_label.visible = false
	add_child(_roar_label)


func _build_title() -> void:
	_title = Label3D.new()
	_title.text = "Orc Warlord"
	_title.font_size = 64
	_title.outline_size = 16
	_title.pixel_size = 0.006
	_title.modulate = Color(1.0, 0.45, 0.35)
	_title.outline_modulate = Color(0.15, 0.0, 0.0, 0.95)
	_title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_title.no_depth_test = true
	_title.position = Vector3(0, health_bar_height + 0.35, 0)
	add_child(_title)
