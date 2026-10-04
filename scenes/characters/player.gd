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
## Special ability (ClassDef.ability, X / R3): enemies drop XP orbs (Enemy.xp_drop); with ClassDef.ability_xp
## collected, `use_ability()` spends it. Swordsman: Whirlwind (`_whirlwind_*`); Spearman: Bull Rush
## (`_bull_rush_*`). Bowman: Bow Rain (`_bow_rain_*`).

signal coins_changed(count: int)
signal upgrades_changed
## Server: this player just went down / was revived (`helpers` = the players who revived them).
signal went_down(player: Player)
signal revived(player: Player, helpers: Array)
## Every peer: the downed state changed (visuals, HUD).
signal downed_changed(downed: bool)
signal army_order_changed(order: int)
## Every peer: a recruited soldier finished training and joined you (it appears right behind you).
signal soldier_ready
## Every peer: the weapon in hand changed (id from WEAPONS).
signal weapon_changed(weapon: String)
## Every peer: the shield went up / down, took a hit, or broke (`shield_health` 0).
signal shield_changed
## Every peer: XP changed, or the special ability started / ended.
signal ability_changed

## KILL: every soldier hunts `army_target` down (then they charge where it fell).
enum Order { FOLLOW, CHARGE, HOLD, KILL }

const TARGET_GROUPS: Array[StringName] = [&"active_enemies", &"player_units", &"camps"]
## Height arrows and thrown spears fly at; main.gd reads the mouse aim on this plane, so a shot passes right
## under the cursor (on the ground it would land short by the camera's slant).
const SHOT_HEIGHT: float = 0.65
## Aim offsets longer than this are a point to hit (the mouse); shorter ones (sticks) only a direction.
const AIM_POINT_MIN: float = 1.0
const AIM_LINE_WIDTH: float = 0.34
const AIM_RETICLE_SIZE: float = 0.75
const AIM_LINE_SHADER := preload("res://assets/shaders/aim_line.gdshader")
const AIM_RETICLE_SHADER := preload("res://assets/shaders/aim_reticle.gdshader")
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
## Weapon id -> how it works. `melee` weapons swing (sword stick / left mouse) and hit the aim area, out to
## `reach` m, every `cooldown` s: a fan `arc` degrees wide (sword), or a straight `lane` this many m wide with a
## pointed end (spear stab). The others are aimed and fired (bow stick /
## aim): the bow shoots arrows, the javelin throws the spear (slower, harder). No ammo. The class
## (ClassDef.weapons) decides what a player carries; E / Y / the HUD button cycles them. `hand` holds the
## model; `icon` is a Game Icon Pack glyph. New weapon = a row here + its model in `_weapon_items`.
const WEAPONS: Dictionary = {
	"sword": {"melee": true, "hand": ARM_RIGHT, "icon": "sword", "name": "Sword", "arc": 80.0, "reach": 1.55,
			"cooldown": 0.5},
	"spear": {"melee": true, "hand": ARM_RIGHT, "icon": "spear", "name": "Spear", "lane": 0.8, "reach": 2.6,
			"cooldown": 0.65},
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
## Procedural spear stab (`_spear_thrust`), keyed carry → drawn back → full stab → hold → carry. Straight
## forward only: the hero, the arm and the shoulders stay put; the spear tips level, pointing down the middle
## of the hit lane (0 carry grip, upright; 1 level), and slides along its shaft through the fist (m, + =
## toward the tip): back, then out.
const THRUST_LEVEL: Array[float] = [0.0, 1.0, 1.0, 1.0, 0.0]
## Keep some shaft behind the fist. Larger positive values push the spear's butt past the hand and make the
## weapon look detached, even though its axis is still aligned correctly.
const THRUST_PUSH: Array[float] = [0.0, -0.16, 0.1, 0.08, 0.0]
## Point on the spear shaft held in the fist (the model runs from local Y = 0 at the butt to 0.6 at the tip).
const SPEAR_GRIP: Vector3 = Vector3(0.0, 0.2, 0.0)
const SPEAR_MIN_SHAFT_BEHIND_HAND: float = 0.08
## The bow is held upright in the body's frame (limbs up / down, belly toward where the hero faces, string
## toward them), whatever the arm's pose: the fist (`left_hand_offset` + `BOW_FIST` in the arm's space) holds
## it at `BOW_GRIP` (bow space: limbs along +Y, belly +Z, string at z = 0). An arrow sits nocked at
## `NOCK_POSITION` (string drawn back); a shot leaves from exactly there and the next one is nocked after the
## cooldown.
const BOW_FIST: Vector3 = Vector3(0.0, 0.24, 0.0)
const BOW_GRIP: Vector3 = Vector3(-0.04, 0.24, 0.15)
const NOCK_POSITION: Vector3 = Vector3(-0.04, 0.24, 0.08)
const ARROW_MODEL := preload("res://assets/items/forest/arrow.glb")
## Shield (Swordsman, Spearman: ClassDef.shield): held up (right mouse / LT / the touch shield button) it blocks
## every hit from within BLOCK_ARC degrees of where the hero faces, soaking the damage until `shield_health`
## runs out and it breaks (back on respawn; buying a new one comes later). Up, the hero walks at BLOCK_SPEED
## and can't attack. Placed every frame (`_place_shield`, body space, the middle of the shield): carried on the
## left fist, upright, its face turned out to the side (SHIELD_CARRY_FACE); up, square in front of the chest
## (SHIELD_BLOCK_AT). Both ride the torso's bob / sway (SHIELD_SWAY of its turn), and a blocked hit knocks it back
## (SHIELD_RECOIL_*).
const BLOCK_ARC: float = 150.0
const BLOCK_SPEED: float = 0.45
const SHIELD_BLOCK_AT: Vector3 = Vector3(0.06, 0.4, 0.27)
## Bull Rush: the shield stays strapped to the moving forearm, faces forward and leans into the charge.
const SHIELD_RUSH_LIFT: float = 0.08
const SHIELD_RUSH_OUT: float = 0.06
const SHIELD_RUSH_TILT: float = -12.0
const SHIELD_RUSH_SWAY: float = 0.25
## Carried: strapped to the forearm (arm space), its middle lifted a bit, face out to the side and a little ahead.
const SHIELD_CARRY: Vector3 = Vector3(0.18, 0.0, 0.0)
const SHIELD_CARRY_LIFT: float = 0.08
const SHIELD_CARRY_FACE: Vector3 = Vector3(0.85, 0.0, 0.5)
const SHIELD_CARRY_OUT: float = 0.05
## Seconds to swing the shield up in front / back down to the side.
const SHIELD_RAISE_TIME: float = 0.14
const SHIELD_SWAY: float = 0.6
const SHIELD_RECOIL_BACK: float = 0.09
const SHIELD_RECOIL_TILT: float = 18.0
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
## Whirlwind (Swordsman ability): spins for ClassDef.ability_duration with the sword held out. Every target
## within WHIRLWIND_RADIUS is hit once per complete rotation for WHIRLWIND_DAMAGE × sword damage. Moves at
## WHIRLWIND_SPEED × running speed; no attacks or blocking meanwhile.
const WHIRLWIND_RADIUS: float = 1.9
const WHIRLWIND_DAMAGE: float = 0.5
const WHIRLWIND_SPEED: float = 0.8
const WHIRLWIND_ARC_DEGREES: float = 160.0
## Degrees per second the body turns.
const WHIRLWIND_SPIN: float = 900.0
## One damage pulse per 360° rotation. Keep this derived from the visual spin speed.
const WHIRLWIND_TICK: float = 360.0 / WHIRLWIND_SPIN
## Bull Rush (Spearman ability): sprint through enemies, turn slowly toward WASD input and damage each target
## once. Enemy collision exceptions are temporary; world walls and buildings still stop the charge.
const BULL_RUSH_SPEED: float = 2.2
const BULL_RUSH_DAMAGE: float = 4.0
const BULL_RUSH_RADIUS: float = 0.72
## Heavy steering: normal movement turns immediately; Bull Rush can turn only this many degrees per second.
const BULL_RUSH_TURN_SPEED: float = 105.0
## Bow Rain (Bowman ability): X enters placement mode and LMB confirms the ground target. Arrows fall
## across this radius for the ability duration. These values are intentionally centralized for tuning.
const BOW_RAIN_RADIUS: float = 4.05
const BOW_RAIN_RANGE: float = 14.0
const BOW_RAIN_HEIGHT: float = 7.0
const BOW_RAIN_TOTAL_ARROWS: int = 100
const BOW_RAIN_TARGETED_ARROWS: int = 3
const BOW_RAIN_COVERAGE_BLOCK: int = 10
const BOW_RAIN_DAMAGE: float = 1.2
const BOW_RAIN_ARROW_SPEED: float = 16.0
const BOW_RAIN_EDGE_MARGIN: float = 0.25
const BOW_RAIN_SHADER := preload("res://assets/shaders/bow_rain_area.gdshader")
# Class upgrades (UpgradeDef.classes, bought from the upgrades sheet; effects in `_apply_class_upgrades`).
## Unlocks every hero gets for free in the Training Field (all class upgrades cost nothing there).
const TRAINING_UNLOCKS: Array[StringName] = [&"shield", &"spear_throw", &"knife", &"sword_dash"]
## Dash Attack (Swordsman, C): DASH_DISTANCE m in DASH_TIME s through enemies, each one crossed takes
## melee_damage × the upgrade's amount once (in a DASH_RADIUS sweep).
const DASH_TIME: float = 0.22
const DASH_DISTANCE: float = 4.5
const DASH_COOLDOWN: float = 4.0
const DASH_RADIUS: float = 0.7
const DASH_COLOR := Color(0.75, 0.9, 1.0)
## Knife (Bowman, right mouse): a quick stab in a KNIFE_ARC° fan out to KNIFE_REACH m (shorter and narrower than
## the sword's swing). The knife is the dungeon sword scaled down, shown in the right hand only while stabbing.
## No arrows while stabbing (`shoot` waits out KNIFE_COOLDOWN).
const KNIFE_SCENE := preload("res://assets/items/dungeon/sword.glb")
const KNIFE_SCALE: float = 0.55
const KNIFE_REACH: float = 1.0
const KNIFE_ARC: float = 50.0
const KNIFE_COOLDOWN: float = 0.5
const KNIFE_HIT_DELAY: float = 0.12
## Wave (Swordsman): each swing also sends a slash wave forward (`sword_wave` projectile) that goes through enemies.
const WAVE_HEIGHT: float = 0.5
## The wave goes through this many enemies after the first.
const WAVE_PIERCE: int = 3

@export var arrow_damage: float = 22.0
@export var shoot_cooldown: float = 0.4
## Spear: thrusts (melee) and throws (javelin) deal this; throws are slower than arrows.
@export var spear_damage: float = 42.0
@export var spear_cooldown: float = 1.1
@export var aim_range: float = 12.0
## Middle of the sword's handle (model space): the slash turns the blade around it, so it stays in the fist.
@export var sword_grip_point: Vector3 = Vector3(0.0, 0.027, 0.0)
## End of the sword blade in model space. Whirlwind anchors the bright edge of its trail here.
@export var sword_tip_point: Vector3 = Vector3(0.0, -0.4, 0.0)
@export var arrow_scene: PackedScene
## Chance and multiplier for critical hits (every weapon).
@export_range(0.0, 1.0) var crit_chance: float = 0.15
@export var crit_multiplier: float = 1.8

## Network id of the player controlling this hero (set at spawn).
var peer_id: int = 1
var display_name: String = "Player"
## The class (set at spawn on every peer with `set_class()`, before entering the tree).
var class_def: ClassDef
## Local Training Field: special abilities need no XP and XP pickups are ignored.
var training_mode: bool = false
## Movement input (screen axes), set from the HUD / network.
var joystick_vector: Vector2 = Vector2.ZERO
## Soldier damage / health multipliers (the "soldier_damage" / "soldier_health" upgrades). Server only.
var ally_damage: float = 1.0
var ally_health: float = 1.0

# --- Replicated stats (see the Sync node) ---
var coins: int = 0:
	set(value):
		coins = value
		coins_changed.emit(coins)
## Recruited soldiers still training (replicated). They train one after another,
## GameConfig.SOLDIER_TRAIN_TIME seconds each, then appear behind the player and follow (`_finish_training`).
var soldiers_training: int = 0:
	set(value):
		value = maxi(value, 0)
		# Every peer keeps a copy of the countdowns for the upgrades sheet (server: the real ones).
		while _training_left.size() < value:
			_training_left.append(GameConfig.SOLDIER_TRAIN_TIME)
		while _training_left.size() > value:
			_training_left.remove_at(0)
		soldiers_training = value
## Max army size: following + in training (raised by the "command" upgrade).
var follower_cap: int = GameConfig.BASE_FOLLOWER_CAP
## Upgrade id -> times bought. Always replaced (not mutated) so replication notices changes.
var upgrade_levels: Dictionary = {}:
	set(value):
		upgrade_levels = value
		if is_node_ready():
			_apply_class_upgrades()
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
## Replicated: the shield is held up (blocking).
var shield_up: bool = false:
	set(value):
		if value != shield_up:
			shield_up = value
			if is_node_ready():
				_apply_shield()
## Replicated: damage the shield can still soak (0 = broken / none). Only shows / hides it (a hit must not
## re-blend the arms, that dragged the shield around).
var shield_health: float = 0.0:
	set(value):
		var was_broken := shield_health <= 0.0
		shield_health = value
		if is_node_ready():
			_show_shield()
			if was_broken != (shield_health <= 0.0):
				_update_move_speed()
			shield_changed.emit()
## Replicated: XP toward the special ability (0 .. ClassDef.ability_xp).
var xp: int = 0:
	set(value):
		xp = value
		ability_changed.emit()
## Replicated: XP pickups cannot be attracted or collected during the post-activation lockout.
var ability_xp_locked: bool = false:
	set(value):
		if value != ability_xp_locked:
			ability_xp_locked = value
			ability_changed.emit()
## Replicated: the special ability is running.
var ability_start_yaw: float = 0.0
var ability_elapsed: float = 0.0:
	set(value):
		ability_elapsed = value
		_ability_visual_elapsed = value
var ability_active: bool = false:
	set(value):
		if value != ability_active:
			ability_active = value
			if is_node_ready():
				_apply_ability()
## Replicated center of an active Bow Rain. The server clamps it to BOW_RAIN_RANGE before starting.
var bow_rain_target: Vector3 = Vector3.ZERO:
	set(value):
		bow_rain_target = value
		if is_node_ready():
			_place_bow_rain_area()
var weapon_index: int = 0:
	set(value):
		if value != weapon_index:
			weapon_index = value
			if is_node_ready() and _melee_indicator:
				_apply_weapon()

## Class-upgrade stats, recomputed from `upgrade_levels` on every peer (`_apply_class_upgrades`): extra enemies an
## arrow flies through, the Wave's damage fraction (0 = none), Dash / Knife damage (0 = not owned).
var arrow_pierce: int = 0
var sword_wave: float = 0.0
var dash_damage: float = 0.0
var knife_damage: float = 0.0
## Replicated: a Dash Attack is under way (trail and slash on every peer).
var dash_active: bool = false:
	set(value):
		if value != dash_active:
			dash_active = value
			if is_node_ready():
				_apply_dash()

var _base_melee_damage: float
var _base_arrow_damage: float
var _base_spear_damage: float
var _base_aim_range: float
var _base_shoot_cooldown: float
var _base_spear_cooldown: float
var _dash_left: float = 0.0  # server and the predicting owner: seconds of dash left
var _dash_direction: Vector3 = Vector3.ZERO
var _dash_cooldown: float = 0.0  # server and the owner (HUD): seconds until the next dash
var _dash_last_position: Vector3 = Vector3.ZERO
var _dash_hit_ids: Dictionary = {}
var _dash_saved_mask: int = -1
var _knife_timer: float = 0.0  # server: seconds until the next knife stab
var _knife_item: Node3D
var _shoot_timer: float = 0.0
var _pending_shot: Vector3 = Vector3.ZERO  # aimed shot released during cooldown
var _aim_indicator: Node3D
var _aim_line: MeshInstance3D
var _aim_reticle: MeshInstance3D
var _melee_aim: Vector3 = Vector3.ZERO
var _melee_indicator: Node3D
var _knife_indicator: Node3D  # the knife's fan, under the Bowman while the knife is held (`set_knife_aim`)
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
var _thrust_phase: float = -1.0  # stab phase (see `_thrust_pose`); < 0 = not stabbing
var _thrust_dir: Vector3 = Vector3.ZERO  # the stab's lane, fixed when it starts (see `_spear_thrust`)
var _thrust_until: int = 0  # ticks (ms) when the current stab ends
var _nocked_arrow: Node3D  # the arrow on the string (bow only)
var _nock_body: Vector3 = Vector3.INF  # where it sits in the model's space (last drawn frame)
var _shield_recoil: float = 0.0  # 1 right after a blocked hit, back to 0 (see `_place_shield`)
var _shield_recoil_tween: Tween
var _shield_raise: float = 0.0  # 0 carried .. 1 up in front (blends while it goes up / down)
var _shield_raise_tween: Tween
var _ability_left: float = 0.0  # server: seconds of the ability left
var _ability_visual_elapsed: float = 0.0  # clients extrapolate the server's replicated ability clock
var _ability_xp_lockout_left: float = 0.0  # server: seconds until XP collection is enabled again
var _ability_tick: float = 0.0  # server: next Whirlwind hit / Bow Rain arrow
var _spin_angle: float = 0.0  # every peer: total Whirlwind turn, independent of movement facing
var _spin_world_yaw: float = 0.0  # visible body yaw; movement may still turn the model underneath it
var _whirlwind_arc: MeshInstance3D  # one reusable effect; moved instead of spawned every frame
var _rush_wind: Node3D
var _bull_rush_direction: Vector3 = Vector3.ZERO
var _bull_rush_last_position: Vector3 = Vector3.ZERO
var _bull_rush_hit_ids: Dictionary = {}
var _bull_rush_exceptions: Array[PhysicsBody3D] = []
var _bull_rush_saved_mask: int = -1
var _bow_rain_area: MeshInstance3D
var _bow_rain_previewing: bool = false
var _bow_rain_fired: int = 0
var _bow_rain_targeted_fired: int = 0
var _bow_rain_offsets: Array[Vector2] = []


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
	weapons = _class_weapons()
	weapon_index = 0
	if not weapons.has("sword"):
		right_hand_item = null
	if not weapons.has("bow"):
		left_hand_item = class_def.shield
		left_hand_offset = SHIELD_CARRY
		hold_left_arm = class_def.shield != null  # raised while blocking
	shield_health = class_def.shield_health if owns_shield() else 0.0
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
	_base_aim_range = aim_range
	_base_shoot_cooldown = shoot_cooldown
	_base_spear_cooldown = spear_cooldown
	if class_def.move_speed > 0.0:
		move_speed = class_def.move_speed
	_base_move_speed = move_speed
	for looping in ["holding-left", "sit", "crouch"]:
		if anim.has_animation(looping):
			anim.get_animation(looping).loop_mode = Animation.LOOP_LINEAR
	_add_downed_anims()
	_build_aim_indicator()
	_build_melee_indicator()
	_build_name_label()
	_build_downed_visuals()
	_build_bow_rain_area()
	var spear := _attach_spear() if weapons.has("spear") or weapons.has("javelin") else null
	# Hand items that are weapons (the left one can be a shield instead of the bow).
	_weapon_items = {"sword": _right_item if weapons.has("sword") else null, "bow": _left_item if weapons.has("bow") else null,
			"spear": spear, "javelin": spear}
	_setup_bow()
	_setup_shield()
	if training_mode and multiplayer.is_server():
		_grant_training_unlocks()
	_apply_class_upgrades()
	_apply_weapon()
	if is_downed:
		_apply_downed()
	if ability_active:
		_apply_ability()  # spawn replication can set the ability before its weapons and effects exist


## True on the device whose player this is.
func is_local() -> bool:
	return peer_id == multiplayer.get_unique_id()


func _get_move_input(delta: float) -> Vector3:
	if is_downed:
		_update_downed(delta)
		return Vector3(joystick_vector.x, 0.0, joystick_vector.y)
	if _is_bull_rushing():
		_steer_bull_rush(Vector3(joystick_vector.x, 0.0, joystick_vector.y), delta)
		return _bull_rush_direction
	if _dash_left > 0.0:
		return _dash_step(delta)
	_shoot_timer = maxf(_shoot_timer - delta, 0.0)
	if _pending_shot != Vector3.ZERO and _shoot_timer <= 0.0:
		var direction := _pending_shot
		_pending_shot = Vector3.ZERO
		shoot(direction)
	if _melee_aim != Vector3.ZERO:
		attack_melee_toward(_melee_aim)
	# Camera looks toward -Z, so screen-up is -Z.
	return Vector3(joystick_vector.x, 0.0, joystick_vector.y)


func _prediction_move_input(delta: float) -> Vector3:
	if _is_bull_rushing():
		_steer_bull_rush(Vector3(predict_input.x, 0.0, predict_input.y), delta)
		return _bull_rush_direction
	if _dash_left > 0.0:
		return _dash_step(delta)
	return super(delta)


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
	# A delayed replicated normal attack must not replace the special ability's weapon pose.
	if ability_active and class_def.ability != &"bow_rain":
		return
	if anim_name == "knife-stab":
		_knife_stab_visual(duration)
		return
	var melee := anim_name.begins_with("attack-melee") and holds_melee()
	if melee and current_weapon() == "sword" and _right_hold and _right_item and not is_downed:
		_sword_slash(duration)
	elif melee and current_weapon() == "spear" and _right_hold and _weapon_items.get("spear") and not is_downed:
		_spear_thrust(duration)
	else:
		super(anim_name, duration, release_arms)
	if anim_name == "holding-left-shoot" and _nocked_arrow:
		# The nocked arrow is the one that flies; the next one is on the string when the bow is ready again.
		_nocked_arrow.visible = false
		get_tree().create_timer(shoot_cooldown * 0.8).timeout.connect(_nock_arrow)
	if not anim_name.begins_with("attack-melee"):
		return
	if melee:
		get_tree().create_timer(attack_hit_delay / anim_speed * 0.55).timeout.connect(_slash_fx)
	elif current_weapon() == "javelin":
		# The spear in hand leaves with the throw and a new one is drawn a moment later.
		get_tree().create_timer(0.15).timeout.connect(_show_spear.bind(false))
		get_tree().create_timer(0.75).timeout.connect(_show_spear.bind(true))


## Bowman: an arrow on the string, and the bow placed upright in the body's frame after every skeleton update
## (after the BoneAttachment3D, which was connected first, so its arm frame is this frame's final pose).
func _setup_bow() -> void:
	var bow := _weapon_items.get("bow") as Node3D
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if bow == null or skeleton == null:
		return
	_nocked_arrow = ARROW_MODEL.instantiate() as Node3D
	_nocked_arrow.position = NOCK_POSITION
	bow.add_child(_nocked_arrow)
	skeleton.skeleton_updated.connect(_place_bow.bind(skeleton))
	_place_bow(skeleton)


func _nock_arrow() -> void:
	if _nocked_arrow:
		_nocked_arrow.visible = true


func _place_bow(skeleton: Skeleton3D) -> void:
	var bow := _weapon_items.get("bow") as Node3D
	if bow == null or not bow.is_inside_tree():
		return
	var to_skeleton := skeleton.global_transform.affine_inverse()
	var arm := (to_skeleton * (bow.get_parent() as Node3D).global_transform).orthonormalized()
	var body := (to_skeleton * model.global_transform * _spin_transform()).orthonormalized()
	bow.basis = arm.basis.inverse() * body.basis
	bow.position = left_hand_offset + BOW_FIST - bow.basis * BOW_GRIP
	_nock_body = model.global_transform.affine_inverse() * bow.global_transform * NOCK_POSITION


# --- Shield -------------------------------------------------------------------

func has_shield() -> bool:
	return class_def != null and class_def.shield != null and shield_health > 0.0


## The shield can go up now: carried, not broken, a melee weapon in hand (thrown spears / the bow aim with
## the same button), standing.
func can_block() -> bool:
	return has_shield() and holds_melee() and not is_dead and not is_downed and not ability_active


## A Bull Rush automatically guards with an intact shield; it does not need the block button held.
func _shield_is_guarding() -> bool:
	return shield_up or (_is_bull_rushing() and has_shield())


## Server: raise / lower the shield.
func set_block(up: bool) -> void:
	shield_up = up and can_block()


## Like the bow: placed in the body's frame after every skeleton update.
func _setup_shield() -> void:
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if class_def.shield == null or _left_item == null or skeleton == null:
		return
	skeleton.skeleton_updated.connect(_place_shield.bind(skeleton))
	_apply_shield()


## Down: upright on the left fist (follows the arm's swing), face turned out to the side. Up: square in front
## of the chest, facing where the hero faces. Both ride the torso (walk bob, sway) and the hit recoil.
func _place_shield(skeleton: Skeleton3D) -> void:
	if _left_item == null or not _left_item.visible or not _left_item.is_inside_tree():
		return
	var to_skeleton := skeleton.global_transform.affine_inverse()
	var arm := (to_skeleton * (_left_item.get_parent() as Node3D).global_transform).orthonormalized()
	var body := (to_skeleton * model.global_transform).orthonormalized()
	# How the torso moves this frame (the walk's bounce and twist) relative to its rest, in skeleton space.
	var torso := skeleton.find_bone("torso")
	var sway := Transform3D.IDENTITY
	if torso >= 0:
		sway = skeleton.get_bone_global_pose(torso) * skeleton.get_bone_global_rest(torso).affine_inverse()
		var sway_strength := SHIELD_RUSH_SWAY if _is_bull_rushing() else SHIELD_SWAY
		sway.basis = Basis(Quaternion.IDENTITY.slerp(sway.basis.orthonormalized().get_rotation_quaternion(), sway_strength))
	# The shield's middle and facing in skeleton space: carried, up in front, and the blend between them.
	var face := SHIELD_CARRY_FACE.normalized()
	var carry_basis := sway.basis * body.basis * Basis(Vector3.UP.cross(face), Vector3.UP, face)
	var forearm := arm * (SHIELD_CARRY + class_def.hand_offset)
	var size := class_def.shield_scale
	var carried := Transform3D(carry_basis, forearm + carry_basis * Vector3(0.0, SHIELD_CARRY_LIFT * size, SHIELD_CARRY_OUT))
	var charge_guard := _is_bull_rushing() and has_shield()
	var raised: Transform3D
	if charge_guard:
		# Unlike the standing block, a running arm moves a lot. Anchor the charge pose to its real forearm
		# point so the shield can never float away while the sprint animation plays.
		var charge_basis := sway.basis * body.basis * Basis(Vector3.RIGHT,
				deg_to_rad(SHIELD_RUSH_TILT) - deg_to_rad(SHIELD_RECOIL_TILT) * _shield_recoil)
		raised = Transform3D(charge_basis, forearm + charge_basis * Vector3(0.0,
				SHIELD_RUSH_LIFT * size, SHIELD_RUSH_OUT - SHIELD_RECOIL_BACK * _shield_recoil))
	else:
		var recoil := Transform3D(Basis(Vector3.RIGHT, -deg_to_rad(SHIELD_RECOIL_TILT) * _shield_recoil),
				SHIELD_BLOCK_AT - Vector3(0.0, 0.0, SHIELD_RECOIL_BACK) * _shield_recoil)
		raised = sway * body * recoil
	var middle := carried.interpolate_with(raised, _shield_raise) if _shield_raise < 1.0 else raised
	_left_item.transform = arm.affine_inverse() * middle * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size),
			-class_def.shield_center * size)


func _show_shield() -> void:
	if _left_item and class_def and class_def.shield:
		_left_item.visible = shield_health > 0.0 and not is_downed


## Every peer: slower while blocking, the left arm up or down, the shield hidden once broken.
func _apply_shield() -> void:
	_update_move_speed()
	_show_shield()
	var guarding := _shield_is_guarding()
	if guarding:
		set_melee_aim(Vector3.ZERO)
	var raise_to := 1.0 if guarding else 0.0
	if not is_equal_approx(_shield_raise, raise_to):
		if _shield_raise_tween:
			_shield_raise_tween.kill()
		_shield_raise_tween = create_tween()
		_shield_raise_tween.tween_property(self, "_shield_raise", raise_to, SHIELD_RAISE_TIME) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if (_left_hold or _right_hold) and _action_time <= 0.0:
		_hold_arms()
	shield_changed.emit()


## Server: a hit from in front landed on the raised shield: it soaks the damage (and maybe breaks).
func _shield_blocks(attacker: Node3D) -> bool:
	if not _shield_is_guarding() or not has_shield():
		return false
	if not is_instance_valid(attacker):
		return true
	var to := attacker.global_position - global_position
	to.y = 0.0
	# The body turns smoothly while steering, but the Bull Rush shield guards the
	# direction of travel immediately. Keep the normal shield arc and durability.
	var guard_direction := _bull_rush_direction if _is_bull_rushing() \
			and _bull_rush_direction.length_squared() > 0.0001 else facing()
	return to.length() < 0.05 or rad_to_deg(guard_direction.angle_to(to)) <= BLOCK_ARC * 0.5


func _block(amount: float) -> void:
	shield_health = maxf(shield_health - amount, 0.0)
	_since_hit = 0.0
	if shield_health <= 0.0:
		shield_up = false
	_net_blocked.rpc(shield_health <= 0.0)


@rpc("authority", "call_local", "reliable")
func _net_blocked(broken: bool) -> void:
	var at := global_position + facing() * 0.45 + Vector3(0, 0.55, 0)
	if _left_item and _left_item.is_inside_tree():
		at = _left_item.global_transform * class_def.shield_center + facing() * 0.08
	HitFx.block_impact(at, facing(), broken)
	# Knocked back toward the body, top tipping back, then it springs into place (`_place_shield`).
	if _shield_recoil_tween:
		_shield_recoil_tween.kill()
	_shield_recoil = 1.0
	_shield_recoil_tween = create_tween()
	_shield_recoil_tween.tween_property(self, "_shield_recoil", 0.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _show_spear(shown: bool) -> void:
	var spear := _weapon_items.get("spear") as Node3D
	if spear:
		spear.visible = shown and _weapon_items.get(current_weapon()) == spear and not is_downed


func _slash_fx() -> void:
	if is_dead or not is_inside_tree():
		return
	# The trail covers the hit area (the server knows where the swing started; other peers use the facing):
	# a sweep for the sword, a straight stab for the spear.
	var forward := _melee_dir if multiplayer.is_server() and _melee_dir != Vector3.ZERO else facing()
	var yaw := atan2(forward.x, forward.z)
	if melee_lane() > 0.0:
		forward = _melee_hit_direction()
		HitFx.stab(self, 0.6, atan2(forward.x, forward.z), melee_reach(), melee_lane() * 0.5,
				Color(1.0, 0.96, 0.85), 0.22, _melee_hit_direction)
	else:
		HitFx.swing_arc(self, 0.5, yaw, melee_reach(), Color(1.0, 0.96, 0.85), melee_arc())


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


## Spear attack, standing or running: no clip (Kenney's melee clip swings the spear at the ground). The spear
## tips level, draws back through the fist, shoots straight out along the hit lane, holds a moment and returns
## (`THRUST_*` keys). Nothing moves sideways and the hero never steps forward. Damage lands in the fast part
## (`attack_hit_delay`).
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
	_slash_skeleton.transform = _slash_skeleton_rest
	# The lane is fixed where the stab starts: turning or re-aiming during it doesn't drag the spear, its
	# streak or the hit sideways (`_melee_hit_direction`, `_facing_locked`).
	_thrust_until = 0
	_thrust_dir = _melee_hit_direction()
	_thrust_until = Time.get_ticks_msec() + int(duration * 1000.0)
	face_now(_thrust_dir)
	# The spear is placed from the arm's real (final) pose each frame, so it points straight ahead whatever
	# the holding pose / walk cycle does to the arm.
	if not _slash_skeleton.skeleton_updated.is_connected(_place_stab_spear):
		_slash_skeleton.skeleton_updated.connect(_place_stab_spear)
	var hit := attack_hit_delay / anim_speed
	var draw := hit * 0.7
	var strike := hit * 0.3 + 0.04
	var rest := maxf(duration * 0.95 - draw - strike, 0.1)
	_thrust_pose(0.0)
	_slash_tween = create_tween()
	_slash_tween.tween_method(_thrust_pose, 0.0, 1.0, draw).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_slash_tween.tween_method(_thrust_pose, 1.0, 2.0, strike).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_slash_tween.tween_method(_thrust_pose, 2.0, 3.0, rest * 0.35)
	_slash_tween.tween_method(_thrust_pose, 3.0, 4.0, rest * 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Stab pose at `phase` (0 carry, 1 drawn back, 2 full stab, 3 held, 4 carry). The spear itself is placed in
## `_place_stab_spear` once the skeleton's pose is final; outside a stab it is back in its carry grip.
func _thrust_pose(phase: float) -> void:
	var spear := _weapon_items.get("spear") as Node3D
	if spear == null:
		return
	_thrust_phase = phase if phase > 0.0 and phase < float(THRUST_PUSH.size() - 1) else -1.0
	if _thrust_phase < 0.0:
		spear.basis = Basis.IDENTITY
		spear.position = _right_fist_position() - SPEAR_GRIP
	else:
		_place_stab_spear()


## Every skeleton update while stabbing: the spear level and pointing from the fist to the middle of the hit
## lane's far end (in the body's frame, so straight ahead from the top-down camera), slid along its shaft.
func _place_stab_spear() -> void:
	var spear := _weapon_items.get("spear") as Node3D
	if _thrust_phase < 0.0 or spear == null or _slash_skeleton == null:
		return
	var i := clampi(int(_thrust_phase), 0, THRUST_PUSH.size() - 2)
	var t := clampf(_thrust_phase - i, 0.0, 1.0)
	# The arm as last drawn (its BoneAttachment3D carries the pose after the holding-pose modifier;
	# get_bone_global_pose() outside the skeleton update would miss it), in skeleton space.
	var arm := _slash_skeleton.global_transform.affine_inverse() * (spear.get_parent() as Node3D).global_transform
	arm.basis = arm.basis.orthonormalized()
	# Body (model) space -> skeleton space.
	var body_to_skeleton := (_slash_skeleton.global_transform.affine_inverse() * model.global_transform).orthonormalized()
	var fist := _right_fist_position()
	var fist_body := body_to_skeleton.affine_inverse() * (arm * fist)
	var lane_forward := Vector3(0.0, 0.0, 1.0)
	if not _is_bull_rushing():
		lane_forward = model.global_basis.inverse() * _melee_hit_direction()
		lane_forward.y = 0.0
		lane_forward = lane_forward.normalized()
	var far := lane_forward * (melee_reach() / maxf(model.scale.z, 0.01))
	far.y = fist_body.y
	var ahead := (far - fist_body).normalized()
	var down := (Vector3.DOWN - ahead * ahead.dot(Vector3.DOWN)).normalized()
	var level_body := Basis(ahead.cross(down), ahead, down)  # spear +Y (shaft) ahead, flat side up
	var level := arm.basis.inverse() * body_to_skeleton.basis * level_body
	var grip := Basis(Quaternion.IDENTITY.slerp(Quaternion(level.orthonormalized()),
			lerpf(THRUST_LEVEL[i], THRUST_LEVEL[i + 1], t)))
	var push := minf(lerpf(THRUST_PUSH[i], THRUST_PUSH[i + 1], t),
			SPEAR_GRIP.y - SPEAR_MIN_SHAFT_BEHIND_HAND)
	spear.basis = grip
	spear.position = fist - grip * SPEAR_GRIP + grip * Vector3(0.0, push, 0.0)


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
		var fist := _right_fist_position()
		_right_item.basis = grip
		_right_item.position = fist - grip * sword_grip_point
	if _slash_skeleton:
		_slash_skeleton.transform = _slash_skeleton_rest * Transform3D(
				Basis(Vector3.UP, deg_to_rad(key.call(SLASH_TWIST))), Vector3(0.0, 0.0, key.call(SLASH_LUNGE)))


## The actual fist point in the arm attachment's space. Every right-hand weapon keeps its own grip point here.
func _right_fist_position() -> Vector3:
	return right_hand_offset + Basis.from_euler(right_hand_rotation * (PI / 180.0)) * sword_grip_point


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


## Procedural slash / stab poses back to carry, then the arms (see `_held_arms`).
func _hold_arms(instant: bool = false) -> void:
	if ability_active and class_def.ability == &"whirlwind":
		_whirlwind_pose()
		return
	if _is_bull_rushing():
		_bull_rush_pose()
		return
	if _slash_tween:
		_slash_tween.kill()
		_slash_tween = null
	if _slash_skeleton:
		_slash_pose(0.0)
		_thrust_pose(0.0)
	super(instant)


## The bow and the shield are placed every frame (`_place_bow`, `_place_shield`), not by the arm blends.
func _places_item(item: Node3D) -> bool:
	return item != null and item == _left_item and (weapons.has("bow") or (class_def != null and class_def.shield != null))


## Only the arm with the weapon in hand holds it (and the left one while the shield is up); downed players
## crawl with both arms free. (Leaving the free arm to Unit._hold_arms keeps the tween that brings the weapon
## arm back, e.g. after a bow shot.)
func _held_arms() -> int:
	if is_downed:
		return 0
	return _weapon_hand() | (ARM_LEFT if _shield_is_guarding() else 0)


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


## Width in degrees of the melee hit fan (0 for a lane weapon).
func melee_arc() -> float:
	return float(WEAPONS.get(_melee_weapon(), WEAPONS.sword).get("arc", 0.0))


## Width in m of the melee hit lane (the spear; 0 for a fan weapon).
func melee_lane() -> float:
	return float(WEAPONS.get(_melee_weapon(), WEAPONS.sword).get("lane", 0.0))


## The melee hit area seen from above (x, z in the hero's space, +Z forward), starting at `back`: a fan to
## `melee_reach()` (sword) or a lane with a pointed end (spear). Convex: the hit prism and the aim marker.
func melee_outline(back: float) -> PackedVector2Array:
	var reach := melee_reach()
	var points := PackedVector2Array()
	if melee_lane() > 0.0:
		var half := melee_lane() * 0.5
		var shoulder := reach - half * 1.1
		points.append_array([Vector2(-half, back), Vector2(half, back), Vector2(half, shoulder), Vector2(0.0, reach),
				Vector2(-half, shoulder)])
		return points
	var half_arc := deg_to_rad(melee_arc() * 0.5)
	points.append(Vector2(0.0, back))
	for i in 9:
		var a := -half_arc + 2.0 * half_arc * i / 8.0
		points.append(Vector2(sin(a), cos(a)) * reach)
	return points


## The spear model in the right hand (carried like the orc spearmen), hidden unless the spear is in hand.
func _attach_spear() -> Node3D:
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return null
	var spear := _attach_item(skeleton, SPEAR_SCENE, "arm-right")
	if spear:
		spear.position = _right_fist_position() - SPEAR_GRIP
		spear.visible = false
	return spear


## The carried weapon that isn't in hand ("" with a single weapon).
func other_weapon() -> String:
	return weapons[(weapon_index + 1) % weapons.size()] if weapons.size() > 1 else ""


## Server: next carried weapon in hand (the Spearman: thrust <-> throw). Cancels aiming / swinging with the old one.
func switch_weapon() -> void:
	if is_dead or is_downed or weapons.size() < 2 or ability_active:
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


## Crawling while downed; walking (never sprinting) behind a raised shield, whatever the stick says.
func _move_anim(strength: float) -> String:
	if is_downed:
		return "crawl"
	if _is_bull_rushing():
		return "sprint"
	return "walk" if shield_up else super(strength)


func _can_hit(target: Object) -> bool:
	var node := target as Node
	return node != null and (GameConfig.is_hostile(self, node) or node.is_in_group(&"choppable") or node.is_in_group(&"breakable"))


# --- Input (called on the server) ---------------------------------------------

## Continuous input for this frame: movement, bow aim and sword aim (Vector3.ZERO = not aiming), shield up.
## With the shield up, `aim` (the cursor / right stick) is where the hero turns to block.
func set_input(move: Vector2, aim: Vector3, melee_aim: Vector3 = Vector3.ZERO, block: bool = false) -> void:
	joystick_vector = move.limit_length(1.0)
	set_block(block)
	if shield_up:
		aim.y = 0.0
		look_override = aim.normalized() if aim.length_squared() > 0.0001 else Vector3.ZERO
		return
	set_melee_aim(melee_aim)
	if melee_aim != Vector3.ZERO:
		return  # the sword stick decides where we face
	if aim != Vector3.ZERO:
		set_aim(aim)
	elif is_aiming():
		clear_aim()


@rpc("any_peer", "call_remote", "unreliable_ordered")
func net_input(move: Vector2, aim: Vector3, melee_aim: Vector3, block: bool) -> void:
	if _from_owner():
		set_input(move, aim, melee_aim, block)


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
	if is_dead or is_downed or shield_up or ability_active or _melee_timer > 0.0 or not holds_melee():
		return
	if current_weapon() == "spear":
		melee()
		return
	var target := find_nearest(TARGET_GROUPS, 1.8, global_position, {&"camps": -0.8})
	if target:
		face_now(_flat_dir_to(target))
	melee()


## Attack toward `direction`. Sword swings get aim assist; spear thrusts keep the exact lane direction.
func attack_melee_toward(direction: Vector3) -> void:
	if is_dead or is_downed or shield_up or ability_active or _melee_timer > 0.0 or not holds_melee():
		return
	direction.y = 0.0
	if current_weapon() == "spear":
		face_now(direction)
		melee()
		return
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


## Server: the swing's damage, then (Wave upgrade) a slash wave flies on from the sword along the swing.
func _apply_melee() -> void:
	super()
	if sword_wave <= 0.0 or is_dead or current_weapon() != "sword" or not multiplayer.is_server():
		return
	var direction := _melee_hit_direction()
	direction.y = 0.0
	direction = direction.normalized()
	NetSpawn.projectile(&"sword_wave", global_position + Vector3(0.0, WAVE_HEIGHT, 0.0) + direction * 0.5, direction,
			melee_damage * sword_wave, self, false, false, 0.0, false, {"pierce": WAVE_PIERCE})


## Sword stick aim: face `direction` (shows a short wedge for the local player). ZERO = released.
func set_melee_aim(direction: Vector3) -> void:
	direction.y = 0.0
	if direction.length_squared() < 0.0001 or is_dead or is_downed or shield_up or ability_active or not holds_melee():
		if _melee_aim != Vector3.ZERO:
			_melee_aim = Vector3.ZERO
			_melee_indicator.visible = false
			look_override = Vector3.ZERO  # the bow stick sets it again next frame if aiming
		return
	_melee_aim = direction.normalized()
	look_override = _melee_aim
	# A stab under way keeps its lane: the marker stays on it until the stab ends.
	var shown := _thrust_dir if _thrusting() else _melee_aim
	_melee_indicator.rotation.y = atan2(shown.x, shown.z)
	_melee_indicator.visible = is_local()
	_aim_indicator.visible = false


# --- Special ability ----------------------------------------------------------

func has_ability() -> bool:
	return class_def != null and class_def.ability != &""


## Enough XP and free to use it now.
func ability_ready() -> bool:
	return has_ability() and (training_mode or xp >= class_def.ability_xp) and not ability_active and not is_dead and not is_downed


## Server: spends the XP and starts the class's ability.
func use_ability() -> void:
	if not ability_ready():
		return
	# Bow Rain needs a confirmed ground point; use_bow_rain() starts it instead.
	if class_def.ability == &"bow_rain":
		return
	_begin_ability()


## Server: starts a placed Bow Rain after validating and clamping its target.
func use_bow_rain(point: Vector3) -> void:
	if not ability_ready() or class_def.ability != &"bow_rain" or not point.is_finite():
		return
	bow_rain_target = clamp_bow_rain_point(point)
	_begin_ability()


func _begin_ability() -> void:
	ability_start_yaw = model.rotation.y
	ability_elapsed = 0.0
	if not training_mode:
		xp -= class_def.ability_xp
		_ability_xp_lockout_left = class_def.ability_xp_lockout
		ability_xp_locked = _ability_xp_lockout_left > 0.0
	if class_def.ability == &"bull_rush":
		_bull_rush_direction = facing().normalized()
		var spear_index := weapons.find("spear")
		if spear_index >= 0:
			weapon_index = spear_index
	_ability_left = class_def.ability_duration
	_ability_tick = 0.0 if class_def.ability == &"bow_rain" else WHIRLWIND_TICK
	_bow_rain_fired = 0
	_bow_rain_targeted_fired = 0
	if class_def.ability == &"bow_rain":
		_prepare_bow_rain_offsets()
	shield_up = false
	ability_active = true


## Local input: X / R3 / the touch ability button.
func request_ability() -> void:
	if multiplayer.is_server():
		use_ability()
	else:
		net_ability.rpc_id(1)


## Local input: confirms Bow Rain at a world-space ground point.
func request_bow_rain(point: Vector3) -> void:
	if multiplayer.is_server():
		use_bow_rain(point)
	else:
		net_bow_rain.rpc_id(1, point)


@rpc("any_peer", "call_remote", "reliable")
func net_ability() -> void:
	if _from_owner():
		use_ability()


@rpc("any_peer", "call_remote", "reliable")
func net_bow_rain(point: Vector3) -> void:
	if _from_owner():
		use_bow_rain(point)


## Server, every physics frame while it runs.
func _update_ability(delta: float) -> void:
	ability_elapsed += delta
	_ability_left -= delta
	if class_def.ability == &"whirlwind":
		_ability_tick -= delta
		if _ability_tick <= 0.0:
			_ability_tick += WHIRLWIND_TICK
			_whirlwind_hit()
	elif class_def.ability == &"bull_rush":
		_bull_rush_hit()
	elif class_def.ability == &"bow_rain":
		_ability_tick -= delta
		var arrow_interval := class_def.ability_duration / float(BOW_RAIN_TOTAL_ARROWS)
		while _ability_tick <= 0.0 and _bow_rain_fired < BOW_RAIN_TOTAL_ARROWS:
			_ability_tick += arrow_interval
			_bow_rain_arrow()
			_bow_rain_fired += 1
	if _ability_left <= 0.0:
		ability_active = false


## Server: enable ability XP collection again when the post-activation lockout expires.
func _update_ability_xp_lockout(delta: float) -> void:
	if not ability_xp_locked:
		return
	_ability_xp_lockout_left = maxf(_ability_xp_lockout_left - delta, 0.0)
	if _ability_xp_lockout_left <= 0.0:
		ability_xp_locked = false


## Every peer: start / end the ability's look (and the speed / arms that go with it).
func _apply_ability() -> void:
	_update_move_speed()
	var takes_over_weapon := class_def.ability != &"bow_rain"
	if ability_active and takes_over_weapon:
		# The special pose owns the weapon until it ends. Do not let a normal attack tween keep moving it.
		if _slash_tween:
			_slash_tween.kill()
			_slash_tween = null
		set_melee_aim(Vector3.ZERO)
		clear_aim()
		_spin_angle = wrapf(deg_to_rad(WHIRLWIND_SPIN) * ability_elapsed, 0.0, TAU)
		_spin_world_yaw = wrapf(ability_start_yaw - _spin_angle, -PI, PI)
		_action_time = 0.0
		if class_def.ability == &"bull_rush":
			# Enemy bodies cannot halt the charge. The separate spear sweep still detects and damages them.
			if multiplayer.is_server() and _bull_rush_saved_mask < 0:
				_bull_rush_saved_mask = collision_mask
				collision_mask &= ~GameConfig.LAYER_ENEMIES
			if _bull_rush_direction.length_squared() < 0.0001:
				_bull_rush_direction = facing()
			_bull_rush_direction.y = 0.0
			_bull_rush_direction = _bull_rush_direction.normalized()
			_bull_rush_last_position = global_position
			_bull_rush_hit_ids.clear()
	elif class_def.ability == &"bull_rush":
		if multiplayer.is_server() and _bull_rush_saved_mask >= 0:
			collision_mask = _bull_rush_saved_mask
			_bull_rush_saved_mask = -1
		_clear_bull_rush_exceptions()
		_bull_rush_direction = Vector3.ZERO
	if class_def.ability == &"whirlwind":
		if ability_active:
			_ensure_whirlwind_arc()
		if is_instance_valid(_whirlwind_arc):
			_whirlwind_arc.visible = ability_active and not is_dead
	if class_def.ability == &"bow_rain":
		_refresh_bow_rain_area()
	if _is_bull_rushing() and not is_dead and not is_downed:
		if not is_instance_valid(_rush_wind):
			var spear := _weapon_items.get("spear") as Node3D
			if is_instance_valid(spear):
				_rush_wind = preload("res://scripts/components/rush_wind.gd").new()
				_rush_wind.name = &"RushWind"
				spear.add_child(_rush_wind)
				_rush_wind.position = Vector3(0.0, 0.6, 0.0)
				_rush_wind.rotation.x = -PI * 0.5  # effect +Z follows the spear's +Y shaft
		if is_instance_valid(_rush_wind):
			_rush_wind.set_active(true)
	elif is_instance_valid(_rush_wind):
		_rush_wind.set_active(false)
	if class_def.shield != null:
		_apply_shield()
	if takes_over_weapon:
		_hold_arms()
	ability_changed.emit()


func _is_bull_rushing() -> bool:
	return ability_active and class_def != null and class_def.ability == &"bull_rush"


## Same range rule is used by the local preview and by the authoritative server.
func clamp_bow_rain_point(point: Vector3) -> Vector3:
	var offset := point - global_position
	offset.y = 0.0
	if offset.length() > BOW_RAIN_RANGE:
		offset = offset.normalized() * BOW_RAIN_RANGE
	return global_position + offset


## Local-only placement preview. Active casts are shown on every peer via bow_rain_target replication.
func set_bow_rain_preview(point: Vector3, shown: bool) -> void:
	_bow_rain_previewing = shown and class_def != null and class_def.ability == &"bow_rain"
	if _bow_rain_previewing:
		bow_rain_target = clamp_bow_rain_point(point)
	_refresh_bow_rain_area()


func _build_bow_rain_area() -> void:
	_bow_rain_area = MeshInstance3D.new()
	_bow_rain_area.name = &"BowRainArea"
	_bow_rain_area.top_level = true
	var mesh := PlaneMesh.new()
	mesh.size = Vector2.ONE * BOW_RAIN_RADIUS * 2.0
	_bow_rain_area.mesh = mesh
	var material := ShaderMaterial.new()
	material.shader = BOW_RAIN_SHADER
	_bow_rain_area.material_override = material
	_bow_rain_area.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bow_rain_area.visible = false
	add_child(_bow_rain_area)
	_place_bow_rain_area()


func _place_bow_rain_area() -> void:
	if not is_instance_valid(_bow_rain_area):
		return
	_bow_rain_area.global_position = bow_rain_target + Vector3(0.0, 0.035, 0.0)
	_refresh_bow_rain_area()


func _refresh_bow_rain_area() -> void:
	if not is_instance_valid(_bow_rain_area):
		return
	var active := ability_active and class_def != null and class_def.ability == &"bow_rain" and not is_dead
	_bow_rain_area.visible = _bow_rain_previewing or active
	var material := _bow_rain_area.material_override as ShaderMaterial
	material.set_shader_parameter(&"opacity", 1.0 if _bow_rain_previewing else 0.85)
	material.set_shader_parameter(&"active", 1.0 if active and not _bow_rain_previewing else 0.0)


## Server: each short run covers every angle and equal-area radial band once, with jittered points
## and shuffled order. This avoids empty patches without creating a visible repeated pattern.
func _prepare_bow_rain_offsets() -> void:
	_bow_rain_offsets.clear()
	var max_radius := BOW_RAIN_RADIUS - BOW_RAIN_EDGE_MARGIN
	for block_start in range(0, BOW_RAIN_TOTAL_ARROWS, BOW_RAIN_COVERAGE_BLOCK):
		var count := mini(BOW_RAIN_COVERAGE_BLOCK, BOW_RAIN_TOTAL_ARROWS - block_start)
		var sectors: Array[int] = []
		var bands: Array[int] = []
		for index in count:
			sectors.append(index)
			bands.append(index)
		sectors.shuffle()
		bands.shuffle()
		var rotation := randf() * TAU
		for index in count:
			var angle := rotation + (sectors[index] + randf()) * TAU / float(count)
			var radius := sqrt((bands[index] + randf()) / float(count)) * max_radius
			_bow_rain_offsets.append(Vector2(cos(angle), sin(angle)) * radius)


## Server: pick from live, hostile targets inside the marked circle. Cycling the sorted list
## spreads the five aimed arrows fairly instead of repeatedly choosing the nearest enemy.
func _bow_rain_target_for_next_arrow() -> Node3D:
	var interval := BOW_RAIN_TOTAL_ARROWS / BOW_RAIN_TARGETED_ARROWS
	if _bow_rain_fired % interval != interval / 2:
		return null
	var candidates: Array[Node3D] = []
	for group in [&"units", &"breakable"]:
		for node in get_tree().get_nodes_in_group(group):
			if not node is Node3D or node == self or GameConfig.is_gone(node) \
					or node.is_queued_for_deletion() or not node.has_method("take_damage") \
					or not GameConfig.is_hostile(self, node):
				continue
			var target_node := node as Node3D
			var delta := target_node.global_position - bow_rain_target
			if Vector2(delta.x, delta.z).length() <= BOW_RAIN_RADIUS and not candidates.has(target_node):
				candidates.append(target_node)
	if candidates.is_empty():
		return null
	candidates.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.get_instance_id() < b.get_instance_id())
	var chosen := candidates[_bow_rain_targeted_fired % candidates.size()]
	_bow_rain_targeted_fired += 1
	return chosen


## Server: fire the next precomputed landing point.
func _bow_rain_arrow() -> void:
	var offset := _bow_rain_offsets[_bow_rain_fired]
	var landing := bow_rain_target + Vector3(offset.x, 0.0, offset.y)
	var aimed_target := _bow_rain_target_for_next_arrow()
	if aimed_target != null:
		var predicted := aimed_target.global_position
		if aimed_target is CharacterBody3D:
			predicted += (aimed_target as CharacterBody3D).velocity \
					* (BOW_RAIN_HEIGHT / BOW_RAIN_ARROW_SPEED)
		var aimed_offset := Vector2(predicted.x - bow_rain_target.x, predicted.z - bow_rain_target.z) \
				.limit_length(BOW_RAIN_RADIUS - BOW_RAIN_EDGE_MARGIN)
		landing = bow_rain_target + Vector3(aimed_offset.x, 0.0, aimed_offset.y)
	var from := Vector3(landing.x, bow_rain_target.y + BOW_RAIN_HEIGHT, landing.z)
	var crit := randf() < crit_chance
	var damage := arrow_damage * BOW_RAIN_DAMAGE * (crit_multiplier if crit else 1.0)
	NetSpawn.projectile(&"arrow", from, Vector3.DOWN, damage, self, crit, false, BOW_RAIN_ARROW_SPEED, true)


## Turn toward held movement input at a limited rate. Releasing WASD keeps the current momentum.
func _steer_bull_rush(input_direction: Vector3, delta: float) -> void:
	input_direction.y = 0.0
	if input_direction.length_squared() < 0.0001 or _bull_rush_direction.length_squared() < 0.0001:
		return
	var target := input_direction.normalized()
	var yaw := atan2(_bull_rush_direction.x, _bull_rush_direction.z)
	var target_yaw := atan2(target.x, target.z)
	yaw += clampf(angle_difference(yaw, target_yaw), -deg_to_rad(BULL_RUSH_TURN_SPEED) * delta,
			deg_to_rad(BULL_RUSH_TURN_SPEED) * delta)
	_bull_rush_direction = Vector3(sin(yaw), 0.0, cos(yaw))


## Server: sweep the path travelled since the previous physics frame. Every valid target takes one heavy
## spear hit, even if a slow frame moved the player farther than one overlap radius.
func _bull_rush_hit() -> void:
	var shape := SphereShape3D.new()
	shape.radius = BULL_RUSH_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = melee_mask
	query.exclude = [get_rid()]
	var start := _bull_rush_last_position
	var finish := global_position + _bull_rush_direction * BULL_RUSH_RADIUS * 0.65
	var distance := start.distance_to(finish)
	var steps := maxi(1, ceili(distance / (BULL_RUSH_RADIUS * 0.65)))
	for step in steps + 1:
		var at := start.lerp(finish, float(step) / steps) + Vector3(0.0, 0.55, 0.0)
		query.transform = Transform3D(Basis.IDENTITY, at)
		for hit in get_world_3d().direct_space_state.intersect_shape(query, 32):
			var collider := hit.collider as Node3D
			if collider == null or not collider.has_method("take_damage") or not _can_hit(collider):
				continue
			var id := collider.get_instance_id()
			if _bull_rush_hit_ids.has(id):
				continue
			_bull_rush_hit_ids[id] = true
			if collider is PhysicsBody3D and collider.is_in_group(&"active_enemies") \
					and (collider.collision_layer & GameConfig.LAYER_ENEMIES) == 0:
				var body := collider as PhysicsBody3D
				add_collision_exception_with(body)
				_bull_rush_exceptions.append(body)
			var crit := randf() < crit_chance
			collider.take_damage(spear_damage * BULL_RUSH_DAMAGE * (crit_multiplier if crit else 1.0), self, true, crit)
	_bull_rush_last_position = global_position


func _clear_bull_rush_exceptions() -> void:
	for body in _bull_rush_exceptions:
		if is_instance_valid(body):
			remove_collision_exception_with(body)
	_bull_rush_exceptions.clear()


## Spear level and straight ahead for the whole charge.
func _bull_rush_pose() -> void:
	_find_slash_skeleton()
	if _right_hold:
		_right_hold.influence = 1.0
	if _left_hold and _shield_is_guarding():
		_left_hold.influence = 1.0
	if _slash_skeleton and not _slash_skeleton.skeleton_updated.is_connected(_place_stab_spear):
		_slash_skeleton.skeleton_updated.connect(_place_stab_spear)
	_thrust_pose(2.0)


## Whirlwind damage: everything hostile around the hero (a cylinder up to the hit height).
func _whirlwind_hit() -> void:
	var shape := CylinderShape3D.new()
	shape.radius = WHIRLWIND_RADIUS
	shape.height = GameConfig.HIT_HEIGHT + 0.3
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3(0, shape.height * 0.5, 0))
	query.collision_mask = melee_mask
	query.exclude = [get_rid()]
	var victims: Array[Node3D] = []
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 32):
		var collider := hit.collider as Node3D
		if collider and not victims.has(collider) and collider.has_method("take_damage") and _can_hit(collider):
			victims.append(collider)
	for victim in victims:
		var crit := randf() < crit_chance
		victim.take_damage(melee_damage * WHIRLWIND_DAMAGE * (crit_multiplier if crit else 1.0), self, true, crit)


## Sword held straight out to the side (the end of the slash), the body turned by the spin.
func _whirlwind_pose() -> void:
	_find_slash_skeleton()
	if _right_hold:
		_right_hold.influence = 1.0
	_slash_pose(3.0)
	if _slash_skeleton:
		_slash_skeleton.transform = _slash_skeleton_rest * Transform3D(
				Basis(Vector3.UP, _whirlwind_local_yaw()))


## The spin's turn relative to the model. Movement can turn the model toward either direction without adding
## to or subtracting from the visible Whirlwind speed.
func _whirlwind_local_yaw() -> float:
	return wrapf(_spin_world_yaw - model.rotation.y, -PI, PI)


## The spin's turn of the skeleton, in the model's space (identity when not spinning).
func _spin_transform() -> Transform3D:
	var local_yaw := _whirlwind_local_yaw()
	if not ability_active or class_def.ability != &"whirlwind" or is_zero_approx(local_yaw):
		return Transform3D.IDENTITY
	return _slash_skeleton_rest * Transform3D(Basis(Vector3.UP, local_yaw)) * _slash_skeleton_rest.affine_inverse()


func _ensure_whirlwind_arc() -> void:
	if not is_instance_valid(_whirlwind_arc):
		_whirlwind_arc = HitFx.persistent_swing_arc(self, 0.55, WHIRLWIND_RADIUS * 0.85,
				Color(1.0, 0.96, 0.85), WHIRLWIND_ARC_DEGREES)
		if _whirlwind_arc:
			_whirlwind_arc.name = &"WhirlwindArc"
			_whirlwind_arc.visible = false
	_find_slash_skeleton()
	if _slash_skeleton and not _slash_skeleton.skeleton_updated.is_connected(_place_whirlwind_arc):
		_slash_skeleton.skeleton_updated.connect(_place_whirlwind_arc)


## Keep the trail flat around the hero, but anchor its bright leading edge and height to the real sword tip.
## Running animations and movement facing can move the hand independently, so this also runs after skeleton
## updates instead of guessing the sword angle from the body rotation.
func _place_whirlwind_arc() -> void:
	if not ability_active or not is_instance_valid(_whirlwind_arc):
		return
	var sword := _weapon_items.get("sword") as Node3D
	if sword == null or not sword.is_inside_tree():
		_whirlwind_arc.rotation.y = _spin_world_yaw - PI * 0.5
		return
	var tip := to_local(sword.global_transform * sword_tip_point)
	var flat_tip := Vector3(tip.x, 0.0, tip.z)
	if flat_tip.length_squared() < 0.0001:
		return
	_whirlwind_arc.position.y = tip.y
	# The persistent mesh starts at -half; adding half puts that bright edge exactly on the sword tip.
	_whirlwind_arc.rotation.y = atan2(flat_tip.x, flat_tip.z) + deg_to_rad(WHIRLWIND_ARC_DEGREES) * 0.5


func _process(delta: float) -> void:
	super(delta)
	_dash_cooldown = maxf(_dash_cooldown - delta, 0.0)
	if ability_active and class_def.ability == &"whirlwind" and not is_dead:
		_ensure_whirlwind_arc()
		if not multiplayer.is_server():
			_ability_visual_elapsed += delta
		_spin_angle = wrapf(deg_to_rad(WHIRLWIND_SPIN) * _ability_visual_elapsed, 0.0, TAU)
		_spin_world_yaw = wrapf(ability_start_yaw - _spin_angle, -PI, PI)
		_whirlwind_pose()
		if is_instance_valid(_whirlwind_arc):
			_whirlwind_arc.visible = true
			_place_whirlwind_arc()
	elif _is_bull_rushing() and not is_dead:
		_bull_rush_pose()
	if is_instance_valid(_rush_wind) and (is_dead or is_downed or not _is_bull_rushing()):
		_rush_wind.set_active(false)


# --- Bow ----------------------------------------------------------------------

## Shows the aim path (local player) and turns the hero toward `aim` (XZ plane). `aim` is the offset from the
## hero to the point aimed at (mouse), or just a direction when it is no longer than `AIM_POINT_MIN` (sticks).
func set_aim(aim: Vector3) -> void:
	if is_dead or is_downed or aim.length_squared() < 0.0001 or not holds_ranged():
		return
	aim.y = 0.0
	var direction := aim.normalized()
	look_override = direction
	if not is_local():
		return
	# The path the shot will really take: from where it leaves (the nocked arrow / the spear) to the aim point.
	var from := _shot_from(direction)
	var to := _aim_point(aim)
	to.y = from.y
	var length := maxf(from.distance_to(to), 0.5)
	_aim_indicator.global_position = from
	_aim_indicator.global_rotation = Vector3(0.0, atan2(to.x - from.x, to.z - from.z), 0.0)
	var start := minf(0.3, length * 0.5)
	_aim_line.position.z = start
	_aim_line.scale.z = maxf(length - start - AIM_RETICLE_SIZE * 0.35, 0.01)
	(_aim_line.material_override as ShaderMaterial).set_shader_parameter(&"line_length", _aim_line.scale.z)
	_aim_reticle.position.z = length
	_aim_indicator.visible = true


## Where an aimed shot heads: the aimed point, or `aim_range` straight ahead for a bare direction; at most
## `aim_range` away. At shot height.
func _aim_point(aim: Vector3) -> Vector3:
	aim.y = 0.0
	var distance := aim.length() if aim.length() > AIM_POINT_MIN else aim_range
	return global_position + Vector3(0.0, SHOT_HEIGHT, 0.0) + aim.normalized() * minf(distance, aim_range)


## Where a shot toward `direction` leaves from: the nocked arrow (bow, in the model's frame turned to face
## `direction`), or just in front of the chest (spear).
func _shot_from(direction: Vector3) -> Vector3:
	if current_weapon() == "javelin" or _nock_body == Vector3.INF:
		return global_position + Vector3(0.0, SHOT_HEIGHT, 0.0) + direction * 0.4
	var nock := model.global_transform * _nock_body - global_position
	var turn := atan2(direction.x, direction.z) - model.global_rotation.y
	var from := global_position + nock.rotated(Vector3.UP, turn)
	from.y = clampf(from.y, 0.3, 0.8)
	return from


func clear_aim() -> void:
	look_override = Vector3.ZERO
	_aim_indicator.visible = false


func is_aiming() -> bool:
	return look_override != Vector3.ZERO


## Fires the ranged weapon in hand (arrow, or a thrown spear) toward `direction`, or at the nearest
## enemy when no direction is given. Server only.
func shoot(direction: Vector3 = Vector3.ZERO) -> void:
	if is_dead or is_downed or (ability_active and class_def.ability != &"bow_rain") or not holds_ranged():
		return
	if _knife_timer > 0.0:  # stabbing with the knife: no arrows meanwhile
		_pending_shot = Vector3.ZERO
		return
	if _shoot_timer > 0.0:
		if direction != Vector3.ZERO:
			_pending_shot = direction
		return
	var spear := current_weapon() == "javelin"
	_shoot_timer = spear_cooldown if spear else shoot_cooldown
	if direction == Vector3.ZERO:
		var target := find_nearest(TARGET_GROUPS, aim_range, global_position, {&"camps": 3.0})
		direction = target.global_position - global_position if target else facing()
	# Aimed: exactly where the player aims (no snapping onto a target). `direction` may carry the distance
	# to the aimed point (see set_aim): the shot leaves from the bow / spear and flies through that point.
	direction.y = 0.0
	var target_point := _aim_point(direction)
	face_now(direction.normalized())
	var crit := randf() < crit_chance
	var multiplier := crit_multiplier if crit else 1.0
	var from := _shot_from(direction.normalized())
	direction = target_point - from
	direction.y = 0.0
	direction = direction.normalized()
	if spear:
		play_action("attack-melee-right", 0.4, ARM_RIGHT)
		NetSpawn.projectile(&"player_spear", from, direction, spear_damage * multiplier, self, crit)
	else:
		play_action("holding-left-shoot", 0.25, ARM_LEFT)
		# Fire Range: the arrow flies longer, in step with the farther aim; Penetration: it goes through enemies.
		NetSpawn.projectile(&"arrow", from, direction, arrow_damage * multiplier, self, crit, true, 0.0, false,
				{"pierce": arrow_pierce, "lifetime_scale": aim_range / _base_aim_range})


## Aim path (drifting chevrons) and a reticle at the aim point, at shot height; placed by `set_aim`.
## Local player only.
func _build_aim_indicator() -> void:
	_aim_indicator = Node3D.new()
	_aim_indicator.top_level = true
	_aim_indicator.visible = false
	add_child(_aim_indicator)
	# Both lie flat along +Z (the indicator is turned toward the aim point).
	var strip := PlaneMesh.new()
	strip.size = Vector2(AIM_LINE_WIDTH, 1.0)
	strip.center_offset = Vector3(0.0, 0.0, 0.5)
	var line_material := ShaderMaterial.new()
	line_material.shader = AIM_LINE_SHADER
	line_material.set_shader_parameter(&"width", AIM_LINE_WIDTH)
	_aim_line = MeshInstance3D.new()
	_aim_line.mesh = strip
	_aim_line.material_override = line_material
	_aim_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aim_indicator.add_child(_aim_line)
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	var reticle_material := ShaderMaterial.new()
	reticle_material.shader = AIM_RETICLE_SHADER
	_aim_reticle = MeshInstance3D.new()
	_aim_reticle.mesh = quad
	_aim_reticle.scale = Vector3.ONE * AIM_RETICLE_SIZE
	_aim_reticle.material_override = reticle_material
	_aim_reticle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aim_indicator.add_child(_aim_reticle)


## How far the melee weapon reaches from the hero's center (the aim wedge and the hit wedge).
func melee_reach() -> float:
	return float(WEAPONS.get(_melee_weapon(), WEAPONS.sword).reach)


func _roll_melee_damage() -> Array:
	var crit := randf() < crit_chance
	var base := spear_damage if current_weapon() == "spear" else melee_damage
	return [base * (crit_multiplier if crit else 1.0), crit]


## The hero may aim elsewhere while the attack animation winds up. Test exactly the wedge currently shown
## to the player; a released/tapped attack falls back to the direction the body still faces.
func _melee_hit_direction() -> Vector3:
	if _thrusting():
		return _thrust_dir
	return _melee_aim if _melee_aim != Vector3.ZERO else facing()


## A spear stab is under way: its lane stays where it started.
func _thrusting() -> bool:
	return _thrust_dir != Vector3.ZERO and Time.get_ticks_msec() < _thrust_until and current_weapon() == "spear"


func _facing_locked() -> bool:
	return _thrusting()


## Melee hits a prism, so big colliders count by their surface instead of their center.
## The spear matches the visible decal exactly; the sword also covers point-blank targets behind its start.
func _melee_query(direction: Vector3) -> PhysicsShapeQueryParameters3D:
	if _melee_wedge == null or _melee_wedge_weapon != _melee_weapon():
		_melee_wedge_weapon = _melee_weapon()
		var points := PackedVector3Array()
		for y in [0.05, GameConfig.HIT_HEIGHT + 0.3]:
			for corner in melee_outline(0.25 if melee_lane() > 0.0 else -0.3):
				points.append(Vector3(corner.x, y, corner.y))
		_melee_wedge = ConvexPolygonShape3D.new()
		_melee_wedge.points = points
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _melee_wedge
	query.transform = Transform3D(Basis(Vector3.UP, atan2(direction.x, direction.z)), global_position)
	query.collision_mask = melee_mask
	query.exclude = [get_rid()]
	return query


## Orange marker of the hit area in front of the hero while aiming the melee weapon (fan / spear lane).
func _build_melee_indicator() -> void:
	_melee_indicator = _fan_indicator(melee_outline(0.25))
	_knife_indicator = _fan_indicator(knife_outline(0.25))


func _fan_indicator(outline: PackedVector2Array) -> Node3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.62, 0.2, 0.45)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var wedge := ImmediateMesh.new()
	wedge.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	for i in range(1, outline.size() - 1):  # a fan over the convex outline
		for corner in [outline[0], outline[i], outline[i + 1]]:
			wedge.surface_add_vertex(Vector3(corner.x, 0.05, corner.y))
	wedge.surface_end()
	var part := MeshInstance3D.new()
	part.mesh = wedge
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var indicator := Node3D.new()
	indicator.visible = false
	indicator.add_child(part)
	add_child(indicator)
	return indicator


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
		Pickup.Kind.XP:
			return not training_mode and has_ability() and not ability_xp_locked and xp < class_def.ability_xp
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
		Pickup.Kind.XP:
			xp = mini(xp + amount, class_def.ability_xp)
	return true


# --- Army ---------------------------------------------------------------------

## This player's soldiers currently in the world (all of them follow).
func followers() -> Array[Node]:
	return get_tree().get_nodes_in_group(&"allies").filter(
			func(ally: Node) -> bool: return ally.get("owner_peer") == peer_id and not ally.get("is_dead"))


## Server: where this hero walked lately (newest last), so soldiers cut off by a wall or a building can
## follow the same way (`Ally._trail_point`). A point every TRAIL_STEP m, at most TRAIL_SIZE.
const TRAIL_STEP: float = 0.8
const TRAIL_SIZE: int = 48
var trail: PackedVector3Array = PackedVector3Array()


func _record_trail() -> void:
	if is_dead or is_downed:
		return
	var here := Vector3(global_position.x, 0.0, global_position.z)
	if trail.is_empty() or trail[trail.size() - 1].distance_to(here) >= TRAIL_STEP:
		trail.append(here)
		if trail.size() > TRAIL_SIZE:
			trail.remove_at(0)


## Everything that counts toward follower_cap: following + in training.
func army_size() -> int:
	return followers().size() + soldiers_training


## Seconds until the next soldier in training is ready (0 = none training).
func next_soldier_in() -> float:
	return _training_left[0] if not _training_left.is_empty() else 0.0


# --- Server tick (soldier training, trail, orders, ability) ------------------------

func _physics_process(delta: float) -> void:
	super(delta)
	_knife_timer = maxf(_knife_timer - delta, 0.0)
	# A queue: the next soldier starts training when the one before it is ready.
	if not _training_left.is_empty():
		_training_left[0] = maxf(_training_left[0] - delta, 0.0)
	if multiplayer.is_server() and not _training_left.is_empty() and _training_left[0] <= 0.0:
		_finish_training()
	if multiplayer.is_server():
		_record_trail()
	if multiplayer.is_server() and army_order == Order.KILL:
		_update_kill_order()
	if multiplayer.is_server() and ability_active:
		_update_ability(delta)
	if multiplayer.is_server() and ability_xp_locked:
		_update_ability_xp_lockout(delta)


## The oldest soldier in training is ready: it appears right behind you and follows at once.
func _finish_training() -> void:
	soldiers_training -= 1
	var at := GameConfig.clamp_to_world(global_position - facing() * 1.3)
	NetSpawn.unit(&"ally", at, {"team": team_id, "owner": peer_id, "weapon": class_def.ally_weapon})
	_net_soldier_ready.rpc(at)


@rpc("authority", "call_local", "reliable")
func _net_soldier_ready(at: Vector3) -> void:
	HitFx.flash(at + Vector3(0, 0.6, 0), HitFx.REVIVE_SPARKLE, Color(unit_color, 0.9), 1.4, 0.5)
	HitFx.flash(at + Vector3(0, 0.05, 0), HitFx.COMBO_RING, Color(unit_color, 0.8), 1.6, 0.4)
	soldier_ready.emit()


# --- Class upgrades -------------------------------------------------------------

## Level × amount of a class upgrade (0 when not owned).
func _upgrade_amount(id: StringName) -> float:
	var level := upgrade_level(id)
	if level == 0:
		return 0.0
	for def in CATALOG.upgrades:
		if def.id == id:
			return level * def.amount
	return 0.0


func owns_shield() -> bool:
	return class_def != null and class_def.shield != null and upgrade_level(&"shield") > 0


## The class's weapons, without the thrown spear until "Can Throw" is bought.
func _class_weapons() -> PackedStringArray:
	var carried := PackedStringArray()
	for weapon in class_def.weapons:
		if weapon != "javelin" or upgrade_level(&"spear_throw") > 0:
			carried.append(weapon)
	return carried


## Every peer: the stats the class upgrades change, straight from the levels (so clients aim with the same range
## and swing at the same speed). Fire Rate shortens the cooldowns and speeds the swing / thrust up to match.
func _apply_class_upgrades() -> void:
	if class_def == null or _base_aim_range <= 0.0:
		return
	melee_damage = _base_melee_damage * (1.0 + _upgrade_amount(&"sword_damage"))
	spear_damage = _base_spear_damage * (1.0 + _upgrade_amount(&"spear_damage"))
	arrow_damage = _base_arrow_damage * (1.0 + _upgrade_amount(&"bow_damage"))
	var rate := 1.0 + _upgrade_amount(&"sword_rate") + _upgrade_amount(&"spear_rate") + _upgrade_amount(&"bow_rate")
	var melee := _melee_weapon()
	if melee != "":
		melee_cooldown = WEAPONS[melee].cooldown / rate
	anim_speed = rate
	shoot_cooldown = _base_shoot_cooldown / rate
	spear_cooldown = _base_spear_cooldown / rate
	aim_range = _base_aim_range + _upgrade_amount(&"bow_range")
	arrow_pierce = upgrade_level(&"bow_pierce")
	knockback_power = _upgrade_amount(&"sword_knockback") if upgrade_level(&"sword_knockback") > 0 else 1.0
	sword_wave = _upgrade_amount(&"sword_wave")
	dash_damage = _upgrade_amount(&"sword_dash")
	knife_damage = _upgrade_amount(&"knife")
	var carried := _class_weapons()
	if carried != weapons:
		weapons = carried
	if _left_item:
		_show_shield()


## Server, Training Field: the class's unlocks are owned from the start.
func _grant_training_unlocks() -> void:
	var levels := upgrade_levels.duplicate()
	for def in class_upgrades():
		if TRAINING_UNLOCKS.has(def.id):
			levels[def.id] = 1
	upgrade_levels = levels
	if owns_shield():
		shield_health = class_def.shield_health


## Server: owning upgrade `id` (tests, Training Field): one more level, applied like a purchase.
func grant_upgrade(id: StringName) -> void:
	for def in CATALOG.upgrades:
		if def.id == id and not is_upgrade_maxed(def):
			var levels := upgrade_levels.duplicate()
			levels[id] = upgrade_level(id) + 1
			upgrade_levels = levels
			_apply_upgrade(def)
			return


# --- Dash Attack (Swordsman) ---------------------------------------------------------

func has_dash() -> bool:
	return dash_damage > 0.0


## Seconds until the next dash (0 = ready).
func dash_cooldown_left() -> float:
	return _dash_cooldown


func can_dash() -> bool:
	return has_dash() and _dash_cooldown <= 0.0 and _dash_left <= 0.0 and not is_dead and not is_downed \
			and not ability_active and not shield_up


## Server: dash toward `direction` (ZERO: where the hero faces), slashing everything crossed.
func dash(direction: Vector3) -> void:
	if not can_dash():
		return
	_start_dash(direction)
	play_action("attack-melee-right", DASH_TIME + 0.15, ARM_RIGHT)
	dash_active = true


## Local input (C / L3 / the touch dash button): dash now on the server, else predict it here and ask the server.
func request_dash(direction: Vector3) -> void:
	if multiplayer.is_server():
		dash(direction)
		return
	if can_dash():
		_start_dash(direction)
	net_dash.rpc_id(1, direction)


@rpc("any_peer", "call_remote", "reliable")
func net_dash(direction: Vector3) -> void:
	if _from_owner():
		dash(direction)


## Server and the predicting owner: the dash's direction, timer and cooldown; enemies don't block it.
func _start_dash(direction: Vector3) -> void:
	direction.y = 0.0
	_dash_direction = direction.normalized() if direction.length_squared() > 0.0001 else facing()
	_dash_left = DASH_TIME
	_dash_cooldown = DASH_COOLDOWN
	_dash_last_position = global_position
	_dash_hit_ids.clear()
	set_melee_aim(Vector3.ZERO)
	clear_aim()
	face_now(_dash_direction)
	if _dash_saved_mask < 0:
		_dash_saved_mask = collision_mask
		collision_mask &= ~GameConfig.LAYER_ENEMIES
	_update_move_speed()


## One movement frame of the dash (it moves at dash speed, see `_update_move_speed`).
func _dash_step(delta: float) -> Vector3:
	_dash_left -= delta
	if multiplayer.is_server():
		_dash_hit()
	if _dash_left <= 0.0:
		_dash_left = 0.0
		if _dash_saved_mask >= 0:
			collision_mask = _dash_saved_mask
			_dash_saved_mask = -1
		_update_move_speed()
		if multiplayer.is_server():
			dash_active = false
	return _dash_direction


## Server: every target along the path since the last frame takes one dash slash.
func _dash_hit() -> void:
	var shape := SphereShape3D.new()
	shape.radius = DASH_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = melee_mask
	query.exclude = [get_rid()]
	var finish := global_position + _dash_direction * DASH_RADIUS * 0.5
	var steps := maxi(1, ceili(_dash_last_position.distance_to(finish) / (DASH_RADIUS * 0.6)))
	for step in steps + 1:
		query.transform = Transform3D(Basis.IDENTITY, _dash_last_position.lerp(finish, float(step) / steps) + Vector3(0, 0.55, 0))
		for hit in get_world_3d().direct_space_state.intersect_shape(query, 32):
			var collider := hit.collider as Node3D
			if collider == null or not collider.has_method("take_damage") or not _can_hit(collider) \
					or _dash_hit_ids.has(collider.get_instance_id()):
				continue
			_dash_hit_ids[collider.get_instance_id()] = true
			var crit := randf() < crit_chance
			collider.take_damage(melee_damage * dash_damage * (crit_multiplier if crit else 1.0), self, true, crit)
	_dash_last_position = global_position


## Every peer: a dust puff where the dash starts and a streak trailing behind the hero.
func _apply_dash() -> void:
	if not dash_active or not is_inside_tree():
		return
	var back := -facing()
	HitFx.burst(global_position + Vector3(0, 0.1, 0), HitFx.Kind.DIRT, 8, back + Vector3.UP * 0.5)
	HitFx.stab(self, 0.55, atan2(back.x, back.z), DASH_DISTANCE * 0.7, 0.6, DASH_COLOR, DASH_TIME + 0.15)


# --- Knife (Bowman) ---------------------------------------------------------------

## Bow range now / at the start (Fire Range upgrades raise it; the camera zooms out with it).
func aim_range_scale() -> float:
	return aim_range / _base_aim_range if _base_aim_range > 0.0 else 1.0


func has_knife() -> bool:
	return knife_damage > 0.0


func can_knife() -> bool:
	return has_knife() and not is_dead and not is_downed and not (ability_active and class_def.ability != &"bow_rain")


## Server: a quick knife stab toward `direction` (ZERO: where the hero faces). Cancels a drawn bow shot.
func knife_attack(direction: Vector3) -> void:
	if not can_knife() or _knife_timer > 0.0:
		return
	_knife_timer = KNIFE_COOLDOWN
	direction.y = 0.0
	direction = direction.normalized() if direction.length_squared() > 0.0001 else facing()
	_pending_shot = Vector3.ZERO
	face_now(direction)
	play_action("knife-stab", KNIFE_COOLDOWN * 0.7, ARM_RIGHT)
	get_tree().create_timer(KNIFE_HIT_DELAY).timeout.connect(_knife_hit.bind(direction))


func request_knife(direction: Vector3) -> void:
	if multiplayer.is_server():
		knife_attack(direction)
	else:
		net_knife.rpc_id(1, direction)


@rpc("any_peer", "call_remote", "reliable")
func net_knife(direction: Vector3) -> void:
	if _from_owner():
		knife_attack(direction)


## The knife's hit fan seen from above (x, z in the hero's space, +Z forward), starting at `back`.
func knife_outline(back: float) -> PackedVector2Array:
	var points := PackedVector2Array([Vector2(0.0, back)])
	var half := deg_to_rad(KNIFE_ARC * 0.5)
	for i in 7:
		var a := -half + 2.0 * half * i / 6.0
		points.append(Vector2(sin(a), cos(a)) * KNIFE_REACH)
	return points


## Local: the knife's fan under the hero toward `direction` while the knife is held; ZERO hides it.
func set_knife_aim(direction: Vector3) -> void:
	direction.y = 0.0
	var shown := direction.length_squared() > 0.0001 and can_knife() and is_local()
	_knife_indicator.visible = shown
	if shown:
		_knife_indicator.rotation.y = atan2(direction.x, direction.z)


## Server: everything hostile in the knife's fan.
func _knife_hit(direction: Vector3) -> void:
	if is_dead or is_downed:
		return
	var points := PackedVector3Array()
	for y in [0.05, GameConfig.HIT_HEIGHT + 0.3]:
		for corner in knife_outline(-0.3):
			points.append(Vector3(corner.x, y, corner.y))
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(Vector3.UP, atan2(direction.x, direction.z)), global_position)
	query.collision_mask = melee_mask
	query.exclude = [get_rid()]
	var victims: Array[Node3D] = []
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 32):
		var collider := hit.collider as Node3D
		if collider and not victims.has(collider) and collider.has_method("take_damage") and _can_hit(collider):
			victims.append(collider)
	for victim in victims:
		var crit := randf() < crit_chance
		victim.take_damage(knife_damage * (crit_multiplier if crit else 1.0), self, true, crit)


## Every peer: the knife appears in the right hand for the stab (Kenney's melee clip on that arm) with a
## small swing trail.
func _knife_stab_visual(duration: float) -> void:
	if is_downed:
		return
	if _knife_item == null:
		var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
		if skeleton:
			_knife_item = _attach_item(skeleton, KNIFE_SCENE, "arm-right")
		if _knife_item:
			_knife_item.position = right_swing_offset + class_def.hand_offset
			_knife_item.rotation_degrees = right_swing_rotation
			_knife_item.scale = Vector3.ONE * KNIFE_SCALE
	if _knife_item:
		_knife_item.visible = true
		get_tree().create_timer(duration).timeout.connect(func() -> void:
			if is_instance_valid(_knife_item):
				_knife_item.visible = false)
	super._play_action_local("attack-melee-right", duration, ARM_RIGHT)
	var forward := facing()
	get_tree().create_timer(KNIFE_HIT_DELAY * 0.6).timeout.connect(func() -> void:
		if is_inside_tree() and not is_dead:
			HitFx.swing_arc(self, 0.5, atan2(forward.x, forward.z), KNIFE_REACH, Color(1.0, 0.96, 0.85), KNIFE_ARC))


# --- Economy ------------------------------------------------------------------

func upgrade_level(id: StringName) -> int:
	return upgrade_levels.get(id, 0)


func upgrade_cost(def: UpgradeDef) -> int:
	if training_mode and def.is_class_upgrade():
		return 0  # the Training Field lets you try every upgrade
	return def.cost_at(upgrade_level(def.id))


## A pick-one class upgrade whose alternative is owned (Knock Back / Wave).
func is_upgrade_locked(def: UpgradeDef) -> bool:
	for other in def.excludes:
		if upgrade_level(other) > 0:
			return true
	return false


## The upgrades sheet's items on `tab` (UpgradeDef.sheet: &"hero" = Vitality, Potion; &"army" = Recruit,
## Soldier Damage, Soldier Health, Command), in catalog order. Class upgrades: `class_upgrades()`.
func sheet_items(tab: StringName) -> Array[UpgradeDef]:
	var result: Array[UpgradeDef] = []
	for def in CATALOG.upgrades:
		if def.sheet == tab:
			result.append(def)
	return result


## The class upgrades this hero's class can buy (upgrades sheet), in catalog order.
func class_upgrades() -> Array[UpgradeDef]:
	var result: Array[UpgradeDef] = []
	for def in CATALOG.upgrades:
		if class_def and def.classes.has(class_def.id):
			result.append(def)
	return result


func is_upgrade_maxed(def: UpgradeDef) -> bool:
	return not def.is_consumable() and upgrade_level(def.id) >= def.max_level


## False when buying would be wasted (e.g. potion at full health).
func is_upgrade_useful(def: UpgradeDef) -> bool:
	match def.id:
		&"potion":
			return health < max_health
		&"recruit":
			return army_size() < follower_cap
	if def.is_class_upgrade():
		return class_def != null and def.classes.has(class_def.id) and not is_upgrade_locked(def)
	return true


## Everything is bought anywhere from the upgrades sheet (checked on the server too).
func can_buy(def: UpgradeDef) -> bool:
	return not is_dead and not is_downed and not is_upgrade_maxed(def) and is_upgrade_useful(def) \
			and coins >= upgrade_cost(def)


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
	if def.is_class_upgrade():
		# The stats follow the levels (`_apply_class_upgrades`, every peer); a new shield arrives whole.
		if def.id == &"shield":
			shield_health = class_def.shield_health
		return
	match def.id:
		&"vitality":
			max_health += def.amount
			heal(def.amount)
		&"soldier_damage", &"soldier_health":
			if def.id == &"soldier_damage":
				ally_damage += def.amount
			else:
				ally_health += def.amount
			for ally in followers():
				(ally as Ally).refresh_army_bonus()
		&"command":
			follower_cap += int(def.amount)
		&"recruit":
			for i in int(def.amount):
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
	ability_active = false
	clear_aim()
	set_melee_aim(Vector3.ZERO)
	joystick_vector = Vector2.ZERO
	super()


## Respawn (server): back on your feet with your soldiers following again.
func revive(at: Vector3) -> void:
	is_downed = false
	shield_up = false
	shield_health = class_def.shield_health if owns_shield() else 0.0
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
	if not is_dead and _shield_blocks(attacker):
		_block(amount)
		return
	super(amount, attacker, is_melee, crit)


func heal(amount: float) -> void:
	if not is_downed:
		super(amount)


# --- Downed / revive (server) -------------------------------------------------------

func _go_down() -> void:
	ability_active = false
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


## Every peer: crawl speed while downed, a little slower carrying a shield, slower still behind a raised one.
func _update_move_speed() -> void:
	if _dash_left > 0.0:
		move_speed = DASH_DISTANCE / DASH_TIME
		return
	if _base_move_speed > 0.0:
		var ability_scale := 1.0
		if ability_active:
			match class_def.ability:
				&"whirlwind": ability_scale = WHIRLWIND_SPEED
				&"bull_rush": ability_scale = BULL_RUSH_SPEED
		move_speed = running_speed() * (DOWNED_SPEED if is_downed else 1.0) * (BLOCK_SPEED if shield_up else 1.0) \
				* ability_scale


## Class running speed: slower while an unbroken shield is carried (ClassDef.shield_move_speed).
func running_speed() -> float:
	if has_shield() and class_def.shield_move_speed > 0.0:
		return class_def.shield_move_speed
	return _base_move_speed


## Every peer: crawl speed, "HELP!" label + revive bar, off-screen marker for teammates.
func _apply_downed() -> void:
	_update_move_speed()
	if is_downed:
		shield_up = false
	_apply_shield()
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
		_knife_indicator.visible = false
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
			if candidate == null or GameConfig.is_gone(candidate) or not GameConfig.is_hostile(self, candidate):
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
