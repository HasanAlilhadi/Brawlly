class_name Player
extends Unit
## A player's hero (one per connected player), of the class picked in the lobby (`class_def`, see
## ClassDef): Swordsman (sword), Spearman (spear thrust; E switches to throwing spears) or Bowman (bow).
## Each class fights only with its own weapons, and nothing runs out of ammo. Moves with the joystick.
## Melee weapons swing / thrust toward the aim stick (keeps attacking while held, even while running another
## way); ranged ones aim and fire on release. A tap auto-targets the nearest enemy.
##
## Multiplayer: the server simulates every player. Input arrives through `set_input()` (host) or the
## `net_*` RPCs (clients → server). Stats (coins, …) are replicated back via the Sync node.
##
## Downed (when GameConfig.downed_enabled, i.e. online co-op / team modes): at 0 health the hero
## crawls for BLEED_TIME seconds instead of dying. A teammate standing close for REVIVE_TIME brings
## them back; orcs leave downed players alone, but an enemy player can finish them.
## Army orders: `command_army()` tells this player's soldiers to follow, charge a point or hold a point.

signal coins_changed(count: int)
signal upgrades_changed
## Server: this player just went down / was revived (`helpers` = the players who revived them).
signal went_down(player: Player)
signal revived(player: Player, helpers: Array)
## Every peer: the downed state changed (visuals, HUD).
signal downed_changed(downed: bool)
signal army_order_changed(order: int)
## Every peer: a trained soldier is waiting in the barracks pen.
signal soldier_ready
## Every peer: the weapon in hand changed (id from WEAPONS).
signal weapon_changed(weapon: String)

## KILL: every soldier hunts `army_target` down (then they charge where it fell).
enum Order { FOLLOW, CHARGE, HOLD, KILL }

const TARGET_GROUPS: Array[StringName] = [&"active_enemies", &"player_units", &"camps"]
const AIM_LINE_WIDTH: float = 0.2
## Aim line length on the ground (arrows fly farther: speed × lifetime of the arrow scene).
const AIM_LINE_LENGTH: float = 5.0
## Aimed sword swings snap to an enemy within this angle / distance.
const MELEE_ASSIST_DEGREES: float = 35.0
const MELEE_ASSIST_RANGE: float = 2.4
const CATALOG := preload("res://resources/data/upgrade_catalog.tres")
const BLEED_TIME: float = 15.0
const REVIVE_TIME: float = 3.0
## Seconds between soldiers filing out of a barracks pen.
const EXIT_INTERVAL: float = 0.2
const REVIVE_RANGE: float = 1.8
## Health fraction after a revive.
const REVIVE_HEALTH: float = 0.4
## Crawl speed while downed (fraction of move_speed).
const DOWNED_SPEED: float = 0.3
## "crawl" (moving) and "downed" (lying still) clips, made in Blender on the archer's armature.
const DOWNED_ANIMS := preload("res://assets/characters/animations/archer_downed.glb")
const DOWNED_CLIPS: Array[String] = ["crawl", "downed"]
const REVIVE_RING_TEXTURE := preload("res://assets/vfx/light_masks/ring_a.png")
## Weapon id -> how it works. `melee` weapons swing (sword stick / left mouse) and hit the aim wedge:
## `arc` degrees wide, out to `reach` m, every `cooldown` s. The others are aimed and fired (bow stick /
## aim): the bow shoots arrows, the javelin throws the spear (slower, harder). No ammo. The class
## (ClassDef.weapons) decides what a player carries; E / Y / the HUD button cycles them. `hand` holds the
## model; `icon` is a Game Icon Pack glyph. New weapon = a row here + its model in `_weapon_items`.
const WEAPONS: Dictionary = {
	"sword": {"melee": true, "hand": ARM_RIGHT, "icon": "sword", "name": "Sword", "arc": 80.0, "reach": 1.55,
			"cooldown": 0.5},
	"spear": {"melee": true, "hand": ARM_RIGHT, "icon": "spear", "name": "Spear", "arc": 28.0, "reach": 2.4,
			"cooldown": 0.7},
	"javelin": {"melee": false, "hand": ARM_RIGHT, "icon": "spear", "name": "Throw"},
	"bow": {"melee": false, "hand": ARM_LEFT, "icon": "bow", "name": "Bow"},
}
const SPEAR_SCENE := preload("res://assets/items/dungeon/spear.glb")
## Procedural sword slash (`_sword_slash`), keyed carry → wind-up → mid-cut → follow-through → carry:
## arm sweep around the torso (degrees, + = across to the left), arm raised above level (a diagonal
## cut, high left to low right), body twist (degrees) and lunge (m), and where the blade points in the
## body's space (+X left, +Y up, +Z forward; the first / last key is the carry grip). The blade stays
## flat side up, so the cut reads from the top-down camera.
const SLASH_YAW: Array[float] = [0.0, 80.0, 5.0, -75.0, 0.0]
const SLASH_RAISE: Array[float] = [0.0, 30.0, 10.0, -8.0, 0.0]
const SLASH_TWIST: Array[float] = [0.0, 22.0, 0.0, -25.0, 0.0]
const SLASH_LUNGE: Array[float] = [0.0, -0.04, 0.07, 0.1, 0.0]
const SLASH_BLADE: Array[Vector3] = [Vector3.ZERO, Vector3(0.55, 0.35, -0.75), Vector3(-0.3, 0.05, 1.0),
		Vector3(-0.95, -0.1, -0.3), Vector3.ZERO]
## Procedural spear thrust (`_spear_thrust`), keyed carry → draw back → full thrust → carry: how far the
## spear slides along its shaft (m, + = toward the tip), how level it is (0 carry grip, upright; 1 pointing
## straight ahead), body lunge (m) and twist (degrees). The arm stays in its holding pose.
const THRUST_PUSH: Array[float] = [0.0, -0.1, 0.14, 0.0]
const THRUST_LEVEL: Array[float] = [0.0, 1.0, 1.0, 0.0]
const THRUST_LUNGE: Array[float] = [0.0, -0.06, 0.2, 0.0]
const THRUST_TWIST: Array[float] = [0.0, 14.0, -6.0, 0.0]
## Spear carry grip (arm bone space, like the orc spearmen) and the point on its shaft held in the fist.
const SPEAR_CARRY: Vector3 = Vector3(-0.27, -0.2, 0.0)
const SPEAR_GRIP: Vector3 = Vector3(0.0, 0.2, 0.0)
## Downed player: the revive bar sits just above the lying body; "HELP!" and the name stack above it
## in screen space (Label3D offsets, pixels), so they never overlap however steep the camera is.
const DOWNED_LABEL_HEIGHT: float = 1.05
const DOWNED_HELP_OFFSET: float = 46.0
const DOWNED_NAME_OFFSET: float = 104.0
## Charge orders reach at most this far from the player.
const MAX_ORDER_DISTANCE: float = 25.0
## A kill order takes the enemy within this distance of the ordered point (the client sends the enemy's position).
const KILL_PICK_RADIUS: float = 2.0
## What a kill order can target (hostile ones only).
const KILL_GROUPS: Array[StringName] = [&"active_enemies", &"enemies", &"player_units", &"camps"]

@export var arrow_damage: float = 25.0
@export var shoot_cooldown: float = 0.4
## Spear: thrusts (melee) and throws (javelin) deal this; throws are slower than arrows.
@export var spear_damage: float = 35.0
@export var spear_cooldown: float = 1.0
@export var aim_range: float = 12.0
## Middle of the sword's handle (model space): the slash turns the blade around it, so it stays in the fist.
@export var sword_grip_point: Vector3 = Vector3(0.0, 0.027, 0.0)
@export var arrow_scene: PackedScene
## Chance and multiplier for critical hits (every weapon).
@export_range(0.0, 1.0) var crit_chance: float = 0.15
@export var crit_multiplier: float = 1.8

## Network id of the player controlling this hero (set at spawn).
var peer_id: int = 1
var display_name: String = "Player"
## The class (set at spawn on every peer with `set_class()`, before entering the tree).
var class_def: ClassDef
## Movement input (screen axes), set from the HUD / network.
var joystick_vector: Vector2 = Vector2.ZERO
## Soldier health/damage multiplier (raised by the "drill" upgrade). Server only.
var ally_power: float = 1.0

# --- Replicated stats (see the Sync node) ---
var coins: int = 0:
	set(value):
		coins = value
		coins_changed.emit(coins)
## Soldiers bought at the barracks that are still training (replicated). They train one after another,
## GameConfig.SOLDIER_TRAIN_TIME seconds each, then wait in the pen until the player takes them (collect_soldiers).
var soldiers_training: int = 0:
	set(value):
		value = maxi(value, 0)
		# Every peer keeps a copy of the countdowns for the barracks sign / shop (server: the real ones).
		while _training_left.size() < value:
			_training_left.append(GameConfig.SOLDIER_TRAIN_TIME)
		while _training_left.size() > value:
			_training_left.remove_at(0)
		soldiers_training = value
## Max army size: following + in the pen + in training (raised by the "command" upgrade).
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
## Revive progress 0..1 (quantized, replicated for the bar over the downed player).
var revive_progress: float = 0.0:
	set(value):
		revive_progress = value
		if _revive_bar:
			_revive_bar.set_ratio(value)
			_revive_bar.visible = _shows_revive_bar()
## Whole seconds left before a downed player bleeds out (replicated for the HUD / label).
var bleed_seconds: int = 0:
	set(value):
		bleed_seconds = value
		if _downed_label:
			_downed_label.text = "HELP!  %d" % value
## Seconds left for each soldier in training, oldest first (only the first one counts down).
var _training_left: Array[float] = []
## Server: the barracks each soldier in training was bought at (its pen), same order.
var _training_stalls: Array[ShopStation] = []
var army_order: int = Order.FOLLOW:
	set(value):
		if value != army_order:
			army_order = value
			army_order_changed.emit(value)
## Where soldiers charge to / hold (valid for CHARGE and HOLD; KILL: where the target was when ordered).
var army_point: Vector3 = Vector3.ZERO
## Server: the enemy (unit or camp) a KILL order hunts.
var army_target: Node3D
## Replicated: path of `army_target` (empty unless KILL), so the owner sees a mark over it.
var army_target_path: NodePath = NodePath()
## Server: +1 on every order (also the same one again), so soldiers drop what they're doing and obey.
var order_serial: int = 0
## Carried weapon ids (see WEAPONS; from the class) and which one is in hand. Always replaced, not
## mutated, so replication notices changes.
var weapons: PackedStringArray = PackedStringArray(["sword"]):
	set(value):
		weapons = value
		if is_node_ready() and _melee_indicator:
			_apply_weapon()
var weapon_index: int = 0:
	set(value):
		if value != weapon_index:
			weapon_index = value
			if is_node_ready() and _melee_indicator:
				_apply_weapon()

var _base_melee_damage: float
var _base_arrow_damage: float
var _base_spear_damage: float
var _shoot_timer: float = 0.0
var _pending_shot: Vector3 = Vector3.ZERO  # aimed shot released during cooldown
var _aim_indicator: Node3D
var _aim_material: StandardMaterial3D
var _melee_aim: Vector3 = Vector3.ZERO
var _melee_indicator: Node3D
var _melee_wedge: ConvexPolygonShape3D
var _melee_wedge_weapon: String = ""
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
var _slash_skeleton: Skeleton3D
var _slash_skeleton_rest: Transform3D
var _slash_raise_axis: Vector3 = Vector3.RIGHT
var _slash_torso: int = -1
var _slash_carry: Quaternion = Quaternion.IDENTITY  # carry grip in the skeleton's space


## Every peer, at spawn and before entering the tree: the class's model (replaces the scene's
## Model), weapons, weapon models and player-color key hue.
func set_class(class_id: StringName) -> void:
	class_def = ClassDef.find(class_id)
	var old := get_node("Model") as Node3D
	var body := class_def.model.instantiate() as Node3D
	body.name = "Model"
	body.transform = old.transform
	var index := old.get_index()
	remove_child(old)
	old.free()
	add_child(body)
	move_child(body, index)
	weapons = class_def.weapons
	weapon_index = 0
	if not weapons.has("sword"):
		right_hand_item = null
	if not weapons.has("bow"):
		left_hand_item = null
		hold_left_arm = false
	right_hand_offset += class_def.hand_offset
	right_swing_offset += class_def.hand_offset
	left_hand_offset += class_def.hand_offset
	var melee := _melee_weapon()
	if melee != "":
		melee_cooldown = WEAPONS[melee].cooldown
	recolor_key_hue = class_def.recolor_key_hue
	recolor_hue_range = class_def.recolor_hue_range
	recolor_min_saturation = class_def.recolor_min_saturation
	recolor_reference_value = class_def.recolor_reference_value


func _ready() -> void:
	owner_peer = peer_id
	if class_def == null:
		# Not spawned (e.g. a menu preview): the default class.
		set_class(&"")
		model = $Model
		anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
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
	var spear := _attach_spear() if weapons.has("spear") or weapons.has("javelin") else null
	_weapon_items = {"sword": _right_item, "bow": _left_item, "spear": spear, "javelin": spear}
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


## Copies the crawl clips into the model's animation library (shared by every hero of the class, so
## once). They were made on the archer; every class has the same bones, so only the skeleton's path changes.
func _add_downed_anims() -> void:
	var library := anim.get_animation_library(&"")
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if library == null or skeleton == null or library.has_animation(DOWNED_CLIPS[0]):
		return
	var skeleton_path := String(anim.get_node(anim.root_node).get_path_to(skeleton))
	var source := DOWNED_ANIMS.instantiate()
	var source_anim := source.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for clip_name in DOWNED_CLIPS:
		if source_anim and source_anim.has_animation(clip_name):
			var clip := source_anim.get_animation(clip_name).duplicate() as Animation
			clip.loop_mode = Animation.LOOP_LINEAR
			for track in clip.get_track_count():
				var bone := String(clip.track_get_path(track)).get_slice(":", 1)
				clip.track_set_path(track, NodePath("%s:%s" % [skeleton_path, bone]))
			library.add_animation(clip_name, clip)
	source.free()


## Every peer: sword swings and spear thrusts get a trail through the hit wedge; spear throws empty the
## hand briefly.
func _play_action_local(anim_name: String, duration: float, release_arms: int) -> void:
	var melee := anim_name.begins_with("attack-melee") and holds_melee()
	if melee and current_weapon() == "sword" and _right_hold and _right_item and not is_downed:
		_sword_slash(duration)
	elif melee and current_weapon() == "spear" and _right_hold and _weapon_items.get("spear") and not is_downed:
		_spear_thrust(duration)
	else:
		super(anim_name, duration, release_arms)
	if not anim_name.begins_with("attack-melee"):
		return
	if melee:
		get_tree().create_timer(attack_hit_delay / anim_speed * 0.55).timeout.connect(_slash_fx)
	elif current_weapon() == "javelin":
		# The spear in hand leaves with the throw and a new one is drawn a moment later.
		get_tree().create_timer(0.15).timeout.connect(_show_spear.bind(false))
		get_tree().create_timer(0.75).timeout.connect(_show_spear.bind(true))


func _show_spear(shown: bool) -> void:
	var spear := _weapon_items.get("spear") as Node3D
	if spear:
		spear.visible = shown and _weapon_items.get(current_weapon()) == spear and not is_downed


func _slash_fx() -> void:
	if is_dead or not is_inside_tree():
		return
	# The trail covers the hit wedge (the server knows where the swing started; other peers use the facing).
	var forward := _melee_dir if multiplayer.is_server() and _melee_dir != Vector3.ZERO else facing()
	HitFx.swing_arc(self, 0.5, atan2(forward.x, forward.z), melee_reach(), Color(1.0, 0.96, 0.85),
			melee_arc())


## Sword attack, standing or running: no clip (Kenney's melee clip twists the arm, so the blade pointed
## at the ground or the camera). The arm starts from the holding pose and runs through the `SLASH_*` keys:
## a slower wind-up, raised and across to the left, then a fast diagonal cut out to the right (like the
## swing trail) with the blade snapping straight out and the body twisting and stepping into it, then
## back. Damage lands in the fast part of the cut (`attack_hit_delay`).
func _sword_slash(duration: float) -> void:
	_action_time = duration
	_was_acting = true
	_full_body_action = false
	if _arm_tween:
		_arm_tween.kill()
	if _slash_tween:
		_slash_tween.kill()
	_find_slash_skeleton()
	# Raise the arm in its own vertical plane: around the axis across the held arm (it points along -X).
	var arm := _right_hold.get_held_rotation() * Vector3.LEFT
	arm.y = 0.0
	if arm.length_squared() > 0.0001:
		_slash_raise_axis = arm.normalized().cross(Vector3.UP)
	_slash_carry = Quaternion(_slash_arm_basis(Quaternion.IDENTITY) * Basis.from_euler(right_hand_rotation * (PI / 180.0)))
	_right_hold.influence = 1.0
	var hit := attack_hit_delay / anim_speed
	var wind := hit * 0.5
	var strike := hit * 0.75
	var back := maxf(duration * 0.95 - wind - strike, 0.05)
	_slash_pose(0.0)
	_slash_tween = create_tween()
	_slash_tween.tween_method(_slash_pose, 0.0, 1.0, wind).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_slash_tween.tween_method(_slash_pose, 1.0, 3.0, strike).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_slash_tween.tween_method(_slash_pose, 3.0, 4.0, back).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## The skeleton the slash / thrust poses (and its rest transform, for the lunge / twist).
func _find_slash_skeleton() -> void:
	if _slash_skeleton == null:
		_slash_skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
		if _slash_skeleton:
			_slash_skeleton_rest = _slash_skeleton.transform
			_slash_torso = _slash_skeleton.get_bone_parent(_slash_skeleton.find_bone("arm-right"))


## Spear attack, standing or running: no clip (Kenney's melee clip swings the spear at the ground). The
## arm keeps its holding pose; the spear tips level, draws back, then shoots forward along its shaft as
## the body lunges into it, and back (`THRUST_*` keys). Damage lands in the fast part (`attack_hit_delay`).
func _spear_thrust(duration: float) -> void:
	_action_time = duration
	_was_acting = true
	_full_body_action = false
	if _arm_tween:
		_arm_tween.kill()
	if _slash_tween:
		_slash_tween.kill()
	_find_slash_skeleton()
	if _slash_skeleton == null:
		return
	_right_hold.influence = 1.0
	_right_hold.pose_offset = Quaternion.IDENTITY
	var hit := attack_hit_delay / anim_speed
	var draw := hit * 0.6
	var strike := hit * 0.4 + 0.05
	var back := maxf(duration * 0.95 - draw - strike, 0.05)
	_thrust_pose(0.0)
	_slash_tween = create_tween()
	_slash_tween.tween_method(_thrust_pose, 0.0, 1.0, draw).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_slash_tween.tween_method(_thrust_pose, 1.0, 2.0, strike).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_slash_tween.tween_method(_thrust_pose, 2.0, 3.0, back).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Thrust pose at `phase` (0 carry, 1 drawn back, 2 full thrust, 3 carry): blends the `THRUST_*` keys.
func _thrust_pose(phase: float) -> void:
	var spear := _weapon_items.get("spear") as Node3D
	if spear == null or _slash_skeleton == null or _right_hold == null:
		return
	var i := clampi(int(phase), 0, THRUST_PUSH.size() - 2)
	var t := clampf(phase - i, 0.0, 1.0)
	var key := func(keys: Array[float]) -> float: return lerpf(keys[i], keys[i + 1], t)
	# Level: the shaft (spear +Y) along the body's forward (+Z), in the arm bone's space.
	var level := _slash_arm_basis(Quaternion.IDENTITY).inverse() * Basis(Vector3.RIGHT, PI * 0.5)
	var grip := Basis(Quaternion.IDENTITY.slerp(Quaternion(level.orthonormalized()), key.call(THRUST_LEVEL)))
	var fist := SPEAR_CARRY + SPEAR_GRIP + class_def.hand_offset
	spear.basis = grip
	spear.position = fist - grip * SPEAR_GRIP + grip * Vector3(0.0, key.call(THRUST_PUSH), 0.0)
	_slash_skeleton.transform = _slash_skeleton_rest * Transform3D(
			Basis(Vector3.UP, deg_to_rad(key.call(THRUST_TWIST))), Vector3(0.0, 0.0, key.call(THRUST_LUNGE)))


## Slash pose at `phase` (0 carry, 1 wind-up, 2 mid-cut, 3 follow-through, 4 carry): blends the `SLASH_*` keys.
func _slash_pose(phase: float) -> void:
	var i := clampi(int(phase), 0, SLASH_YAW.size() - 2)
	var t := clampf(phase - i, 0.0, 1.0)
	var key := func(keys: Array[float]) -> float: return lerpf(keys[i], keys[i + 1], t)
	var offset := Quaternion(Vector3.UP, deg_to_rad(key.call(SLASH_YAW))) \
			* Quaternion(_slash_raise_axis, deg_to_rad(key.call(SLASH_RAISE)))
	if _right_hold:
		_right_hold.pose_offset = offset
	if _right_item and _slash_skeleton:
		var blade := _slash_blade(i).slerp(_slash_blade(i + 1), t)
		var grip := _slash_arm_basis(offset).inverse() * Basis(blade)
		var fist := right_hand_offset + Basis.from_euler(right_hand_rotation * (PI / 180.0)) * sword_grip_point
		_right_item.basis = grip
		_right_item.position = fist - grip * sword_grip_point
	if _slash_skeleton:
		_slash_skeleton.transform = _slash_skeleton_rest * Transform3D(
				Basis(Vector3.UP, deg_to_rad(key.call(SLASH_TWIST))), Vector3(0.0, 0.0, key.call(SLASH_LUNGE)))


## The sword's orientation in the skeleton's space at `SLASH_BLADE` key `index`: blade (model -Y) along the
## key's direction, flat side up; the first / last key is the carry grip.
func _slash_blade(index: int) -> Quaternion:
	var direction := SLASH_BLADE[index]
	if direction == Vector3.ZERO:
		return _slash_carry
	var y := -direction.normalized()
	var z := (Vector3.UP - y * y.dot(Vector3.UP)).normalized()
	return Quaternion(Basis(y.cross(z), y, z))


## The right arm bone's rotation in the skeleton's space with `offset` on top of the held pose.
func _slash_arm_basis(offset: Quaternion) -> Basis:
	var torso := _slash_skeleton.get_bone_global_pose(_slash_torso).basis.orthonormalized() \
			if _slash_torso >= 0 else Basis.IDENTITY
	return torso * Basis(offset * _right_hold.get_held_rotation())


## Only the arm with the weapon in hand holds it; downed players crawl with both arms.
func _hold_arms(instant: bool = false) -> void:
	if _slash_tween:
		_slash_tween.kill()
		_slash_tween = null
	if _slash_skeleton:
		_slash_pose(0.0)
		_thrust_pose(0.0)
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


## The class's melee weapon ("" for the Bowman): its wedge is the aim / hit area.
func _melee_weapon() -> String:
	for weapon in weapons:
		if WEAPONS.has(weapon) and WEAPONS[weapon].melee:
			return weapon
	return ""


## Width in degrees of the melee hit wedge (`_melee_indicator`).
func melee_arc() -> float:
	return float(WEAPONS.get(_melee_weapon(), WEAPONS.sword).arc)


## The spear model in the right hand (carried like the orc spearmen), hidden unless the spear is in hand.
func _attach_spear() -> Node3D:
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return null
	var spear := _attach_item(skeleton, SPEAR_SCENE, "arm-right")
	if spear:
		spear.position = SPEAR_CARRY + class_def.hand_offset
		spear.visible = false
	return spear


## The carried weapon that isn't in hand ("" with a single weapon).
func other_weapon() -> String:
	return weapons[(weapon_index + 1) % weapons.size()] if weapons.size() > 1 else ""


## Server: next carried weapon in hand (the Spearman: thrust <-> throw). Cancels aiming / swinging with the old one.
func switch_weapon() -> void:
	if is_dead or is_downed or weapons.size() < 2:
		return
	weapon_index = (weapon_index + 1) % weapons.size()


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
	var in_hand: Node3D = _weapon_items.get(current_weapon())
	for weapon in _weapon_items:
		var item := _weapon_items[weapon] as Node3D
		if item:
			item.visible = item == in_hand and not is_downed
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

## Shows the aim line (local player) and turns the hero toward `direction` (XZ plane).
func set_aim(direction: Vector3) -> void:
	if is_dead or is_downed or direction.length_squared() < 0.0001 or not holds_ranged():
		return
	direction.y = 0.0
	direction = direction.normalized()
	look_override = direction
	_aim_indicator.rotation.y = atan2(direction.x, direction.z)
	_aim_indicator.visible = is_local()


func clear_aim() -> void:
	look_override = Vector3.ZERO
	_aim_indicator.visible = false


func is_aiming() -> bool:
	return look_override != Vector3.ZERO


## Fires the ranged weapon in hand (arrow, or a thrown spear) toward `direction`, or at the nearest
## enemy when no direction is given. Server only.
func shoot(direction: Vector3 = Vector3.ZERO) -> void:
	if is_dead or is_downed or not holds_ranged():
		return
	if _shoot_timer > 0.0:
		if direction != Vector3.ZERO:
			_pending_shot = direction
		return
	var spear := current_weapon() == "javelin"
	_shoot_timer = spear_cooldown if spear else shoot_cooldown
	if direction == Vector3.ZERO:
		var target := find_nearest(TARGET_GROUPS, aim_range, global_position, {&"camps": 3.0})
		direction = _flat_dir_to(target) if target else facing()
	else:
		# Aimed: exactly where the player aims (no snapping onto a target).
		direction.y = 0.0
		direction = direction.normalized()
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


## Short tapered aim line that fades out, with an arrowhead (the arrow flies farther). Local player only.
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


func _aim_quad(mesh: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3, d: Vector3, near: Color, far: Color) -> void:
	for vertex in [[a, near], [b, near], [c, far], [a, near], [c, far], [d, far]]:
		mesh.surface_set_color(vertex[1])
		mesh.surface_add_vertex(vertex[0])


## How far the melee weapon reaches from the hero's center (the aim wedge and the hit wedge).
func melee_reach() -> float:
	return float(WEAPONS.get(_melee_weapon(), WEAPONS.sword).reach)


func _roll_melee_damage() -> Array:
	var crit := randf() < crit_chance
	var base := spear_damage if current_weapon() == "spear" else melee_damage
	return [base * (crit_multiplier if crit else 1.0), crit]


## Melee hits the aim wedge itself (a prism, so big colliders like camp houses count by their surface,
## not their center), starting a little behind the hero so point-blank targets are never missed.
func _melee_query(direction: Vector3) -> PhysicsShapeQueryParameters3D:
	if _melee_wedge == null or _melee_wedge_weapon != _melee_weapon():
		_melee_wedge_weapon = _melee_weapon()
		var points := PackedVector3Array()
		var half := deg_to_rad(melee_arc() * 0.5)
		for y in [0.05, GameConfig.HIT_HEIGHT + 0.3]:
			points.append(Vector3(0.0, y, -0.3))
			for i in 9:
				var a := -half + 2.0 * half * i / 8.0
				points.append(Vector3(sin(a) * melee_reach(), y, cos(a) * melee_reach()))
		_melee_wedge = ConvexPolygonShape3D.new()
		_melee_wedge.points = points
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _melee_wedge
	query.transform = Transform3D(Basis(Vector3.UP, atan2(direction.x, direction.z)), global_position)
	query.collision_mask = melee_mask
	query.exclude = [get_rid()]
	return query


## Short orange wedge in front of the hero while aiming the melee weapon.
func _build_melee_indicator() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.62, 0.2, 0.45)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var reach := melee_reach()
	var wedge := ImmediateMesh.new()
	wedge.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	var steps := 8
	var half := deg_to_rad(melee_arc() * 0.5)
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
		Pickup.Kind.HEALTH:
			return health < max_health
		Pickup.Kind.COIN:
			return true
	return false


func collect(kind: Pickup.Kind, amount: int) -> bool:
	if not can_collect(kind):
		return false
	match kind:
		Pickup.Kind.HEALTH:
			heal(amount)
		Pickup.Kind.COIN:
			coins += amount
			MatchStats.add(peer_id, &"coins", amount)
	return true


# --- Army ---------------------------------------------------------------------

## This player's soldiers currently in the world.
## Soldiers following this player (not the ones still waiting in a barracks pen).
func followers() -> Array[Node]:
	return get_tree().get_nodes_in_group(&"allies").filter(
			func(ally: Node) -> bool: return ally.get("owner_peer") == peer_id and not ally.get("is_dead") \
					and not ally.get("penned"))


## Trained soldiers waiting in a barracks pen for this player.
func penned_soldiers() -> Array[Node]:
	return get_tree().get_nodes_in_group(&"penned").filter(
			func(ally: Node) -> bool: return ally.get("owner_peer") == peer_id and not ally.get("is_dead"))


## Everything that counts toward follower_cap: following + waiting in the pen + in training.
func army_size() -> int:
	return followers().size() + penned_soldiers().size() + soldiers_training


## Seconds until the next soldier in training is ready (0 = none training).
func next_soldier_in() -> float:
	return _training_left[0] if not _training_left.is_empty() else 0.0


# --- Barracks (server) ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	super(delta)
	# A queue: the next soldier starts training when the one before it is ready.
	if not _training_left.is_empty():
		_training_left[0] = maxf(_training_left[0] - delta, 0.0)
	if multiplayer.is_server() and not _training_left.is_empty() and _training_left[0] <= 0.0:
		_finish_training()
	if multiplayer.is_server() and army_order == Order.KILL:
		_update_kill_order()


## The oldest soldier in training is ready: it appears in the pen of the barracks it was bought at.
func _finish_training() -> void:
	var stall: ShopStation = _training_stalls.pop_front() if not _training_stalls.is_empty() else null
	soldiers_training -= 1
	if not is_instance_valid(stall):
		return
	NetSpawn.unit(&"ally", stall.pen_spot(), {"team": team_id, "owner": peer_id, "color": unit_color,
			"pen": stall.get_path(), "weapon": class_def.ally_weapon})
	_net_soldier_ready.rpc()


@rpc("authority", "call_local", "reliable")
func _net_soldier_ready() -> void:
	soldier_ready.emit()


## Server: every soldier waiting in a pen joins this player (they must stand at a barracks: its front
## or its pen gate).
func collect_soldiers() -> int:
	if is_dead or is_downed:
		return 0
	var reach := ShopStation.INTERACT_RANGE + ShopStation.SERVER_SLACK
	if ShopStation.nearest(self, reach, ShopStation.BARRACKS) == null and ShopStation.nearest_gate(self, reach) == null:
		return 0
	var soldiers := penned_soldiers()
	# They file out one after another, closest to the gate first, spread over three lanes.
	soldiers.sort_custom(func(a: Ally, b: Ally) -> bool:
		return a.global_position.distance_to(a.pen.gate_inside()) < b.global_position.distance_to(b.pen.gate_inside()) \
				if is_instance_valid(a.pen) and is_instance_valid(b.pen) else false)
	for i in soldiers.size():
		(soldiers[i] as Ally).release(i * EXIT_INTERVAL, [0.0, -0.7, 0.7][i % 3])
	return soldiers.size()


## Takes the soldiers waiting in the pen (server; clients ask it).
func request_collect_soldiers() -> void:
	if multiplayer.is_server():
		collect_soldiers()
	else:
		net_collect_soldiers.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func net_collect_soldiers() -> void:
	if _from_owner():
		collect_soldiers()


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
		&"recruit":
			return army_size() < follower_cap
		&"blade":
			return weapons.has("sword")
		&"archery":
			return weapons.has("bow") or weapons.has("spear")
	return true


## Only at a trading post stall that sells `def` (checked on the server too).
func can_buy(def: UpgradeDef) -> bool:
	return not is_dead and not is_downed and not is_upgrade_maxed(def) and is_upgrade_useful(def) \
			and coins >= upgrade_cost(def) and ShopStation.can_buy_here(self, def)


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
		&"drill":
			ally_power += def.amount
			for ally in followers():
				(ally as Ally).refresh_army_bonus()
		&"command":
			follower_cap += int(def.amount)
		&"recruit":
			for i in int(def.amount):
				_training_stalls.append(ShopStation.nearest(self, ShopStation.INTERACT_RANGE + ShopStation.SERVER_SLACK,
						ShopStation.BARRACKS))
				soldiers_training += 1
		&"potion":
			heal(def.amount)
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
	army_target = null
	army_target_path = NodePath()
	order_serial += 1
	add_to_group(&"player_units")
	super(at)


func take_damage(amount: float, attacker: Node3D = null, is_melee: bool = true, crit: bool = false) -> void:
	if is_downed:
		# Orcs leave downed players alone; an enemy player (their soldiers or arrows) finishes them.
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
		set_meta(&"marker_icon", preload("res://assets/ui/icons/game/medical_kit.svg"))
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
## HOLD: guard `point`. KILL: hunt the enemy at `point` (none there → CHARGE `point`).
## Every order is obeyed at once: soldiers drop their fight and go (see Ally._obey).
func command_army(order: int, point: Vector3) -> void:
	if is_dead:
		return
	order = clampi(order, Order.FOLLOW, Order.KILL)
	var offset := point - global_position
	offset.y = 0.0
	army_point = GameConfig.clamp_to_world(global_position + offset.limit_length(MAX_ORDER_DISTANCE))
	army_target = null
	if order == Order.KILL:
		army_target = kill_target_near(point)
		if army_target:
			army_point = army_target.global_position
		else:
			order = Order.CHARGE  # missed: charge there
	army_target_path = army_target.get_path() if army_target else NodePath()
	army_order = order
	order_serial += 1


## The hostile unit / camp closest to `point` (within `radius`), for a kill order.
func kill_target_near(point: Vector3, radius: float = KILL_PICK_RADIUS) -> Node3D:
	var best: Node3D = null
	var best_dist := radius
	for group in KILL_GROUPS:
		for node in get_tree().get_nodes_in_group(group):
			var candidate := node as Node3D
			if candidate == null or GameConfig.is_gone(candidate) or not GameConfig.is_hostile(self, candidate) \
					or candidate.is_in_group(&"penned"):
				continue
			var reach: float = Unit.target_radius(candidate) if candidate is Camp else 0.0
			var d := Vector2(candidate.global_position.x - point.x, candidate.global_position.z - point.z).length() - reach
			if d < best_dist:
				best_dist = d
				best = candidate
	return best


## Server: while hunting, keep the point on the target; once it's dead, charge where it fell.
func _update_kill_order() -> void:
	if not GameConfig.is_gone(army_target):
		if army_target.global_position.distance_to(army_point) > 1.5:
			army_point = army_target.global_position  # quantized: only when it moved a bit
		return
	army_target = null
	army_target_path = NodePath()
	army_order = Order.CHARGE


@rpc("any_peer", "call_remote", "reliable")
func net_command(order: int, point: Vector3) -> void:
	if _from_owner():
		command_army(order, point)
