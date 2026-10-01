class_name Unit
extends CharacterBody3D
## Base for every character (player, orcs, soldiers): health, movement, animation,
## melee attacks, weapons in hands, teams and network sync.
## Subclasses override `_get_move_input()` (and optionally `_can_hit()`, `_on_died()`).
##
## Multiplayer: the server (host) runs all gameplay. The `Sync` child (MultiplayerSynchronizer)
## replicates net_position / net_yaw / health / anim_state / action_token / is_dead; other peers
## only interpolate and play animations (`_is_remote()`).

signal health_changed(current: float, maximum: float)
signal died(unit: Unit)

const LOOPING_ANIMS: Array[String] = ["idle", "walk", "sprint"]
## Directions tried (radians from the desired one, + = the side we're already going around) when the way
## ahead is blocked. Our own side is tried up to 90° before switching sides, so a unit walks along a wide
## obstacle (a wall of orcs, a house) instead of flip-flopping in front of it.
const STEER_ANGLES: Array[float] = [0.0, 0.4, -0.4, 0.8, -0.8, 1.2, 1.6, -1.2, -1.6, 2.1, -2.1, 2.6, -2.6]
const STEER_INTERVAL: float = 0.15
## Target stickiness: after picking a target, keep it at least this long, and only switch to one that
## is much closer (at most this fraction of the current distance). Stops AI flip-flopping.
const TARGET_LOCK_TIME: float = 2.5
const TARGET_SWITCH_RATIO: float = 0.5
## Above raised walkable details such as the town compass mosaic (top: 0.037 m).
const COLOR_RING_HEIGHT: float = 0.06
const ARM_RIGHT: int = 1
const ARM_LEFT: int = 2
const ARM_BOTH: int = 3

@export var max_health: float = 100.0
@export var move_speed: float = 3.5
@export var melee_damage: float = 20.0
## Reach of a melee swing, measured from the unit's center.
@export var melee_range: float = 1.0
@export var melee_cooldown: float = 0.8
## Seconds from the start of the swing to the moment damage lands (at anim_speed 1).
@export var attack_hit_delay: float = 0.24
## Attack animations, used in turn (e.g. alternate left/right punches).
@export var melee_anims: PackedStringArray = PackedStringArray(["attack-melee-right"])
## Body radius (attackers stand this far from the center, plus their reach).
@export var radius: float = 0.35
## Animation playback speed (big, slow creatures < 1).
@export var anim_speed: float = 1.0
## If true, a swing damages everything in front (giants); otherwise only one target.
@export var melee_cleave: bool = false
## Physics layers a melee swing can hit.
@export_flags_3d_physics var melee_mask: int = 0
@export_group("Hands")
@export var right_hand_item: PackedScene
## Carry grip: used while the arm is held in the "holding-right" pose (weapon upright in front).
@export var right_hand_offset: Vector3 = Vector3(-0.27, 0.0, 0.0)
@export var right_hand_rotation: Vector3 = Vector3.ZERO
## Swing grip: weapon in line with the (single-bone) arm so it follows the melee swing.
@export var right_swing_offset: Vector3 = Vector3(-0.25, 0.0, 0.0)
@export var right_swing_rotation: Vector3 = Vector3(0.0, 0.0, 90.0)
## Keep the right arm in the holding pose except while attacking.
@export var hold_right_arm: bool = true
@export var left_hand_item: PackedScene
@export var left_hand_offset: Vector3 = Vector3(0.27, 0.0, 0.0)
@export var left_hand_rotation: Vector3 = Vector3.ZERO
## Keep the left arm in the holding pose except during actions that release it.
@export var hold_left_arm: bool = false
@export_group("")
@export var health_bar_color: Color = Color(0.9, 0.22, 0.2)
@export_group("Player color")
## Palette hue recolored to the player's color (-1 = no recolor, only the ring under the unit).
@export_range(-1.0, 1.0) var recolor_key_hue: float = -1.0
@export var recolor_hue_range: float = 0.03
@export var recolor_min_saturation: float = 0.6
@export var recolor_reference_value: float = 0.95
@export_group("")
@export var health_bar_height: float = 1.3
@export var health_bar_width: float = 0.7
## Seconds the health bar stays visible after a hit (0 = while damaged).
@export var health_bar_hide_delay: float = 2.5
## Run animation above this fraction of move_speed, walk below it.
@export var sprint_threshold: float = 0.65
@export var free_on_death: bool = true
## How far hits push this unit (0 = not at all; giants barely move).
@export var knockback_taken: float = 1.0
## Health regained per second after `regen_delay` seconds without taking damage (0 = off).
@export var regen_per_second: float = 0.0
@export var regen_delay: float = 5.0
@export_group("Steering")
## How far ahead AI units look for obstacles (trees, houses).
@export var steer_lookahead: float = 1.3
## Extra physics layers `engage()` steers around while still chasing its target (not yet close), e.g.
## soldiers go around orcs in the way instead of getting tangled in (and fighting) them. 0 = only
## trees / houses / walls.
@export_flags_3d_physics var chase_avoid_mask: int = 0
## Push away from same-side units closer than this (stops them stacking in a line).
@export var separation_radius: float = 0.75
@export var separation_strength: float = 0.9

## Team: GameConfig.ORC_TEAM for orcs; players and their soldiers share their player's team.
var team_id: int = GameConfig.ORC_TEAM
## Peer id of the controlling player (players and their soldiers); 0 for orcs.
var owner_peer: int = 0
## Player color (ring under the unit + light tint). Alpha 0 = no color.
var unit_color: Color = Color(1, 1, 1, 0)
## Peer who last damaged this unit (kill credit).
var last_attacker_peer: int = 0

# --- Replicated state (see the Sync node) ---
var net_position: Vector3
var net_yaw: float
var anim_state: String = "":
	set(value):
		anim_state = value
		if _is_remote() and is_node_ready() and not _full_body_busy() and not is_predicted:
			play_anim(value)
## "anim|sequence|arms" — a new sequence number makes remote peers replay the action.
var action_token: String = "":
	set(value):
		if value == action_token:
			return
		action_token = value
		if _is_remote() and is_node_ready():
			var parts := value.split("|")
			if parts.size() == 3:
				_play_action_local(parts[0], 0.45 / anim_speed, int(parts[2]))
var health: float = 100.0:
	set(value):
		var lost := health - value
		health = value
		if lost > 0.5 and is_node_ready() and not is_dead:
			_hurt_visuals()
		if _health_bar:
			_health_bar.set_ratio(health / max_health if max_health > 0.0 else 0.0)
		health_changed.emit(health, max_health)
var is_dead: bool = false:
	set(value):
		var changed := value != is_dead
		is_dead = value
		if changed and _is_remote() and is_node_ready():
			if value:
				_death_visuals()
			else:
				_revive_visuals()
## When set, the unit faces this direction instead of where it moves (e.g. while aiming).
var look_override: Vector3 = Vector3.ZERO
## Client-side prediction for the local player on clients: moves immediately from `predict_input`
## and gently reconciles with the server's position (set by main.gd).
var is_predicted: bool = false
var predict_input: Vector2 = Vector2.ZERO

var _action_time: float = 0.0  # > 0 while an attack animation should not be interrupted
var _melee_timer: float = 0.0
var _hit_tween: Tween
var _health_bar: HealthBar3D
var _right_item: Node3D
var _left_item: Node3D
var _right_hold: BonePoseOverride3D
var _left_hold: BonePoseOverride3D
var _arm_tween: Tween
var _was_acting: bool = false
var _melee_index: int = 0
var _melee_dir: Vector3 = Vector3.ZERO  # facing when the current swing started
var _since_hit: float = 0.0
var _model_scale: Vector3 = Vector3.ONE  # the model's size as set in the scene (e.g. giants are big)
var _action_seq: int = 0
var _saved_layers: Vector2i
static var _recolor_materials: Dictionary = {}  # "texture_rid|color|hue" -> ShaderMaterial (shared)
const RECOLOR_SHADER := preload("res://assets/shaders/palette_recolor.gdshader")
var _regen_pool: float = 0.0
var _full_body_action: bool = false
var _knockback: Vector3 = Vector3.ZERO
var _flash_material: StandardMaterial3D
var _flash_tween: Tween
var _live_hold: BonePoseOverride3D
var _color_ring: MeshInstance3D
# Steering state (AI units).
var _steer_timer: float = 0.0
var _steer_angle: float = 0.0
var _steer_side: float = 1.0
var _separation: Vector3 = Vector3.ZERO
var _slot_angle: float = 0.0
var _slot_target: Node3D
var _probe_shape: SphereShape3D
var _target_lock: float = 0.0
var _last_steer_pos: Vector3 = Vector3.INF
var _stuck_checks: int = 0
var _unstick_time: float = 0.0

@onready var model: Node3D = $Model
@onready var anim: AnimationPlayer = model.find_child("AnimationPlayer", true, false) as AnimationPlayer


func _ready() -> void:
	add_to_group(&"units")
	health = max_health
	net_position = global_position
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	anim.speed_scale = anim_speed
	_model_scale = model.scale
	for anim_name in LOOPING_ANIMS:
		if anim.has_animation(anim_name):
			anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	_setup_hands()
	_health_bar = HealthBar3D.new()
	_health_bar.fill_color = health_bar_color
	_health_bar.auto_hide_delay = health_bar_hide_delay
	_health_bar.position = Vector3(0, health_bar_height, 0)
	_health_bar.width = health_bar_width
	add_child(_health_bar)
	_apply_color()
	play_anim("idle")
	if _is_remote():
		# Other peers only show what the server simulates (the predicted local player still
		# bumps into trees / houses, see `enable_prediction()`).
		collision_layer = 0
		collision_mask = 0
		if is_dead:
			_death_visuals()


## Client: make this (local player's) unit move immediately from local input.
func enable_prediction() -> void:
	is_predicted = true
	collision_mask = GameConfig.LAYER_WORLD | GameConfig.LAYER_FENCE
	global_position = net_position


## True on clients: this unit is simulated by the server and only displayed here.
func _is_remote() -> bool:
	return multiplayer.has_multiplayer_peer() and not multiplayer.is_server()


func _process(delta: float) -> void:
	if not _is_remote():
		return
	if is_predicted and not is_dead:
		_predict(delta)
	else:
		_follow_server(delta)
	_advance_live_arm(delta)
	if _action_time > 0.0:
		_action_time -= delta
		if _action_time <= 0.0 and not is_dead:
			var was_full_body := _full_body_action
			_hold_arms()
			if was_full_body and not is_predicted:
				play_anim(anim_state if anim_state != "" else "idle")


## Remote units: smoothly follow the server's position / facing.
func _follow_server(delta: float) -> void:
	var before := global_position
	if global_position.distance_to(net_position) > 4.0:
		global_position = net_position
	else:
		global_position = global_position.lerp(net_position, 1.0 - exp(-14.0 * delta))
	velocity = (global_position - before) / maxf(delta, 0.0001)  # display speed (arm-only actions)
	model.rotation.y = lerp_angle(model.rotation.y, net_yaw, 1.0 - exp(-14.0 * delta))


## Local player on a client: move right away (no round trip), then drift toward the server's truth.
func _predict(delta: float) -> void:
	var move := Vector3(predict_input.x, 0.0, predict_input.y).limit_length(1.0)
	var strength := move.length()
	velocity = move * move_speed * (0.4 if _full_body_busy() else 1.0)
	move_and_slide()
	global_position = GameConfig.clamp_to_world(Vector3(global_position.x, 0.0, global_position.z))
	# Reconcile: the server's position trails ours by the network delay, so only correct real drift.
	var error := net_position - global_position
	error.y = 0.0
	var moving := strength > 0.05
	if error.length() > 3.0:
		global_position = net_position  # teleport / respawn
	elif error.length() > (0.7 if moving else 0.05):
		global_position += error * minf(1.0, delta * (2.0 if moving else 6.0))
	if look_override != Vector3.ZERO:
		face(look_override, delta * 1.5)
	elif moving:
		face(move, delta)
	if not _full_body_busy():
		play_anim(_move_anim(strength) if moving else _idle_anim())


func _physics_process(delta: float) -> void:
	if is_dead or _is_remote():
		return
	_action_time = maxf(_action_time - delta, 0.0)
	_melee_timer = maxf(_melee_timer - delta, 0.0)
	_target_lock = maxf(_target_lock - delta, 0.0)
	_unstick_time = maxf(_unstick_time - delta, 0.0)
	_since_hit += delta
	if regen_per_second > 0.0 and _since_hit > regen_delay and health < max_health:
		# Heal in whole points: fewer replicated health updates.
		_regen_pool += regen_per_second * delta
		if _regen_pool >= 1.0:
			heal(floorf(_regen_pool))
			_regen_pool -= floorf(_regen_pool)
	if _was_acting and _action_time <= 0.0:
		_hold_arms()
	_was_acting = _action_time > 0.0
	var move := _get_move_input(delta)
	var strength := minf(move.length(), 1.0)
	velocity = move.limit_length(1.0) * move_speed
	if _full_body_busy():
		velocity *= 0.4
	velocity += _knockback
	_knockback = _knockback.move_toward(Vector3.ZERO, delta * 22.0)
	move_and_slide()
	global_position = GameConfig.clamp_to_world(Vector3(global_position.x, 0.0, global_position.z))
	if look_override != Vector3.ZERO:
		face(look_override, delta * 1.5)
	elif strength > 0.05:
		face(move, delta)
	_advance_live_arm(delta)
	if not _full_body_busy():
		play_anim(_idle_anim() if strength < 0.05 else _move_anim(strength))
	net_position = global_position
	net_yaw = model.rotation.y


## Virtual: desired movement on the XZ plane (length 0..1).
func _get_move_input(_delta: float) -> Vector3:
	return Vector3.ZERO


## Virtual: animation to play while standing still.
func _idle_anim() -> String:
	return "idle"


## Virtual: animation while moving at `strength` (0..1 of move_speed).
func _move_anim(strength: float) -> String:
	return "sprint" if strength > sprint_threshold else "walk"


## Virtual: [damage, is_crit] for one melee swing (players can land critical hits).
func _roll_melee_damage() -> Array:
	return [melee_damage, false]


## Hit feedback on every peer: white flash, squash, sparks.
func _hurt_visuals() -> void:
	_punch()
	HitFx.burst(global_position + Vector3(0, health_bar_height * 0.55, 0), HitFx.Kind.FLESH, 9)
	HitFx.flash(global_position + Vector3(0, health_bar_height * 0.55, 0), HitFx.HIT_SPARK, Color(1.0, 0.9, 0.6), 1.1 * sqrt(radius / 0.35), 0.18)
	if _flash_material == null:
		_flash_material = StandardMaterial3D.new()
		_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_material.albedo_color = Color(1, 1, 1, 0)
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).material_overlay = _flash_material
	if _flash_tween:
		_flash_tween.kill()
	_flash_material.albedo_color.a = 0.85
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_material, "albedo_color:a", 0.0, 0.14)


## Whether a melee swing should damage this collider (hostile units / camps by default).
func _can_hit(target: Object) -> bool:
	return GameConfig.is_hostile(self, target)


## Virtual: called whenever the unit takes damage (attacker may be null).
func _on_damaged(_attacker: Node3D) -> void:
	pass


## Virtual: called once when the unit dies.
func _on_died() -> void:
	pass


# --- Facing -------------------------------------------------------------------

## Models face +Z, so the yaw is atan2(x, z).
func face(direction: Vector3, delta: float) -> void:
	var yaw := atan2(direction.x, direction.z)
	model.rotation.y = lerp_angle(model.rotation.y, yaw, minf(1.0, delta * 14.0))


func face_now(direction: Vector3) -> void:
	if direction.length_squared() > 0.0001:
		model.rotation.y = atan2(direction.x, direction.z)


func facing() -> Vector3:
	return Vector3(sin(model.rotation.y), 0.0, cos(model.rotation.y))


# --- Animation ----------------------------------------------------------------

func play_anim(anim_name: String, blend: float = 0.12) -> void:
	if not _is_remote():
		anim_state = anim_name
	if anim.current_animation != anim_name and anim.has_animation(anim_name):
		anim.play(anim_name, blend)


## Plays a one-shot animation; `release_arms` lets those arms leave the holding pose meanwhile.
## On the server this is also replicated to other peers.
func play_action(anim_name: String, duration: float, release_arms: int = ARM_BOTH) -> void:
	_action_seq += 1
	action_token = "%s|%d|%d" % [anim_name, _action_seq, release_arms]
	_play_action_local(anim_name, duration, release_arms)


func _play_action_local(anim_name: String, duration: float, release_arms: int) -> void:
	# While moving, one-arm actions (sword swing, bow shot) play on that arm only: legs keep running.
	var arm_hold: BonePoseOverride3D = null
	if release_arms == ARM_RIGHT:
		arm_hold = _right_hold
	elif release_arms == ARM_LEFT:
		arm_hold = _left_hold
	if arm_hold and velocity.length() > 0.5 and anim.has_animation(anim_name) and anim_name != "die":
		_action_time = duration
		_was_acting = true
		_full_body_action = false
		if _arm_tween:
			_arm_tween.kill()
		arm_hold.influence = 1.0
		arm_hold.start_live(anim.get_animation(anim_name))
		_live_hold = arm_hold
		if release_arms == ARM_RIGHT and _right_item:
			_right_item.position = right_swing_offset
			_right_item.rotation_degrees = right_swing_rotation
		return
	_full_body_action = true
	_action_time = duration
	_was_acting = true
	_release_arms(release_arms)
	if anim.current_animation == anim_name:
		anim.seek(0.0, true)
	else:
		anim.play(anim_name, 0.05)


# --- Combat -------------------------------------------------------------------

## Starts a melee swing if the cooldown allows it. Damage lands a moment later.
func melee() -> bool:
	if is_dead or _melee_timer > 0.0:
		return false
	_melee_timer = melee_cooldown
	_melee_dir = facing()  # damage lands where the swing started, even if the unit turns meanwhile
	var anim_name := melee_anims[_melee_index % melee_anims.size()]
	_melee_index += 1
	play_action(anim_name, 0.4 / anim_speed, ARM_RIGHT if anim_name.ends_with("right") else ARM_BOTH)
	# Damage lands on the forward strike frame of the swing.
	get_tree().create_timer(attack_hit_delay / anim_speed).timeout.connect(_apply_melee)
	return true


func _apply_melee() -> void:
	if is_dead:
		return
	var query := _melee_query(_melee_dir if _melee_dir != Vector3.ZERO else facing())
	var center := query.transform.origin
	var roll := _roll_melee_damage()
	var victims: Array[Node3D] = []
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 32):
		var collider := hit.collider as Node3D
		if collider and not victims.has(collider) and collider.has_method("take_damage") and _can_hit(collider):
			victims.append(collider)
	if victims.is_empty():
		return
	if not melee_cleave:
		# Single-target: the unit we're fighting if it's in the swing, else the closest one.
		var best: Node3D = _slot_target if is_instance_valid(_slot_target) and victims.has(_slot_target) else null
		if best == null:
			for victim in victims:
				if best == null or victim.global_position.distance_to(center) < best.global_position.distance_to(center):
					best = victim
		victims = [best]
	for victim in victims:
		victim.take_damage(roll[0], self, true, roll[1])


## What a melee swing toward `direction` can hit. Covers up to ~1.25 × melee_range in front (plus the
## target's own size), so every unit can always hit from the distance where `engage()` stops it.
func _melee_query(direction: Vector3) -> PhysicsShapeQueryParameters3D:
	var sphere := SphereShape3D.new()
	sphere.radius = melee_range * 0.75
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis(), global_position + direction * melee_range * 0.5 + Vector3(0, 0.5, 0))
	query.collision_mask = melee_mask
	query.exclude = [get_rid()]
	return query


func take_damage(amount: float, attacker: Node3D = null, is_melee: bool = true, crit: bool = false) -> void:
	if is_dead:
		return
	if attacker and GameConfig.owner_peer_of(attacker) != 0:
		last_attacker_peer = GameConfig.owner_peer_of(attacker)
	if attacker and knockback_taken > 0.0:
		var away := global_position - attacker.global_position
		away.y = 0.0
		if away.length_squared() > 0.0001:
			_knockback = away.normalized() * (4.5 if crit else 3.0) * knockback_taken
	var dealt := minf(amount, health)  # numbers show real damage, not overkill
	health = maxf(health - amount, 0.0)
	_since_hit = 0.0
	HitFx.report_hit(self, dealt, attacker, crit, is_melee)
	_on_damaged(attacker)
	if health <= 0.0:
		die()


func heal(amount: float) -> void:
	if is_dead:
		return
	health = minf(health + amount, max_health)


func die() -> void:
	if is_dead:
		return
	is_dead = true
	velocity = Vector3.ZERO
	_saved_layers = Vector2i(collision_layer, collision_mask)
	_death_visuals()
	MatchStats.on_unit_died(self)
	_on_died()
	died.emit(self)
	if free_on_death:
		var tween := create_tween()
		tween.tween_interval(1.4)
		tween.tween_property(model, "position:y", -0.9, 0.8)
		tween.tween_callback(queue_free)


## Brings a dead unit back (multiplayer respawns). Server only.
func revive(at: Vector3) -> void:
	global_position = at
	net_position = at
	health = max_health
	is_dead = false
	collision_layer = _saved_layers.x
	collision_mask = _saved_layers.y
	_revive_visuals()


func _death_visuals() -> void:
	collision_layer = 0
	collision_mask = 0
	_health_bar.hide()
	if _color_ring:
		_color_ring.hide()
	_play_action_local("die", 99.0, ARM_BOTH)
	HitFx.flash(global_position + Vector3(0, 0.4, 0), HitFx.DEATH_SMOKE, Color(0.85, 0.85, 0.8, 0.8), 1.6 * sqrt(radius / 0.35), 0.7, Vector2(0.5, 1.3), false)


func _revive_visuals() -> void:
	_action_time = 0.0
	model.position.y = 0.0
	if _color_ring:
		_color_ring.show()
	_hold_arms(true)
	play_anim("idle", 0.0)


func _full_body_busy() -> bool:
	return _action_time > 0.0 and _full_body_action


func _advance_live_arm(delta: float) -> void:
	if _live_hold:
		_live_hold.live_time += delta * anim_speed


## Colored ring under the unit + the player's color on the model (see recolor_* exports).
func _apply_color() -> void:
	if unit_color.a <= 0.0:
		return
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = radius * 0.95
	ring_mesh.outer_radius = radius * 1.35
	ring_mesh.rings = 24
	ring_mesh.ring_segments = 6
	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.albedo_color = unit_color
	ring_mesh.material = ring_material
	_color_ring = MeshInstance3D.new()
	_color_ring.mesh = ring_mesh
	_color_ring.scale = Vector3(1, 0.15, 1)
	_color_ring.position.y = COLOR_RING_HEIGHT
	_color_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_color_ring)
	if recolor_key_hue < 0.0:
		return
	# Recolor the model's key hue (soldier crest, archer hat…) to the player's color; not the weapons in hand.
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if _in_hand(mesh_instance):
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.mesh.surface_get_material(surface) as StandardMaterial3D
			if source and source.albedo_texture:
				mesh_instance.set_surface_override_material(surface, _recolor_material(source.albedo_texture))


## True for meshes of an item attached to a bone (weapons, shields), which keep their own colors.
func _in_hand(node: Node) -> bool:
	while node and node != model:
		if node is BoneAttachment3D:
			return true
		node = node.get_parent()
	return false


func _recolor_material(texture: Texture2D) -> ShaderMaterial:
	var key := "%s|%s|%.3f" % [texture.get_rid(), unit_color.to_html(false), recolor_key_hue]
	if not _recolor_materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = RECOLOR_SHADER
		material.set_shader_parameter("albedo_tex", texture)
		material.set_shader_parameter("target_color", Vector3(unit_color.r, unit_color.g, unit_color.b))
		material.set_shader_parameter("key_hue", recolor_key_hue)
		material.set_shader_parameter("hue_range", recolor_hue_range)
		material.set_shader_parameter("min_saturation", recolor_min_saturation)
		material.set_shader_parameter("reference_value", recolor_reference_value)
		_recolor_materials[key] = material
	return _recolor_materials[key]


# --- Helpers ------------------------------------------------------------------

func _punch() -> void:
	if _hit_tween:
		_hit_tween.kill()
	model.scale = _model_scale * 1.18
	_hit_tween = create_tween()
	_hit_tween.tween_property(model, "scale", _model_scale, 0.15)


# --- Hands --------------------------------------------------------------------
# Kenney characters have one bone per arm, so a weapon can't follow a wrist. Instead the arm is
# held in the "holding" pose (weapon upright in front) while walking/idle, and released during
# attacks, where the weapon switches to a grip in line with the arm so it follows the swing.

func _setup_hands() -> void:
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	_right_item = _attach_item(skeleton, right_hand_item, "arm-right")
	_left_item = _attach_item(skeleton, left_hand_item, "arm-left")
	if hold_right_arm:
		_right_hold = _make_hold(skeleton, "arm-right", "holding-right")
	if hold_left_arm:
		_left_hold = _make_hold(skeleton, "arm-left", "holding-left")
	_hold_arms(true)


func _make_hold(skeleton: Skeleton3D, bone: String, pose_anim: String) -> BonePoseOverride3D:
	if skeleton.find_bone(bone) == -1 or not anim.has_animation(pose_anim):
		return null
	var hold := BonePoseOverride3D.new()
	skeleton.add_child(hold)
	var pose := anim.get_animation(pose_anim)
	hold.set_pose_from_animation(pose, pose.length * 0.5, PackedStringArray([bone]))
	return hold


func _attach_item(skeleton: Skeleton3D, item: PackedScene, bone: String) -> Node3D:
	if item == null or skeleton.find_bone(bone) == -1:
		return null
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = bone
	skeleton.add_child(attachment)
	var instance := item.instantiate() as Node3D
	attachment.add_child(instance)
	return instance


## Arms back into the holding pose, weapons into their carry grip.
func _hold_arms(instant: bool = false) -> void:
	_full_body_action = false
	if _live_hold:
		_live_hold.stop_live()
		_live_hold = null
	if _arm_tween:
		_arm_tween.kill()
	var duration := 0.0 if instant else 0.12
	if duration > 0.0 and (_right_hold or _left_hold):
		_arm_tween = create_tween().set_parallel(true)
	_tween_arm(_right_hold, _right_item, 1.0, right_hand_offset, right_hand_rotation, duration)
	_tween_arm(_left_hold, _left_item, 1.0, left_hand_offset, left_hand_rotation, duration)
	# Arms that are never held always use the swing grip.
	if _right_hold == null and _right_item:
		_right_item.position = right_swing_offset
		_right_item.rotation_degrees = right_swing_rotation
	if _left_hold == null and _left_item:
		_left_item.position = left_hand_offset
		_left_item.rotation_degrees = left_hand_rotation


func _release_arms(arms: int) -> void:
	if _arm_tween:
		_arm_tween.kill()
	if arms & ARM_RIGHT and _right_hold:
		_right_hold.influence = 0.0
		if _right_item:
			_right_item.position = right_swing_offset
			_right_item.rotation_degrees = right_swing_rotation
	if arms & ARM_LEFT and _left_hold:
		_left_hold.influence = 0.0


func _tween_arm(hold: BonePoseOverride3D, item: Node3D, influence: float, offset: Vector3,
		rotation_deg: Vector3, duration: float) -> void:
	if hold == null:
		return
	if duration <= 0.0:
		hold.influence = influence
		if item:
			item.position = offset
			item.rotation_degrees = rotation_deg
		return
	_arm_tween.tween_property(hold, "influence", influence, duration)
	if item:
		_arm_tween.tween_property(item, "position", offset, duration)
		_arm_tween.tween_property(item, "rotation_degrees", rotation_deg, duration)


## Nearest living hostile node from `groups` within `max_range` (XZ distance). `bias` per group adds
## extra distance, e.g. to prefer units over buildings.
func find_nearest(groups: Array[StringName], max_range: float, origin: Vector3 = global_position,
		bias: Dictionary = {}) -> Node3D:
	var best: Node3D = null
	var best_dist := max_range
	for group in groups:
		var extra: float = bias.get(group, 0.0)
		for node in get_tree().get_nodes_in_group(group):
			if GameConfig.is_gone(node) or node == self or not GameConfig.is_hostile(self, node):
				continue
			var n3 := node as Node3D
			var d := Vector2(n3.global_position.x - origin.x, n3.global_position.z - origin.z).length() + extra
			if d < best_dist:
				best_dist = d
				best = n3
	return best


## AI target choice with stickiness: keeps `current` while it is valid and within `keep_range`, unless
## `candidate` is much closer and the lock time is over. Returns the target to use.
func choose_target(current: Node3D, candidate: Node3D, keep_range: float) -> Node3D:
	if GameConfig.is_gone(current) or flat_distance_to(current) > keep_range:
		if candidate:
			_target_lock = TARGET_LOCK_TIME
		return candidate
	if candidate == null or candidate == current or _target_lock > 0.0:
		return current
	if flat_distance_to(candidate) < flat_distance_to(current) * TARGET_SWITCH_RATIO:
		_target_lock = TARGET_LOCK_TIME
		return candidate
	return current


## Keep the current target for TARGET_LOCK_TIME (e.g. right after retaliating against an attacker).
func lock_target() -> void:
	_target_lock = TARGET_LOCK_TIME


func flat_distance_to(node: Node3D) -> float:
	return Vector2(node.global_position.x - global_position.x, node.global_position.z - global_position.z).length()


## How far from its center a target's surface is (buildings are wider than units).
static func target_radius(target: Node3D) -> float:
	var radius: Variant = target.get("radius")
	return radius if radius is float else 0.35


# --- AI movement --------------------------------------------------------------

## Moves toward `target` and melee-attacks it once in reach. Attackers spread around the target
## (each picks its own spot) instead of queueing behind each other. Returns the move vector.
func engage(target: Node3D, delta: float) -> Vector3:
	var to := target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var reach := melee_range + Unit.target_radius(target)
	if dist <= reach:
		# Face the target before swinging, otherwise the swing hits empty air.
		face_now(to)
		melee()
		return _separation * 0.5
	if target != _slot_target:
		# Pick a spot on the side we're coming from, with some spread.
		_slot_target = target
		_slot_angle = atan2(-to.z, -to.x) + randf_range(-1.1, 1.1)
	var desired := to
	if dist < reach + 3.0:
		var slot := target.global_position + Vector3(cos(_slot_angle), 0.0, sin(_slot_angle)) * reach * 0.8
		desired = slot - global_position
		desired.y = 0.0
	# The target itself (e.g. a camp) is not an obstacle; while still chasing, others in the way are.
	return steer(desired, delta, target, dist > reach + 1.5)


## Turns a desired direction into one that goes around obstacles, plus separation from
## nearby units on the same side. `ignore` (e.g. the building being attacked) is not an obstacle.
## A unit that barely moves for a few checks while trying to (wedged against a tree, a crowd or a
## wall corner) switches sides and walks sideways for a moment to get free.
func steer(desired: Vector3, delta: float, ignore: Node3D = null, chasing: bool = false) -> Vector3:
	var strength := minf(desired.length(), 1.0)
	if strength < 0.01:
		return Vector3.ZERO
	var want := desired.normalized()
	_steer_timer -= delta
	if _steer_timer <= 0.0:
		_steer_timer = STEER_INTERVAL + randf() * 0.05
		_check_stuck(strength)
		_steer_angle = _pick_steer_angle(want, ignore, 1.2 if _unstick_time > 0.0 else 0.0,
				chase_avoid_mask if chasing else 0)
		_separation = _compute_separation() if separation_strength > 0.0 else Vector3.ZERO
	var dir := want.rotated(Vector3.UP, _steer_angle) + _separation * separation_strength
	return dir.normalized() * strength


func _check_stuck(strength: float) -> void:
	var moved := global_position.distance_to(_last_steer_pos) if _last_steer_pos != Vector3.INF else INF
	_last_steer_pos = global_position
	if strength > 0.3 and moved < move_speed * STEER_INTERVAL * 0.2:
		_stuck_checks += 1
		if _stuck_checks >= 3:
			_stuck_checks = 0
			_steer_side = -_steer_side
			_unstick_time = 0.7
	else:
		_stuck_checks = 0


## Picks the direction closest to `want` whose path is free of trees / houses for `steer_lookahead`.
## The probe is sized to the unit, so big ones (giants, the Warlord) look for wide enough gaps.
## `min_angle` > 0 forces a sideways step (used to get unstuck). `extra_mask`: more layers to go around.
func _pick_steer_angle(want: Vector3, ignore: Node3D, min_angle: float = 0.0, extra_mask: int = 0) -> float:
	if _probe_shape == null:
		_probe_shape = SphereShape3D.new()
		_probe_shape.radius = clampf(radius * 0.6, 0.24, 0.5)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _probe_shape
	query.collision_mask = GameConfig.LAYER_WORLD | (collision_mask & GameConfig.LAYER_FENCE) | extra_mask
	query.transform = Transform3D(Basis(), global_position + Vector3(0, 0.45, 0))
	var exclude: Array[RID] = [get_rid()]
	if is_instance_valid(ignore) and ignore is CollisionObject3D:
		exclude.append((ignore as CollisionObject3D).get_rid())
	query.exclude = exclude
	var space := get_world_3d().direct_space_state
	var best_angle := 0.0
	var best_free := -1.0
	for base_angle in STEER_ANGLES:
		if absf(base_angle) < min_angle:
			continue
		var angle := base_angle * _steer_side
		query.motion = want.rotated(Vector3.UP, angle) * steer_lookahead
		var free: float = space.cast_motion(query)[0]
		if free >= 0.999:
			if angle != 0.0:
				_steer_side = signf(angle)  # keep going around the same side
			return angle
		if free > best_free:
			best_free = free
			best_angle = angle
	return best_angle


func _compute_separation() -> Vector3:
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = separation_radius
	query.shape = sphere
	query.collision_mask = collision_layer
	query.transform = Transform3D(Basis(), global_position + Vector3(0, 0.5, 0))
	query.exclude = [get_rid()]
	var push := Vector3.ZERO
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 8):
		var other := hit.collider as Node3D
		if other == null:
			continue
		var away := global_position - other.global_position
		away.y = 0.0
		var d := away.length()
		if d < 0.001:
			away = Vector3(randf() - 0.5, 0.0, randf() - 0.5)
			d = 0.001
		push += away / d * (1.0 - minf(d / separation_radius, 1.0))
	return push.limit_length(1.0)
