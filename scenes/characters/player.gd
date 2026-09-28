class_name Player
extends Unit
## The archer (one per connected player). Moves with the joystick. Both weapons are aim sticks:
## sword — drag to swing toward a direction (keeps swinging while held, even while running another way);
## bow — drag to aim, release to shoot. A tap on either auto-targets the nearest enemy. Arrows are limited.
##
## Multiplayer: the server simulates every player. Input arrives through `set_input()` (host) or the
## `net_*` RPCs (clients → server). Stats (arrows, coins, …) are replicated back via the Sync node.
##
## Downed (when GameConfig.downed_enabled, i.e. online co-op / team modes): at 0 health the archer
## crawls for BLEED_TIME seconds instead of dying. A teammate standing close for REVIVE_TIME brings
## them back; orcs leave downed archers alone, but an enemy player can finish them.
## Army orders: `command_army()` tells this player's soldiers to follow, charge a point or hold a point.

signal arrows_changed(count: int)
signal coins_changed(count: int)
signal upgrades_changed
## Server: this player just went down / was revived (`helpers` = the players who revived them).
signal went_down(player: Player)
signal revived(player: Player, helpers: Array)
## Every peer: the downed state changed (visuals, HUD).
signal downed_changed(downed: bool)
signal army_order_changed(order: int)

enum Order { FOLLOW, CHARGE, HOLD }

const TARGET_GROUPS: Array[StringName] = [&"active_enemies", &"player_units", &"camps"]
const AIM_LINE_WIDTH: float = 0.18
## Aimed sword swings snap to an enemy within this angle / distance.
const MELEE_ASSIST_DEGREES: float = 35.0
const MELEE_ASSIST_RANGE: float = 2.4
const CATALOG := preload("res://resources/data/upgrade_catalog.tres")
const BLEED_TIME: float = 15.0
const REVIVE_TIME: float = 3.0
const REVIVE_RANGE: float = 1.8
## Health fraction after a revive.
const REVIVE_HEALTH: float = 0.4
## Crawl speed while downed (fraction of move_speed).
const DOWNED_SPEED: float = 0.3
## "crawl" (moving) and "downed" (lying still) clips, made in Blender on the archer's armature.
const DOWNED_ANIMS := preload("res://assets/characters/animations/archer_downed.glb")
const DOWNED_CLIPS: Array[String] = ["crawl", "downed"]
const REVIVE_RING_TEXTURE := preload("res://assets/vfx/light_masks/ring_a.png")
## Downed archer: the revive bar sits just above the lying body; "HELP!" and the name stack above it
## in screen space (Label3D offsets, pixels), so they never overlap however steep the camera is.
const DOWNED_LABEL_HEIGHT: float = 1.05
const DOWNED_HELP_OFFSET: float = 46.0
const DOWNED_NAME_OFFSET: float = 104.0
## Charge orders reach at most this far from the player.
const MAX_ORDER_DISTANCE: float = 25.0

@export var max_arrows: int = 99
@export var arrow_damage: float = 34.0
@export var shoot_cooldown: float = 0.4
@export var aim_range: float = 12.0
## Aimed shots snap to an enemy within this angle of the aim direction.
@export var aim_assist_degrees: float = 10.0
@export var arrow_scene: PackedScene
## Chance and multiplier for critical hits (sword and arrows).
@export_range(0.0, 1.0) var crit_chance: float = 0.15
@export var crit_multiplier: float = 1.8

## Network id of the player controlling this archer (set at spawn).
var peer_id: int = 1
var display_name: String = "Archer"
## Movement input (screen axes), set from the HUD / network.
var joystick_vector: Vector2 = Vector2.ZERO
## Soldier health/damage multiplier (raised by the "drill" upgrade). Server only.
var ally_power: float = 1.0

# --- Replicated stats (see the Sync node) ---
@export var arrows: int = 15:
	set(value):
		arrows = value
		arrows_changed.emit(arrows)
var coins: int = 0:
	set(value):
		coins = value
		coins_changed.emit(coins)
## Freed soldiers waiting to replace fallen followers (over the follower cap).
var reserve_soldiers: int = 0
## Max soldiers following at once (raised by the "command" upgrade).
var follower_cap: int = GameConfig.BASE_FOLLOWER_CAP
## Upgrade id -> times bought. Always replaced (not mutated) so replication notices changes.
var upgrade_levels: Dictionary = {}:
	set(value):
		upgrade_levels = value
		upgrades_changed.emit()
var is_downed: bool = false:
	set(value):
		if value != is_downed:
			is_downed = value
			if is_node_ready():
				_apply_downed()
## Revive progress 0..1 (quantized, replicated for the bar over the downed archer).
var revive_progress: float = 0.0:
	set(value):
		revive_progress = value
		if _revive_bar:
			_revive_bar.set_ratio(value)
			_revive_bar.visible = _shows_revive_bar()
## Whole seconds left before a downed archer bleeds out (replicated for the HUD / label).
var bleed_seconds: int = 0:
	set(value):
		bleed_seconds = value
		if _downed_label:
			_downed_label.text = "HELP!  %d" % value
var army_order: int = Order.FOLLOW:
	set(value):
		if value != army_order:
			army_order = value
			army_order_changed.emit(value)
## Where soldiers charge to / hold (valid for CHARGE and HOLD).
var army_point: Vector3 = Vector3.ZERO

var _base_melee_damage: float
var _base_arrow_damage: float
var _shoot_timer: float = 0.0
var _pending_shot: Vector3 = Vector3.ZERO  # aimed shot released during cooldown
var _aim_indicator: Node3D
var _aim_material: StandardMaterial3D
var _melee_aim: Vector3 = Vector3.ZERO
var _melee_indicator: Node3D
var _name_label: Label3D
var _base_move_speed: float
var _bleed_left: float = 0.0
var _revive_raw: float = 0.0
var _downed_label: Label3D
var _revive_bar: HealthBar3D
var _revive_ring: Decal
var _was_downed: bool = false


func _ready() -> void:
	owner_peer = peer_id
	super()
	add_to_group(&"players")
	add_to_group(&"player_units")
	_base_melee_damage = melee_damage
	_base_arrow_damage = arrow_damage
	_base_move_speed = move_speed
	for looping in ["holding-left", "sit", "crouch"]:
		if anim.has_animation(looping):
			anim.get_animation(looping).loop_mode = Animation.LOOP_LINEAR
	_add_downed_anims()
	_build_aim_indicator()
	_build_melee_indicator()
	_build_name_label()
	_build_downed_visuals()
	if is_downed:
		_apply_downed()


## True on the device whose player this is.
func is_local() -> bool:
	return peer_id == multiplayer.get_unique_id()


func _get_move_input(delta: float) -> Vector3:
	if is_downed:
		_update_downed(delta)
		return Vector3(joystick_vector.x, 0.0, joystick_vector.y)
	_shoot_timer = maxf(_shoot_timer - delta, 0.0)
	if _pending_shot != Vector3.ZERO and _shoot_timer <= 0.0:
		var direction := _pending_shot
		_pending_shot = Vector3.ZERO
		shoot(direction)
	if _melee_aim != Vector3.ZERO:
		attack_melee_toward(_melee_aim)
	# Camera looks toward -Z, so screen-up is -Z.
	return Vector3(joystick_vector.x, 0.0, joystick_vector.y)


func _roll_melee_damage() -> Array:
	var crit := randf() < crit_chance
	return [melee_damage * (crit_multiplier if crit else 1.0), crit]


## Copies the crawl clips into the archer's animation library (shared by every archer, so once).
func _add_downed_anims() -> void:
	var library := anim.get_animation_library(&"")
	if library == null or library.has_animation(DOWNED_CLIPS[0]):
		return
	var source := DOWNED_ANIMS.instantiate()
	var source_anim := source.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for clip_name in DOWNED_CLIPS:
		if source_anim and source_anim.has_animation(clip_name):
			var clip := source_anim.get_animation(clip_name).duplicate() as Animation
			clip.loop_mode = Animation.LOOP_LINEAR
			library.add_animation(clip_name, clip)
	source.free()


## Downed archers crawl with both arms, so the weapon-holding pose stays off.
func _hold_arms(instant: bool = false) -> void:
	super(instant)
	if is_downed:
		_release_arms(ARM_BOTH)


func _idle_anim() -> String:
	if is_downed:
		return "downed"
	return "holding-left" if is_aiming() else "idle"


func _move_anim(strength: float) -> String:
	return "crawl" if is_downed else super(strength)


func _can_hit(target: Object) -> bool:
	var node := target as Node
	return node != null and (GameConfig.is_hostile(self, node) or node.is_in_group(&"choppable"))


# --- Input (called on the server) ---------------------------------------------

## Continuous input for this frame: movement, bow aim and sword aim (Vector3.ZERO = not aiming).
func set_input(move: Vector2, aim: Vector3, melee_aim: Vector3 = Vector3.ZERO) -> void:
	joystick_vector = move.limit_length(1.0)
	set_melee_aim(melee_aim)
	if melee_aim != Vector3.ZERO:
		return  # the sword stick decides where we face
	if aim != Vector3.ZERO:
		set_aim(aim)
	elif is_aiming():
		clear_aim()


@rpc("any_peer", "call_remote", "unreliable_ordered")
func net_input(move: Vector2, aim: Vector3, melee_aim: Vector3) -> void:
	if _from_owner():
		set_input(move, aim, melee_aim)


@rpc("any_peer", "call_remote", "reliable")
func net_melee() -> void:
	if _from_owner():
		attack_melee()


@rpc("any_peer", "call_remote", "reliable")
func net_shoot(direction: Vector3) -> void:
	if _from_owner():
		shoot(direction)


@rpc("any_peer", "call_remote", "reliable")
func net_buy(upgrade_id: StringName) -> void:
	if not _from_owner():
		return
	for def in CATALOG.upgrades:
		if def.id == upgrade_id:
			buy_upgrade(def)
			return


func _from_owner() -> bool:
	return multiplayer.is_server() and multiplayer.get_remote_sender_id() == peer_id


# --- Melee --------------------------------------------------------------------

func attack_melee() -> void:
	if is_dead or is_downed or _melee_timer > 0.0:
		return
	var target := find_nearest(TARGET_GROUPS, 1.8, global_position, {&"camps": -0.8})
	if target:
		face_now(_flat_dir_to(target))
	melee()


## Swing toward `direction` (sword stick), with a little aim assist. Movement is independent.
func attack_melee_toward(direction: Vector3) -> void:
	if is_dead or is_downed or _melee_timer > 0.0:
		return
	direction.y = 0.0
	var best := direction.normalized()
	var best_angle := deg_to_rad(MELEE_ASSIST_DEGREES)
	for group in TARGET_GROUPS:
		for node in get_tree().get_nodes_in_group(group):
			if GameConfig.is_gone(node) or node == self or not GameConfig.is_hostile(self, node):
				continue
			var to := (node as Node3D).global_position - global_position
			to.y = 0.0
			if to.length() > MELEE_ASSIST_RANGE + Unit.target_radius(node) or to.length() < 0.05:
				continue
			var angle := direction.angle_to(to)
			if angle < best_angle:
				best_angle = angle
				best = to.normalized()
	face_now(best)
	melee()


## Sword stick aim: face `direction` (shows a short wedge for the local player). ZERO = released.
func set_melee_aim(direction: Vector3) -> void:
	direction.y = 0.0
	if direction.length_squared() < 0.0001 or is_dead or is_downed:
		if _melee_aim != Vector3.ZERO:
			_melee_aim = Vector3.ZERO
			_melee_indicator.visible = false
			look_override = Vector3.ZERO  # the bow stick sets it again next frame if aiming
		return
	_melee_aim = direction.normalized()
	look_override = _melee_aim
	_melee_indicator.rotation.y = atan2(_melee_aim.x, _melee_aim.z)
	_melee_indicator.visible = is_local()
	_aim_indicator.visible = false


# --- Bow ----------------------------------------------------------------------

## Shows the aim line (local player) and turns the archer toward `direction` (XZ plane).
func set_aim(direction: Vector3) -> void:
	if is_dead or is_downed or direction.length_squared() < 0.0001:
		return
	direction.y = 0.0
	direction = direction.normalized()
	look_override = direction
	_aim_indicator.rotation.y = atan2(direction.x, direction.z)
	_aim_material.albedo_color = Color(1, 1, 1, 0.5) if arrows > 0 else Color(1, 0.3, 0.3, 0.5)
	_aim_indicator.visible = is_local()


func clear_aim() -> void:
	look_override = Vector3.ZERO
	_aim_indicator.visible = false


func is_aiming() -> bool:
	return look_override != Vector3.ZERO


## Shoots toward `direction`, or at the nearest enemy when no direction is given. Server only.
func shoot(direction: Vector3 = Vector3.ZERO) -> void:
	if is_dead or is_downed or arrows <= 0:
		return
	if _shoot_timer > 0.0:
		if direction != Vector3.ZERO:
			_pending_shot = direction
		return
	_shoot_timer = shoot_cooldown
	arrows -= 1
	if direction == Vector3.ZERO:
		var target := find_nearest(TARGET_GROUPS, aim_range, global_position, {&"camps": 3.0})
		direction = _flat_dir_to(target) if target else facing()
	else:
		direction.y = 0.0
		direction = _assisted(direction.normalized())
	face_now(direction)
	play_action("holding-left-shoot", 0.25, ARM_LEFT)
	var crit := randf() < crit_chance
	NetSpawn.projectile(&"arrow", global_position + Vector3(0, 0.55, 0) + direction * 0.4, direction,
			arrow_damage * (crit_multiplier if crit else 1.0), self, crit)


## Nudges an aimed direction onto an enemy that is almost in line with it.
func _assisted(direction: Vector3) -> Vector3:
	var best := direction
	var best_angle := deg_to_rad(aim_assist_degrees)
	for group in TARGET_GROUPS:
		for node in get_tree().get_nodes_in_group(group):
			if GameConfig.is_gone(node) or node == self or not GameConfig.is_hostile(self, node):
				continue
			var to := (node as Node3D).global_position - global_position
			to.y = 0.0
			if to.length() > aim_range or to.length() < 0.1:
				continue
			var angle := direction.angle_to(to)
			if angle < best_angle:
				best_angle = angle
				best = to.normalized()
	return best


func _build_aim_indicator() -> void:
	var probe := arrow_scene.instantiate() as ArrowProjectile
	var arrow_range := probe.speed * probe.lifetime
	probe.free()
	_aim_material = StandardMaterial3D.new()
	_aim_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_aim_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_aim_material.albedo_color = Color(1, 1, 1, 0.5)
	_aim_indicator = Node3D.new()
	_aim_indicator.visible = false
	add_child(_aim_indicator)
	# Line along +Z (models face +Z, so rotation.y uses the same atan2(x, z) as facing).
	var line := PlaneMesh.new()
	line.size = Vector2(AIM_LINE_WIDTH, arrow_range - 0.6)
	_add_indicator_part(line, Vector3(0, 0.05, 0.6 + (arrow_range - 0.6) * 0.5), 0.0)
	# Diamond tip at the end of the range.
	var tip := PlaneMesh.new()
	tip.size = Vector2(0.45, 0.45)
	_add_indicator_part(tip, Vector3(0, 0.05, arrow_range), PI * 0.25)


func _add_indicator_part(mesh: PlaneMesh, at: Vector3, yaw: float) -> void:
	mesh.material = _aim_material
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.rotation.y = yaw
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aim_indicator.add_child(part)


## Short orange wedge in front of the archer while aiming the sword.
func _build_melee_indicator() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.62, 0.2, 0.45)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var reach := melee_range * 1.25 + 0.3
	var wedge := ImmediateMesh.new()
	wedge.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	var steps := 8
	var half := deg_to_rad(40.0)
	for i in steps:
		var a0 := -half + 2.0 * half * i / steps
		var a1 := -half + 2.0 * half * (i + 1) / steps
		wedge.surface_add_vertex(Vector3(0, 0.05, 0.25))
		wedge.surface_add_vertex(Vector3(sin(a0) * reach, 0.05, cos(a0) * reach))
		wedge.surface_add_vertex(Vector3(sin(a1) * reach, 0.05, cos(a1) * reach))
	wedge.surface_end()
	var part := MeshInstance3D.new()
	part.mesh = wedge
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_melee_indicator = Node3D.new()
	_melee_indicator.visible = false
	_melee_indicator.add_child(part)
	add_child(_melee_indicator)


func _build_name_label() -> void:
	_name_label = Label3D.new()
	_name_label.text = display_name
	_name_label.font_size = 56
	_name_label.outline_size = 14
	_name_label.pixel_size = 0.006
	_name_label.modulate = unit_color if unit_color.a > 0.0 else Color.WHITE
	_name_label.outline_modulate = Color(0.1, 0.05, 0.0, 0.9)
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.no_depth_test = true
	_name_label.position = Vector3(0, health_bar_height + 0.28, 0)
	_name_label.visible = Net.is_online()
	add_child(_name_label)


# --- Pickups (server) -------------------------------------------------------------

func can_collect(kind: Pickup.Kind) -> bool:
	if is_dead or is_downed:
		return false
	match kind:
		Pickup.Kind.ARROWS:
			return arrows < max_arrows
		Pickup.Kind.HEALTH:
			return health < max_health
		Pickup.Kind.COIN:
			return true
	return false


func collect(kind: Pickup.Kind, amount: int) -> bool:
	if not can_collect(kind):
		return false
	match kind:
		Pickup.Kind.ARROWS:
			arrows = mini(arrows + amount, max_arrows)
		Pickup.Kind.HEALTH:
			heal(amount)
		Pickup.Kind.COIN:
			coins += amount
			MatchStats.add(peer_id, &"coins", amount)
	return true


# --- Army ---------------------------------------------------------------------

## This player's soldiers currently in the world.
func followers() -> Array[Node]:
	return get_tree().get_nodes_in_group(&"allies").filter(
			func(ally: Node) -> bool: return ally.get("owner_peer") == peer_id and not ally.get("is_dead"))


# --- Economy ------------------------------------------------------------------

func upgrade_level(id: StringName) -> int:
	return upgrade_levels.get(id, 0)


func upgrade_cost(def: UpgradeDef) -> int:
	return def.cost_at(upgrade_level(def.id))


func is_upgrade_maxed(def: UpgradeDef) -> bool:
	return not def.is_consumable() and upgrade_level(def.id) >= def.max_level


## False when buying would be wasted (e.g. potion at full health).
func is_upgrade_useful(def: UpgradeDef) -> bool:
	match def.id:
		&"potion":
			return health < max_health
		&"arrows":
			return arrows < max_arrows
	return true


func can_buy(def: UpgradeDef) -> bool:
	return not is_dead and not is_downed and not is_upgrade_maxed(def) and is_upgrade_useful(def) and coins >= upgrade_cost(def)


## Buys on the server; on clients sends the request to the server.
func request_buy(def: UpgradeDef) -> void:
	if multiplayer.is_server():
		buy_upgrade(def)
	else:
		net_buy.rpc_id(1, def.id)


func buy_upgrade(def: UpgradeDef) -> bool:
	if not can_buy(def):
		return false
	coins -= upgrade_cost(def)
	var levels := upgrade_levels.duplicate()
	levels[def.id] = upgrade_level(def.id) + 1
	upgrade_levels = levels
	_apply_upgrade(def)
	return true


func _apply_upgrade(def: UpgradeDef) -> void:
	match def.id:
		&"vitality":
			max_health += def.amount
			heal(def.amount)
		&"blade":
			melee_damage += _base_melee_damage * def.amount
		&"archery":
			arrow_damage += _base_arrow_damage * def.amount
		&"quiver":
			max_arrows += int(def.amount)
			arrows = mini(arrows + 15, max_arrows)
		&"drill":
			ally_power += def.amount
			for ally in followers():
				(ally as Ally).refresh_army_bonus()
		&"command":
			follower_cap += int(def.amount)
		&"recruit":
			reserve_soldiers += int(def.amount)
		&"potion":
			heal(def.amount)
		&"arrows":
			arrows = mini(arrows + int(def.amount), max_arrows)
		_:
			push_warning("Upgrade '%s' has no effect in Player._apply_upgrade()" % def.id)


func _flat_dir_to(target: Node3D) -> Vector3:
	var to := target.global_position - global_position
	to.y = 0.0
	return to.normalized() if to.length_squared() > 0.0001 else facing()


func die() -> void:
	if is_dead:
		return
	if GameConfig.downed_enabled and not is_downed:
		_go_down()
		return
	is_downed = false
	clear_aim()
	set_melee_aim(Vector3.ZERO)
	joystick_vector = Vector2.ZERO
	super()


## Respawn (server): back on your feet with your soldiers following again.
func revive(at: Vector3) -> void:
	is_downed = false
	army_order = Order.FOLLOW
	add_to_group(&"player_units")
	super(at)


func take_damage(amount: float, attacker: Node3D = null, is_melee: bool = true, crit: bool = false) -> void:
	if is_downed:
		# Orcs leave downed archers alone; an enemy player (their soldiers or arrows) finishes them.
		if GameConfig.owner_peer_of(attacker) != 0 and GameConfig.is_hostile(self, attacker):
			last_attacker_peer = GameConfig.owner_peer_of(attacker)
			die()
		return
	super(amount, attacker, is_melee, crit)


func heal(amount: float) -> void:
	if not is_downed:
		super(amount)


# --- Downed / revive (server) -------------------------------------------------------

func _go_down() -> void:
	clear_aim()
	set_melee_aim(Vector3.ZERO)
	_pending_shot = Vector3.ZERO
	_bleed_left = BLEED_TIME
	_revive_raw = 0.0
	revive_progress = 0.0
	bleed_seconds = int(BLEED_TIME)
	is_downed = true
	remove_from_group(&"player_units")
	MatchStats.add(peer_id, &"downs")
	went_down.emit(self)


## Teammates close by fill the revive bar (faster with more helpers, and the bleed-out clock
## stops meanwhile); alone, the bar drains and the clock runs.
func _update_downed(delta: float) -> void:
	var helpers: Array = []
	for node in get_tree().get_nodes_in_group(&"players"):
		var other := node as Player
		if other != self and other.team_id == team_id and not GameConfig.is_gone(other) \
				and other.global_position.distance_to(global_position) < REVIVE_RANGE:
			helpers.append(other)
	if helpers.is_empty():
		_revive_raw = maxf(_revive_raw - delta * 0.5, 0.0)
		_bleed_left -= delta
		if _bleed_left <= 0.0:
			die()
			return
	else:
		_revive_raw += delta / REVIVE_TIME * (1.0 + 0.5 * (helpers.size() - 1))
		if _revive_raw >= 1.0:
			_get_up(helpers)
			return
	revive_progress = snappedf(_revive_raw, 0.05)
	bleed_seconds = ceili(_bleed_left)


func _get_up(helpers: Array) -> void:
	is_downed = false
	_revive_raw = 0.0
	revive_progress = 0.0
	health = max_health * REVIVE_HEALTH
	_since_hit = 0.0
	add_to_group(&"player_units")
	for helper in helpers:
		MatchStats.add((helper as Player).peer_id, &"revives")
	revived.emit(self, helpers)


## Every peer: crawl speed, "HELP!" label + revive bar, off-screen marker for teammates.
func _apply_downed() -> void:
	move_speed = _base_move_speed * (DOWNED_SPEED if is_downed else 1.0)
	var show_world_label := _shows_downed_label()
	_downed_label.visible = show_world_label
	_revive_bar.visible = _shows_revive_bar()
	_revive_ring.visible = show_world_label
	if _was_downed and not is_downed and not is_dead:
		HitFx.flash(global_position + Vector3(0, 0.6, 0), HitFx.REVIVE_SPARKLE, Color(0.55, 1.0, 0.6), 2.2, 0.6, Vector2(0.5, 1.4))
	_was_downed = is_downed
	_name_label.position.y = DOWNED_LABEL_HEIGHT if is_downed else health_bar_height + 0.28
	_name_label.offset.y = DOWNED_NAME_OFFSET if is_downed else 0.0
	_health_bar.visible = false
	for item in [_right_item, _left_item]:
		if item:
			item.visible = not is_downed
	if is_downed:
		_aim_indicator.visible = false
		_melee_indicator.visible = false
		play_anim("downed")
	_hold_arms(true)
	var teammate := not is_local() and Net.team_of(Net.my_id()) == team_id
	if is_downed and teammate:
		set_meta(&"marker_color", Color(0.4, 1.0, 0.45))
		set_meta(&"marker_label", "%s down!" % display_name)
		add_to_group(&"tracked")
	else:
		remove_from_group(&"tracked")
	downed_changed.emit(is_downed)


## The downed player sees the HUD card instead of floating labels over their own body.
func _shows_downed_label() -> bool:
	return is_downed and not is_local()


## Only while someone is reviving: an empty bar is just a dark strip.
func _shows_revive_bar() -> bool:
	return _shows_downed_label() and revive_progress > 0.0


func _build_downed_visuals() -> void:
	_downed_label = Label3D.new()
	_downed_label.text = "HELP!"
	_downed_label.font_size = 52
	_downed_label.outline_size = 14
	_downed_label.pixel_size = 0.006
	_downed_label.modulate = Color(0.55, 1.0, 0.55)
	_downed_label.outline_modulate = Color(0.05, 0.15, 0.05, 0.95)
	_downed_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_downed_label.no_depth_test = true
	_downed_label.position = Vector3(0, DOWNED_LABEL_HEIGHT, 0)
	_downed_label.offset = Vector2(0, DOWNED_HELP_OFFSET)
	_downed_label.visible = false
	add_child(_downed_label)
	_revive_bar = HealthBar3D.new()
	_revive_bar.fill_color = Color(0.35, 0.95, 0.4)
	_revive_bar.hide_when_full = false
	_revive_bar.width = 0.8
	_revive_bar.height = 0.1
	_revive_bar.position = Vector3(0, DOWNED_LABEL_HEIGHT, 0)
	add_child(_revive_bar)
	_revive_bar.set_ratio(0.0)
	_revive_bar.visible = false
	# Where teammates must stand to revive (Kenney light mask on the ground).
	_revive_ring = Decal.new()
	_revive_ring.texture_albedo = REVIVE_RING_TEXTURE
	_revive_ring.modulate = Color(0.45, 1.0, 0.5, 0.5)
	_revive_ring.size = Vector3(REVIVE_RANGE * 2.0, 2.0, REVIVE_RANGE * 2.0)
	_revive_ring.visible = false
	add_child(_revive_ring)


# --- Army orders (server) ------------------------------------------------------------

## FOLLOW: formation around the player. CHARGE: run to `point` and fight everything there.
## HOLD: guard `point`.
func command_army(order: int, point: Vector3) -> void:
	if is_dead:
		return
	var offset := point - global_position
	offset.y = 0.0
	army_point = GameConfig.clamp_to_world(global_position + offset.limit_length(MAX_ORDER_DISTANCE))
	army_order = clampi(order, Order.FOLLOW, Order.HOLD)


@rpc("any_peer", "call_remote", "reliable")
func net_command(order: int, point: Vector3) -> void:
	if _from_owner():
		command_army(order, point)
