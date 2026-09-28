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
signal spears_changed(count: int)
signal coins_changed(count: int)
signal upgrades_changed
## Server: this player just went down / was revived (`helpers` = the players who revived them).
signal went_down(player: Player)
signal revived(player: Player, helpers: Array)
## Every peer: the downed state changed (visuals, HUD).
signal downed_changed(downed: bool)
signal army_order_changed(order: int)
## Every peer: the weapon in hand changed (id from WEAPONS).
signal weapon_changed(weapon: String)

enum Order { FOLLOW, CHARGE, HOLD }

const TARGET_GROUPS: Array[StringName] = [&"active_enemies", &"player_units", &"camps"]
const AIM_LINE_WIDTH: float = 0.2
## Aim line length on the ground (arrows fly farther: speed × lifetime of the arrow scene).
const AIM_LINE_LENGTH: float = 5.0
const AIM_LOCK_TEXTURE := preload("res://assets/vfx/light_masks/circle_rings_b.png")
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
## One weapon in hand at a time, at most this many carried (Q / Y / the HUD button cycles them):
## the sword plus the bow and the spear once both are bought.
const MAX_WEAPONS: int = 3
## Weapon id -> how it works. `melee` weapons swing (sword stick / left mouse); the others are aimed
## and fired (bow stick / aim): the bow shoots arrows (ammo), the spear is thrown (no ammo, slower).
## `hand` holds the model; `icon` is a Game Icon Pack glyph. New weapon = a row here + its model in
## `_weapon_items` + a shop item (see `buy_weapon`).
const WEAPONS: Dictionary = {
	"sword": {"melee": true, "hand": ARM_RIGHT, "icon": "sword", "name": "Sword"},
	"bow": {"melee": false, "hand": ARM_LEFT, "icon": "bow", "name": "Bow"},
	"spear": {"melee": false, "hand": ARM_RIGHT, "icon": "spear", "name": "Spear"},
}
const SPEAR_SCENE := preload("res://assets/items/dungeon/spear.glb")
## Procedural sword slash (`_sword_slash`): arm sweep around the shoulder from the holding pose
## (degrees, + = across to the left) and the blade grip while slashing (out along the arm, a bit raised).
const SLASH_WIND_UP: float = -70.0
const SLASH_FOLLOW: float = 85.0
const SLASH_GRIP: Vector3 = Vector3(0, 0, 80)
## Downed archer: the revive bar sits just above the lying body; "HELP!" and the name stack above it
## in screen space (Label3D offsets, pixels), so they never overlap however steep the camera is.
const DOWNED_LABEL_HEIGHT: float = 1.05
const DOWNED_HELP_OFFSET: float = 46.0
const DOWNED_NAME_OFFSET: float = 104.0
## Charge orders reach at most this far from the player.
const MAX_ORDER_DISTANCE: float = 25.0

@export var max_arrows: int = 99
@export var arrow_damage: float = 25.0
@export var shoot_cooldown: float = 0.4
## Thrown spear: hits harder than an arrow, needs no ammo, but throws and flies slower.
@export var spear_damage: float = 35.0
@export var spear_cooldown: float = 1.0
@export var max_spears: int = 8
## Spears in hand when you buy the spear.
@export var spear_start: int = 6
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
## Spear ammo (replicated, like arrows).
var spears: int = 0:
	set(value):
		spears = value
		spears_changed.emit(spears)
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
## Carried weapon ids (at most MAX_WEAPONS, see WEAPONS) and which one is in hand. Always replaced,
## not mutated, so replication notices changes.
var weapons: PackedStringArray = PackedStringArray(["sword"]):
	set(value):
		weapons = value
		if is_node_ready():
			_apply_weapon()
var weapon_index: int = 0:
	set(value):
		if value != weapon_index:
			weapon_index = value
			if is_node_ready():
				_apply_weapon()

var _base_melee_damage: float
var _base_arrow_damage: float
var _base_spear_damage: float
var _shoot_timer: float = 0.0
var _pending_shot: Vector3 = Vector3.ZERO  # aimed shot released during cooldown
var _aim_indicator: Node3D
var _aim_material: StandardMaterial3D
var _aim_lock: MeshInstance3D
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
var _weapon_items: Dictionary = {}  # weapon id -> the model in hand
var _slash_tween: Tween


func _ready() -> void:
	owner_peer = peer_id
	super()
	add_to_group(&"players")
	add_to_group(&"player_units")
	_base_melee_damage = melee_damage
	_base_arrow_damage = arrow_damage
	_base_spear_damage = spear_damage
	_base_move_speed = move_speed
	for looping in ["holding-left", "sit", "crouch"]:
		if anim.has_animation(looping):
			anim.get_animation(looping).loop_mode = Animation.LOOP_LINEAR
	_add_downed_anims()
	_build_aim_indicator()
	_build_melee_indicator()
	_build_name_label()
	_build_downed_visuals()
	_weapon_items = {"sword": _right_item, "bow": _left_item, "spear": _attach_spear()}
	_apply_weapon()
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


## Every peer: sword swings get a swing trail through the hit wedge; spear throws empty the hand briefly.
func _play_action_local(anim_name: String, duration: float, release_arms: int) -> void:
	var sword := anim_name.begins_with("attack-melee") and holds_melee()
	if sword and _right_hold and _right_item and not is_downed:
		_sword_slash(duration)
	else:
		super(anim_name, duration, release_arms)
	if not anim_name.begins_with("attack-melee"):
		return
	if sword:
		get_tree().create_timer(attack_hit_delay / anim_speed * 0.55).timeout.connect(_slash_fx)
	elif current_weapon() == "spear":
		# The spear in hand leaves with the throw and a new one is drawn a moment later.
		get_tree().create_timer(0.15).timeout.connect(_show_spear.bind(false))
		get_tree().create_timer(0.75).timeout.connect(_show_spear.bind(true))


func _show_spear(shown: bool) -> void:
	var spear := _weapon_items.get("spear") as Node3D
	if spear:
		spear.visible = shown and current_weapon() == "spear" and not is_downed


func _slash_fx() -> void:
	if is_dead or not is_inside_tree():
		return
	var forward := facing()
	HitFx.swing_arc(self, 0.5, atan2(forward.x, forward.z), melee_range * 1.25 + 0.3,
			Color(1.0, 0.96, 0.85))


## Sword attack, standing or running: no clip (Kenney's melee clip twists the arm, so the blade pointed
## at the ground or the camera). The arm stays in the holding pose (arm forward, level) and sweeps
## around the shoulder — wind up out to the right, slash across the front, back — while the blade turns
## out along the arm. Damage lands mid-sweep (`attack_hit_delay`).
func _sword_slash(duration: float) -> void:
	_action_time = duration
	_was_acting = true
	_full_body_action = false
	if _arm_tween:
		_arm_tween.kill()
	if _slash_tween:
		_slash_tween.kill()
	_right_hold.influence = 1.0
	_right_item.position = right_hand_offset
	var hit := attack_hit_delay / anim_speed
	var wind := hit * 0.33
	var strike := hit * 0.6
	var back := maxf(duration * 0.95 - wind - strike, 0.05)
	_slash_tween = create_tween()
	_slash_tween.tween_method(_set_slash_yaw, 0.0, SLASH_WIND_UP, wind).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_slash_tween.parallel().tween_property(_right_item, "rotation_degrees", SLASH_GRIP, wind)
	_slash_tween.tween_method(_set_slash_yaw, SLASH_WIND_UP, SLASH_FOLLOW, strike).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_slash_tween.tween_method(_set_slash_yaw, SLASH_FOLLOW, 0.0, back).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_slash_tween.parallel().tween_property(_right_item, "rotation_degrees", right_hand_rotation, back)


## Arm sweep in degrees around the torso's up axis, relative to the holding pose (+ = toward the left).
func _set_slash_yaw(degrees: float) -> void:
	if _right_hold:
		_right_hold.pose_offset = Quaternion(Vector3.UP, deg_to_rad(degrees))


## Only the arm with the weapon in hand holds it; downed archers crawl with both arms.
func _hold_arms(instant: bool = false) -> void:
	if _slash_tween:
		_slash_tween.kill()
		_slash_tween = null
	_set_slash_yaw(0.0)
	super(instant)
	if is_downed:
		_release_arms(ARM_BOTH)
	else:
		_release_arms(ARM_LEFT if _weapon_hand() == ARM_RIGHT else ARM_RIGHT)


# --- Weapons ------------------------------------------------------------------

## Id of the weapon in hand ("" if none).
func current_weapon() -> String:
	return weapons[weapon_index] if weapon_index < weapons.size() else ""


func holds_melee() -> bool:
	return bool(WEAPONS.get(current_weapon(), {}).get("melee", false))


func holds_ranged() -> bool:
	return WEAPONS.has(current_weapon()) and not holds_melee()


## Arm that holds the weapon in hand.
func _weapon_hand() -> int:
	return int(WEAPONS.get(current_weapon(), {}).get("hand", ARM_RIGHT))


## Ammo for the weapon in hand (the sword never runs out).
func has_ammo() -> bool:
	match current_weapon():
		"bow":
			return arrows > 0
		"spear":
			return spears > 0
	return true


## Server: shop purchase of the bow or the spear. Bought weapons stay unlocked: buy both and Q cycles
## sword, bow and spear (kept in WEAPONS order). The new weapon goes straight into your hand.
func buy_weapon(weapon: String) -> void:
	if not WEAPONS.has(weapon) or weapon == "sword" or weapons.has(weapon):
		return
	var carried := PackedStringArray()
	for id: String in WEAPONS:
		if weapons.has(id) or id == weapon:
			carried.append(id)
	weapons = carried
	weapon_index = carried.find(weapon)
	if weapon == "spear":
		spears = maxi(spears, spear_start)
	_apply_weapon()


## The spear model in the right hand (carried like the orc spearmen), hidden until it's the weapon in hand.
func _attach_spear() -> Node3D:
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return null
	var spear := _attach_item(skeleton, SPEAR_SCENE, "arm-right")
	if spear:
		spear.position = Vector3(-0.27, -0.2, 0.0)
		spear.visible = false
	return spear


## The carried weapon that isn't in hand ("" with a single weapon).
func other_weapon() -> String:
	return weapons[(weapon_index + 1) % weapons.size()] if weapons.size() > 1 else ""


## Server: next carried weapon in hand. Cancels aiming / swinging with the old one.
func switch_weapon() -> void:
	if is_dead or is_downed or weapons.size() < 2:
		return
	weapon_index = (weapon_index + 1) % weapons.size()


## Server: pick up `weapon` — take it in hand if already carried, else carry it (replacing the one in
## hand when both slots are full).
func give_weapon(weapon: String) -> void:
	if not WEAPONS.has(weapon):
		return
	var carried := weapons.duplicate()
	var slot := carried.find(weapon)
	if slot == -1:
		if carried.size() < MAX_WEAPONS:
			carried.append(weapon)
			slot = carried.size() - 1
		else:
			slot = weapon_index
			carried[slot] = weapon
	weapons = carried
	weapon_index = slot
	_apply_weapon()


## Local input: switch now on the server / host, or ask the server.
func request_switch_weapon() -> void:
	if multiplayer.is_server():
		switch_weapon()
	else:
		net_switch_weapon.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func net_switch_weapon() -> void:
	if _from_owner():
		switch_weapon()


## Every peer: only the weapon in hand is visible (none while downed), its arm holds it.
func _apply_weapon() -> void:
	for weapon in _weapon_items:
		var item := _weapon_items[weapon] as Node3D
		if item:
			item.visible = weapon == current_weapon() and not is_downed
	if not holds_ranged():
		clear_aim()
		_pending_shot = Vector3.ZERO
	if not holds_melee():
		set_melee_aim(Vector3.ZERO)
	if _right_hold or _left_hold:
		_hold_arms(true)
	weapon_changed.emit(current_weapon())


func _idle_anim() -> String:
	if is_downed:
		return "downed"
	return "holding-left" if is_aiming() else "idle"


func _move_anim(strength: float) -> String:
	return "crawl" if is_downed else super(strength)


func _can_hit(target: Object) -> bool:
	var node := target as Node
	return node != null and (GameConfig.is_hostile(self, node) or node.is_in_group(&"choppable") or node.is_in_group(&"breakable"))


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
	if is_dead or is_downed or _melee_timer > 0.0 or not holds_melee():
		return
	var target := find_nearest(TARGET_GROUPS, 1.8, global_position, {&"camps": -0.8})
	if target:
		face_now(_flat_dir_to(target))
	melee()


## Swing toward `direction` (sword stick), with a little aim assist. Movement is independent.
func attack_melee_toward(direction: Vector3) -> void:
	if is_dead or is_downed or _melee_timer > 0.0 or not holds_melee():
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
	if direction.length_squared() < 0.0001 or is_dead or is_downed or not holds_melee():
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
	if is_dead or is_downed or direction.length_squared() < 0.0001 or not holds_ranged():
		return
	direction.y = 0.0
	direction = direction.normalized()
	look_override = direction
	_aim_indicator.rotation.y = atan2(direction.x, direction.z)
	_aim_material.albedo_color = Color.WHITE if has_ammo() else Color(1, 0.35, 0.3)
	_aim_indicator.visible = is_local()
	if is_local():
		_update_aim_lock(direction)


func clear_aim() -> void:
	look_override = Vector3.ZERO
	_aim_indicator.visible = false
	if _aim_lock:
		_aim_lock.visible = false


func is_aiming() -> bool:
	return look_override != Vector3.ZERO


## Fires the ranged weapon in hand (arrow, or a thrown spear) toward `direction`, or at the nearest
## enemy when no direction is given. Server only.
func shoot(direction: Vector3 = Vector3.ZERO) -> void:
	if is_dead or is_downed or not has_ammo() or not holds_ranged():
		return
	if _shoot_timer > 0.0:
		if direction != Vector3.ZERO:
			_pending_shot = direction
		return
	var spear := current_weapon() == "spear"
	_shoot_timer = spear_cooldown if spear else shoot_cooldown
	if spear:
		spears -= 1
	else:
		arrows -= 1
	if direction == Vector3.ZERO:
		var target := find_nearest(TARGET_GROUPS, aim_range, global_position, {&"camps": 3.0})
		direction = _flat_dir_to(target) if target else facing()
	else:
		direction.y = 0.0
		direction = _assisted(direction.normalized())
	face_now(direction)
	var crit := randf() < crit_chance
	var multiplier := crit_multiplier if crit else 1.0
	var from := global_position + Vector3(0, 0.55, 0) + direction * 0.4
	if spear:
		play_action("attack-melee-right", 0.4, ARM_RIGHT)
		NetSpawn.projectile(&"player_spear", from + Vector3(0, 0.15, 0), direction, spear_damage * multiplier, self, crit)
	else:
		play_action("holding-left-shoot", 0.25, ARM_LEFT)
		NetSpawn.projectile(&"arrow", from, direction, arrow_damage * multiplier, self, crit)


## Nudges an aimed direction onto an enemy that is almost in line with it.
func _assisted(direction: Vector3) -> Vector3:
	var target := _assist_target(direction)
	if target == null:
		return direction
	var to := target.global_position - global_position
	to.y = 0.0
	return to.normalized()


## The enemy an aimed shot toward `direction` snaps to — or, with no enemy in line, a chest (or
## other breakable) — null if none.
func _assist_target(direction: Vector3) -> Node3D:
	var best: Node3D = null
	var best_angle := deg_to_rad(aim_assist_degrees)
	for group in TARGET_GROUPS:
		for node in get_tree().get_nodes_in_group(group):
			if node != self and GameConfig.is_hostile(self, node) and _assist_angle(direction, node) < best_angle:
				best_angle = _assist_angle(direction, node)
				best = node
	if best == null:
		for node in get_tree().get_nodes_in_group(&"breakable"):
			if _assist_angle(direction, node) < best_angle:
				best_angle = _assist_angle(direction, node)
				best = node
	return best


## Angle between `direction` and a live `node` within aim range (INF if gone or out of range).
func _assist_angle(direction: Vector3, node: Node) -> float:
	if GameConfig.is_gone(node):
		return INF
	var to := (node as Node3D).global_position - global_position
	to.y = 0.0
	if to.length() > aim_range or to.length() < 0.1:
		return INF
	return direction.angle_to(to)


## Short tapered aim line that fades out, with an arrowhead (the arrow flies farther), plus a ring that
## locks onto the enemy the aim assist will hit. Local player only.
func _build_aim_indicator() -> void:
	_aim_material = StandardMaterial3D.new()
	_aim_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_aim_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_aim_material.vertex_color_use_as_albedo = true
	_aim_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_aim_material.albedo_color = Color.WHITE
	_aim_indicator = Node3D.new()
	_aim_indicator.visible = false
	add_child(_aim_indicator)
	# Along +Z (models face +Z, so rotation.y uses the same atan2(x, z) as facing).
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _aim_material)
	var start := 0.55
	var head := AIM_LINE_LENGTH - 0.5
	var steps := 10
	for i in steps:
		var z0 := lerpf(start, head, float(i) / steps)
		var z1 := lerpf(start, head, float(i + 1) / steps)
		var w0 := lerpf(AIM_LINE_WIDTH, AIM_LINE_WIDTH * 0.35, float(i) / steps) * 0.5
		var w1 := lerpf(AIM_LINE_WIDTH, AIM_LINE_WIDTH * 0.35, float(i + 1) / steps) * 0.5
		var c0 := Color(1, 1, 1, lerpf(0.6, 0.18, float(i) / steps))
		var c1 := Color(1, 1, 1, lerpf(0.6, 0.18, float(i + 1) / steps))
		_aim_quad(mesh, Vector3(-w0, 0.05, z0), Vector3(w0, 0.05, z0), Vector3(w1, 0.05, z1), Vector3(-w1, 0.05, z1), c0, c1)
	# Arrowhead (chevron) at the end.
	var tip_color := Color(1, 1, 1, 0.75)
	for side in [-1.0, 1.0]:
		var outer := Vector3(side * 0.32, 0.05, head - 0.05)
		var inner := Vector3(side * 0.2, 0.05, head - 0.12)
		mesh.surface_set_color(tip_color)
		mesh.surface_add_vertex(Vector3(0, 0.05, AIM_LINE_LENGTH))
		mesh.surface_add_vertex(outer)
		mesh.surface_add_vertex(inner)
		mesh.surface_add_vertex(Vector3(0, 0.05, AIM_LINE_LENGTH))
		mesh.surface_add_vertex(inner)
		mesh.surface_add_vertex(Vector3(0, 0.05, AIM_LINE_LENGTH - 0.14))
	mesh.surface_end()
	var line := MeshInstance3D.new()
	line.mesh = mesh
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aim_indicator.add_child(line)
	# Target lock ring (top level: sits under the target, not on the rotating line).
	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.albedo_texture = AIM_LOCK_TEXTURE
	ring_material.albedo_color = Color(1.0, 0.85, 0.4, 0.9)
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	quad.material = ring_material
	_aim_lock = MeshInstance3D.new()
	_aim_lock.mesh = quad
	_aim_lock.top_level = true
	_aim_lock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aim_lock.visible = false
	add_child(_aim_lock)


func _aim_quad(mesh: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3, d: Vector3, near: Color, far: Color) -> void:
	for vertex in [[a, near], [b, near], [c, far], [a, near], [c, far], [d, far]]:
		mesh.surface_set_color(vertex[1])
		mesh.surface_add_vertex(vertex[0])


## Local aim visuals: lock ring under the assisted target (spins slowly), or hidden.
func _update_aim_lock(direction: Vector3) -> void:
	var target := _assist_target(direction)
	_aim_lock.visible = target != null
	if target:
		var size := 1.2 * sqrt(maxf(Unit.target_radius(target), 0.35) / 0.35)
		_aim_lock.global_position = target.global_position + Vector3(0, 0.06, 0)
		_aim_lock.scale = Vector3(size, 1.0, size)
		_aim_lock.rotation.y = Time.get_ticks_msec() * 0.002


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
			return weapons.has("bow") and arrows < max_arrows
		Pickup.Kind.SPEARS:
			return weapons.has("spear") and spears < max_spears
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
		Pickup.Kind.SPEARS:
			spears = mini(spears + amount, max_spears)
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
		&"weapon_bow":
			return not weapons.has("bow")
		&"weapon_spear":
			return not weapons.has("spear")
		&"potion":
			return health < max_health
		&"arrows":
			return weapons.has("bow") and arrows < max_arrows
		&"quiver":
			return weapons.has("bow")
		&"archery":
			return weapons.has("bow") or weapons.has("spear")
		&"spears":
			return weapons.has("spear") and spears < max_spears
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
			spear_damage += _base_spear_damage * def.amount
		&"weapon_bow":
			buy_weapon("bow")
		&"weapon_spear":
			buy_weapon("spear")
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
		&"spears":
			spears = mini(spears + int(def.amount), max_spears)
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
	_apply_weapon()
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
