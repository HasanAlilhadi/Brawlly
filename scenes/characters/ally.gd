class_name Ally
extends Unit
## Soldier recruited from the upgrades sheet (see Player.soldiers_training): once trained it appears behind
## its player (`owner_peer`) and follows in a compact formation, fighting nearby hostiles: orcs, and in versus
## modes other players and their soldiers. Once dead, it is gone for good.
## Four kinds, picked on the Army tab (`weapon`, see WEAPON_STATS): sword and shield; bow — archers shoot from
## `archer_range()` (half their hero's bow range) with a clear line of fire; wizard — magic bolts from a little
## closer; healer — no attack, heals the most wounded friend near (`_heal_move`). The three ranged kinds step
## back from enemies that get close and stand in rows behind the hero (`is_ranged()`).
## **A soldier carries out orders, it doesn't look around for itself**: who to fight comes from its commander
## (`BattleBrain`, one pass for the whole army on a worker thread — `_best_enemy` only says what it needs and checks
## the pick): enemies hitting the hero, then the soldiers, come first; melee soldiers spread over the enemies
## instead of piling on one; archers focus the wounded. So do a healer's patient and who a shooter steps back from.
## Following: when a wall or a building
## cuts a soldier off from its spot, it walks the hero's recent path (`Player.trail`, `_trail_point`).
## The player's army order (Player.army_order) changes where the formation stands: around the player
## (FOLLOW), or around Player.army_point, where they fight everything nearby (CHARGE) or guard it (HOLD);
## KILL hunts Player.army_target down (then CHARGE where it fell). Orders are always obeyed: on every new
## order (Player.order_serial) soldiers drop their fight at once and walk to their new spot without
## fighting (`_regroup`, until they get there or `regroup_time` runs out); KILL goes straight for the target.
## Conquest squads (`squad` > 0, ConquestSquads): not in the hero's formation and deaf to the hero's orders; the
## leader (`squad_leader`, a banner) walks to the squad's goal, the rest follow it and stand around the goal there
## (`_think_squad`), guarding it within ConquestSquads.GUARD.

const BOW_SCENE := preload("res://assets/items/forest/bow.glb")
const ORB_SCENE := preload("res://scenes/characters/soldier_orb.tscn")
const POTION_SCENE := preload("res://assets/items/dungeon/potion.glb")
## Wizards shoot from this share of an archer's range.
const WIZARD_RANGE_SHARE: float = 0.8
## Healers: heal the most wounded friend (hero or soldier of their team) within HEAL_SIGHT, from HEAL_RANGE,
## `heal` health every cooldown (whole points: health is replicated).
const HEAL_SIGHT: float = 9.0
const HEAL_RANGE: float = 4.5
const HEAL_COLOR := Color(0.45, 1.0, 0.55)
## Archers shoot from this share of their hero's bow range (Player.aim_range, Fire Range included).
const ARCHER_RANGE_SHARE: float = 0.5
## An enemy closer than this makes an archer step back (still shooting).
const ARCHER_KEEP_AWAY: float = 2.6
## Picking a target, in m of extra distance: each squadmate already on an enemy (melee soldiers spread out),
## an enemy hitting the hero / one of us (it counts as closer), a blocked line of fire (archers).
const CROWD_PENALTY: float = 1.6
const DEFEND_BONUS: float = 4.0
const GUARD_BONUS: float = 2.0
const BLOCKED_PENALTY: float = 3.0
## What blocks walking and arrows (trees, houses, camp walls, fences).
const OBSTACLE_MASK: int = GameConfig.LAYER_WORLD | GameConfig.LAYER_FENCE
## Physics frames an archer keeps its line-of-fire / step-back checks before looking again.
const SHOT_CHECK_FRAMES: int = 12
## Weapon id (ClassDef.ally_weapon) -> stats over the scene's (the sword soldier). `damage` is per hit
## (an arrow for the bow).
## Every soldier's health and damage × this (on top of the weapon's stats and the Soldier Damage / Health upgrades).
const BASE_POWER: float = 1.25
## A ranged soldier pushed into melee hits with this share of its shot's damage.
const BOW_MELEE_SHARE: float = 0.5
## Conquest weapons wear by battle: a battle ends BATTLE_END seconds after the soldier's last attack, and then
## counts as one use (`weapon_uses`). Every WEAR_STEP uses the weapon is weaker (WEAR_LOSS of its damage each),
## after WEAPON_LIFE uses it is broken: the soldier is useless, every blow, shot or heal of its is BROKEN_DAMAGE
## (`hit_damage`). A new weapon (one weapons supply) resets it.
const BATTLE_END: float = 6.0
const WEAPON_LIFE: int = 8
const WEAR_STEP: int = 2
const WEAR_LOSS: float = 0.15
const BROKEN_DAMAGE: float = 1.0
const WEAPON_STATS: Dictionary = {
	"sword": {},
	"bow": {"damage": 11.0, "health": 65.0, "cooldown": 1.2},
	"wizard": {"damage": 17.0, "health": 60.0, "cooldown": 1.8},
	"healer": {"damage": 4.0, "health": 70.0, "cooldown": 1.4, "heal": 8.0},
}

@export var aggro_range: float = 6.0
## Stop chasing when this far from the player.
@export var leash_range: float = 9.0
## Soldiers move at exactly two speeds: running (move_speed) or walking (this share of it, with the walk clip),
## never faster to catch up or charge (`_get_move_input` snaps every move to one of them).
@export var walk_share: float = 0.45
## Closer than this to its spot in the formation a soldier walks the rest of the way.
@export var walk_distance: float = 2.0
var _shot_node: Node3D
var _shot_until: int = 0
var _shot_clear: bool = true
var _away_until: int = 0
var _away := Vector3.ZERO
## > 0 this frame: move at exactly this share of move_speed (keeping pace with a moving hero).
var _match_pace: float = -1.0
## Orders: soldiers fight hostiles within this distance of the charge / hold point.
@export var charge_radius: float = 9.0
@export var hold_radius: float = 6.0
## After an order: at most this many seconds of walking to the new spot without fighting.
@export var regroup_time: float = 6.0
## Regrouping ends this close to the soldier's slot (then it fights normally again).
@export var regroup_arrive: float = 2.5
## Archers shoot from up to this far (from the target's surface); set from `archer_range()` on every think.
var shoot_range: float = 6.0
## MARCH (Conquest): arrived this close to the territory, soldiers patrol a ring of PATROL_RADIUS around it
## (turning PATROL_TURN rad/s) and fight what comes within MARCH_GUARD of it; on the way they only fight what
## comes within aggro_range. The path comes from a NavigationAgent3D made on the first march order (none before).
const MARCH_ARRIVE: float = 10.0
const MARCH_GUARD: float = 12.0
const PATROL_RADIUS: float = 5.0
const PATROL_TURN: float = 0.15
var _nav: NavigationAgent3D
var _patrol_angle: float = 0.0
## Ranks (every mode): kills raise a soldier through RANK_NAMES (at RANK_KILLS; a healer's heals count too,
## one kill per HEALS_PER_KILL); every rank adds RANK_BONUS to its health and damage. Conquest barracks also train
## the soldiers waiting in them (`rank_for_drill`: DRILL_SECONDS of training per rank), who leave with that rank
## (spawn data "rank"). `rank` is replicated (Sync) for the badge over its head.
static var progression: bool = true
const RANK_KILLS: Array[int] = [0, 2, 5, 10, 20]
const DRILL_SECONDS: Array[float] = [0.0, 45.0, 120.0, 240.0, 420.0]
const HEALS_PER_KILL: int = 3
const RANK_NAMES: PackedStringArray = ["Recruit", "Soldier", "Veteran", "Elite", "Champion"]
const RANK_BADGES: PackedStringArray = ["", "I", "II", "III", "IV"]
const RANK_BONUS: float = 0.15
const RANK_COLOR := Color(1.0, 0.82, 0.3)
## Mustered (Conquest, spawn data "muster"): it walks from its barracks to its General on the navigation mesh,
## fighting only what comes within aggro_range, and joins the formation within MUSTER_JOIN.
const MUSTER_JOIN: float = 10.0
var mustering: bool = false
var kills: int = 0
var _heals: int = 0
## Healer: who it is healing (server).
var _patient: Unit
var rank: int = 0:
	set(value):
		var promoted := value > rank
		rank = value
		_show_rank(promoted)
var _rank_label: Label3D
## Conquest upkeep (server; the defaults change nothing in other modes): speed and damage multipliers (no
## ration, a worn weapon) and the battles its weapon has been through (-1 = it never wears; see BATTLE_END).
var upkeep_speed: float = 1.0
var upkeep_damage: float = 1.0
var weapon_uses: int = -1:
	set(value):
		weapon_uses = value
		upkeep_damage = weapon_power()
## Server: seconds left of the battle it is in (0 = not fighting).
var _battle: float = 0.0
## Conquest: meals it carries (LogisticsManager; -1 = it never eats).
var rations: int = -1

## The weapon it fights with (from the spawn data, every peer, before entering the tree).
var weapon: String = "sword"
## Conquest: its squad (0 = in its hero's army) and whether it leads it (replicated: the banner, the map).
var squad: int = 0:
	set(value):
		if value != squad:
			squad = value
			_forget_followers()
var squad_leader: bool = false:
	set(value):
		squad_leader = value
		_show_banner()
var _banner: Node3D
## Server: where it walks to in its squad (the goal for the leader, behind the leader for the rest).
var _squad_spot: Vector3 = Vector3.INF

var leader: Player
var target: Node3D
## What it asks its commander for (BattleBrain reads these): a foe within `scan_range` of `scan_origin` (INF =
## where it stands), else within `scan_own` of itself (0 = no second look). Set by `_best_enemy`.
var scan_origin: Vector3 = Vector3.INF
var scan_range: float = 0.0
var scan_own: float = 0.0
## A pick may be this much farther than asked (it is a few frames old; the hero and the soldier moved on).
const ORDER_SLACK: float = 2.0

var _think_timer: float = 0.0
## Server: the leader's order_serial this soldier has obeyed.
var _order_serial: int = 0
## Server: seconds left of walking to the ordered spot without fighting (0 = not regrouping).
var _regroup: float = 0.0
var _slot_offset: Vector3
var _base_max_health: float
var _base_damage: float
## Following: a point of the hero's trail to walk to while the straight way to the slot is blocked.
var _via: Vector3 = Vector3.INF
## The hero's walking direction (archers line up behind it).
var _heading: Vector3 = Vector3.BACK


## Its hero's cached follower list is out of date (it joined, left the army or fell).
func _forget_followers() -> void:
	if not is_inside_tree():
		return
	for player in get_tree().get_nodes_in_group(&"players"):
		if (player as Player).peer_id == owner_peer:
			(player as Player).forget_followers()


func _ready() -> void:
	_forget_followers()
	_apply_weapon_stats()
	super()
	chase_avoid_mask = GameConfig.LAYER_ENEMIES  # go around orcs in the way to the one we're after
	add_to_group(&"allies")
	add_to_group(&"player_units")
	_think_timer = randf() * 0.3
	scan_range = aggro_range  # (orders from its first moment, before its first think)
	_base_max_health = max_health * BASE_POWER
	_base_damage = melee_damage * BASE_POWER
	_find_leader()
	refresh_army_bonus()
	_show_banner()


## Hands and stats for `weapon` (before Unit._ready() attaches the hand items).
## Every peer: a squad leader carries a banner on its back in its hero's color.
func _show_banner() -> void:
	if squad_leader and _banner == null and is_inside_tree():
		_banner = Node3D.new()
		_banner.name = "Banner"
		_banner.position = Vector3(0.0, 0.0, -0.22)
		var material := StandardMaterial3D.new()
		material.albedo_color = Net.color_of(owner_peer)
		var pole_material := StandardMaterial3D.new()
		pole_material.albedo_color = Color(0.36, 0.25, 0.15)
		var pole := MeshInstance3D.new()
		var rod := CylinderMesh.new()
		rod.top_radius = 0.025
		rod.bottom_radius = 0.025
		rod.height = 1.5
		rod.material = pole_material
		pole.mesh = rod
		pole.position = Vector3(0.0, 1.0, 0.0)
		_banner.add_child(pole)
		var flag := MeshInstance3D.new()
		var cloth := BoxMesh.new()
		cloth.size = Vector3(0.04, 0.42, 0.6)
		cloth.material = material
		flag.mesh = cloth
		flag.position = Vector3(0.0, 1.52, -0.31)
		_banner.add_child(flag)
		add_child(_banner)
	if _banner:
		_banner.visible = squad_leader


func _apply_weapon_stats() -> void:
	var stats: Dictionary = WEAPON_STATS.get(weapon, {})
	melee_damage = stats.get("damage", melee_damage)
	melee_range = stats.get("range", melee_range)
	melee_cooldown = stats.get("cooldown", melee_cooldown)
	max_health = stats.get("health", max_health)
	match weapon:
		"bow":
			right_hand_item = null
			hold_right_arm = false
			left_hand_item = BOW_SCENE
			left_hand_offset = Vector3(0.27, -0.24, 0.0)
			hold_left_arm = true
		"wizard", "healer":
			# A glowing orb (wizard) or a potion (healer) in the right hand, nothing in the left.
			right_hand_item = ORB_SCENE if weapon == "wizard" else POTION_SCENE
			right_hand_offset = Vector3(-0.27, -0.24, 0.0)
			right_hand_rotation = Vector3.ZERO
			left_hand_item = null


## Bow soldiers.
func is_archer() -> bool:
	return weapon == "bow"


## Bow, wizard and healer: they stand in rows behind the hero and keep away from enemies.
func is_ranged() -> bool:
	return weapon == "bow" or weapon == "wizard" or weapon == "healer"


func is_healer() -> bool:
	return weapon == "healer"


## Fights from range: archers and wizards.
func shoots() -> bool:
	return is_archer() or weapon == "wizard"


## Barracks training (Conquest): the rank `seconds` of drill earn.
static func rank_for_drill(seconds: float) -> int:
	var new_rank := 0
	while new_rank + 1 < DRILL_SECONDS.size() and seconds >= DRILL_SECONDS[new_rank + 1]:
		new_rank += 1
	return new_rank


## Before entering the tree: starts at `value` (as if it had the kills for it).
func start_rank(value: int) -> void:
	rank = clampi(value, 0, RANK_KILLS.size() - 1)
	kills = RANK_KILLS[rank]


func _roll_melee_damage() -> Array:
	return [hit_damage(melee_damage * (BOW_MELEE_SHARE if is_ranged() else 1.0)), false]


func _on_hit_dealt(_victim: Node3D, _amount: float) -> void:
	_fight()


## Server: it attacks — in a battle until BATTLE_END seconds after its last attack.
func _fight() -> void:
	_battle = BATTLE_END


## Server, every frame: a battle that is over has used its weapon once more.
func _wear_weapon(delta: float) -> void:
	if _battle <= 0.0:
		return
	_battle -= delta
	if _battle <= 0.0 and weapon_uses >= 0:
		weapon_uses = mini(weapon_uses + 1, WEAPON_LIFE)


## Damage share of its weapon: whole while new, WEAR_LOSS less every WEAR_STEP battles, nothing once broken
## (`hit_damage` then deals BROKEN_DAMAGE).
func weapon_power() -> float:
	if weapon_uses < 0:
		return 1.0
	if weapon_uses >= WEAPON_LIFE:
		return 0.0
	return 1.0 - WEAR_LOSS * (weapon_uses / WEAR_STEP)


## Its weapon has been through WEAPON_LIFE battles: it is useless until it gets a new one.
func weapon_broken() -> bool:
	return weapon_uses >= WEAPON_LIFE


## Battles its weapon still lasts (WEAPON_LIFE when it never wears).
func weapon_left() -> int:
	return WEAPON_LIFE - clampi(weapon_uses, 0, WEAPON_LIFE)


## What a blow / shot / heal of `base` strength does with the weapon it has: weaker when worn, BROKEN_DAMAGE when
## it is broken.
func hit_damage(base: float) -> float:
	return BROKEN_DAMAGE if weapon_broken() else base * upkeep_damage


## How far archers shoot: half their hero's bow range (wizards a little less).
func archer_range() -> float:
	var bow_range: float = leader.aim_range if is_instance_valid(leader) else 12.0
	return bow_range * ARCHER_RANGE_SHARE * (WIZARD_RANGE_SHARE if weapon == "wizard" else 1.0)


func _find_leader() -> void:
	for player in get_tree().get_nodes_in_group(&"players"):
		if (player as Player).peer_id == owner_peer:
			leader = player
			_order_serial = leader.order_serial  # orders given before we joined are not news
			return


## Applies the player's soldier upgrades (keeps the current health fraction).
func refresh_army_bonus() -> void:
	var valid := is_instance_valid(leader)
	var ratio := health / max_health if max_health > 0.0 else 1.0
	var ranked := 1.0 + RANK_BONUS * rank
	max_health = _base_max_health * (leader.ally_health if valid else 1.0) * ranked
	health = max_health * ratio
	melee_damage = _base_damage * (leader.ally_damage if valid else 1.0) * ranked


## Server (Unit.take_damage): this soldier landed a killing blow. With `progression` on, kills raise its rank.
func credit_kill(_victim: Node3D) -> void:
	if not progression or is_dead or not multiplayer.is_server():
		return
	kills += 1
	_check_rank()


func _check_rank() -> void:
	var new_rank := rank
	while new_rank + 1 < RANK_KILLS.size() and kills >= RANK_KILLS[new_rank + 1]:
		new_rank += 1
	if new_rank != rank:
		rank = new_rank
		refresh_army_bonus()


## Every peer: the rank badge over its head (I..IV), and a golden sparkle on a promotion.
func _show_rank(promoted: bool) -> void:
	if rank > 0 and _rank_label == null:
		_rank_label = Label3D.new()
		_rank_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_rank_label.pixel_size = 0.009
		_rank_label.outline_size = 8
		_rank_label.modulate = RANK_COLOR
		_rank_label.position = Vector3(0.0, health_bar_height + 0.28, 0.0)
		add_child(_rank_label)
	if _rank_label:
		_rank_label.text = RANK_BADGES[clampi(rank, 0, RANK_BADGES.size() - 1)]
		_rank_label.visible = rank > 0
	if promoted and is_inside_tree():
		HitFx.flash(global_position + Vector3(0, 1.0, 0), HitFx.REVIVE_SPARKLE, Color(RANK_COLOR, 0.9), 1.3, 0.5)


## Compact spiral ("sunflower") formation around the player: slot i sits at radius ~sqrt(i),
## so followers stay packed instead of covering the screen.
## Archers stand apart: rows of five behind the hero (behind = against the way it walks).
func _update_slot() -> void:
	var index := leader.follower_index(self) if is_instance_valid(leader) else 0
	if is_ranged():
		var row := index / 5
		var spread := (index % 5 - 2) * 0.42 + (0.21 if row % 2 == 1 else 0.0)
		_slot_offset = (-_heading).rotated(Vector3.UP, spread) * (2.0 + 0.8 * row)
		return
	var angle := index * 2.39996  # golden angle
	var slot_radius := 1.1 + 0.5 * sqrt(index)
	_slot_offset = Vector3(cos(angle), 0.0, sin(angle)) * slot_radius


func _get_move_input(delta: float) -> Vector3:
	_match_pace = -1.0
	var move := _desired_move(delta)
	move.y = 0.0
	var strength := move.length()
	if strength < 0.15:
		return Vector3.ZERO
	if _match_pace > 0.0:
		return move / strength * _match_pace * upkeep_speed  # marching with a moving hero: one steady run
	if not shoots() and not GameConfig.is_gone(target):
		return move / strength * upkeep_speed  # going for an enemy: always the run (no walk / run flicker at its edge)
	return move / strength * (1.0 if strength >= 0.75 else walk_share) * upkeep_speed


## The move this frame (any length up to 1); `_get_move_input` turns it into a run or a walk.
func _desired_move(delta: float) -> Vector3:
	if multiplayer.is_server():
		_wear_weapon(delta)
	look_override = Vector3.ZERO  # archers face their target while shooting / stepping back (`_shoot_at`)
	_regroup = maxf(_regroup - delta, 0.0)
	_think_timer -= delta
	# A new order is obeyed this frame, not at the next think.
	if _think_timer <= 0.0 or (is_instance_valid(leader) and leader.order_serial != _order_serial):
		_think_timer = 0.25 + randf() * 0.1
		_think()
		if brain_cycle < 0:
			_think_timer = NO_ORDERS_WAIT  # just arrived, no orders yet: they come within a brain cycle

	if is_healer() and not GameConfig.is_gone(_patient):
		return _heal_move(delta)
	if breach_point != Vector3.INF:
		return _nav_move(breach_point, delta, 0.5)  # behind a shut gate: to the gate (ConquestDemons hits it)
	if not GameConfig.is_gone(target):
		return _shoot_at(delta) if shoots() else engage(target, delta)
	if mustering and is_instance_valid(leader):
		return _nav_move(leader.global_position, delta, MUSTER_JOIN * 0.5)
	if squad > 0:
		return _nav_move(_squad_spot, delta, 0.6) if _squad_spot != Vector3.INF else settle(delta)
	var order := _order()
	if order == Player.Order.MARCH:
		return _march_move(delta)
	if order == Player.Order.FOLLOW and GameConfig.is_gone(leader):
		return Vector3.ZERO
	var slot := _slot_point()
	if _via != Vector3.INF:
		# Cut off from the slot (a wall, a house): the hero's own way around.
		if _via.distance_to(Vector3(global_position.x, 0.0, global_position.z)) < 0.5:
			_via = _trail_point(slot)
			if _via == Vector3.INF:
				return Vector3.ZERO
		return _walk_to(_via, delta)
	var to_slot := slot - global_position
	to_slot.y = 0.0
	var dist := to_slot.length()
	var leader_speed := _leader_speed() if order == Player.Order.FOLLOW else 0.0
	if leader_speed > 1.0 and dist < walk_distance * 3.0:
		# The hero is on the move and the slot with them: keep pace (their speed, a bit more when behind,
		# never past our own run) instead of flipping between run and walk around the slot's edge.
		_match_pace = clampf((leader_speed + dist * 1.2) / maxf(move_speed, 0.1), walk_share, 1.0)
		return steer(to_slot.normalized(), delta) if dist >= 0.15 else leader.velocity.normalized()
	if dist < 0.4:
		return settle(delta)
	# Run when behind, walk the last bit.
	return steer(to_slot.normalized() * (1.0 if dist > walk_distance else 0.5), delta)


## How fast the hero is moving right now (flat), 0 without one.
func _leader_speed() -> float:
	if GameConfig.is_gone(leader):
		return 0.0
	return Vector2(leader.velocity.x, leader.velocity.z).length()


## Archer: walk up until the target is in range with a clear line of fire (around what blocks it), then
## shoot (leading it a little); an enemy right next to it makes it step back while shooting.
func _shoot_at(delta: float) -> Vector3:
	var to := target.global_position - global_position
	to.y = 0.0
	if to.length() - Unit.target_radius(target) > shoot_range or not _clear_shot_cached(target):
		return steer(to, delta, target, true)
	look_override = to.normalized()
	face(to, delta * 2.0)
	if _melee_timer <= 0.0 and _action_time <= 0.0:
		_melee_timer = melee_cooldown * randf_range(0.9, 1.1)
		if is_archer():
			play_action("holding-left-shoot", 0.3, ARM_LEFT)
		else:
			play_action("holding-right-shoot", 0.4, ARM_RIGHT)
		get_tree().create_timer(0.12).timeout.connect(_release_arrow)
	var away := _keep_away_cached()
	if away != Vector3.ZERO:
		return steer(away, delta)
	return settle(delta)


## `_clear_shot(node)`, looked at again every SHOT_CHECK_FRAMES frames (a ray every frame per archer was a big share of a fight).
func _clear_shot_cached(node: Node3D) -> bool:
	var now := Engine.get_physics_frames()
	if node != _shot_node or now >= _shot_until:
		_shot_node = node
		_shot_until = now + SHOT_CHECK_FRAMES
		_shot_clear = _clear_shot(node)
	return _shot_clear


## `_keep_away()`, looked at again every SHOT_CHECK_FRAMES frames.
func _keep_away_cached() -> Vector3:
	var now := Engine.get_physics_frames()
	if now >= _away_until:
		_away_until = now + SHOT_CHECK_FRAMES
		_away = _keep_away()
	return _away


## Away from the closest enemy within ARCHER_KEEP_AWAY (a little toward the hero), or ZERO. Who that is comes
## from its commander (`brain_near`).
func _keep_away() -> Vector3:
	var near := ordered_foe(brain_near, ARCHER_KEEP_AWAY)
	if near == null:
		return Vector3.ZERO
	var away := global_position - near.global_position
	away.y = 0.0
	if is_instance_valid(leader):
		var home := leader.global_position - global_position
		home.y = 0.0
		if home.length() > 0.5:
			away = away.normalized() + home.normalized() * 0.35
	return away.normalized()


## Nothing (a tree, a wall) between this archer's bow and `node` (arrows would stop on it).
func _clear_shot(node: Node3D) -> bool:
	var from := global_position + Vector3(0, 0.55, 0)
	var to := node.global_position + Vector3(0, 0.55, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to, OBSTACLE_MASK)
	var exclude: Array[RID] = [get_rid()]
	if node is CollisionObject3D:
		exclude.append((node as CollisionObject3D).get_rid())
	query.exclude = exclude
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## A unit-wide path from here to `point` with nothing in the way.
func _clear_walk(point: Vector3) -> bool:
	var motion := point - global_position
	motion.y = 0.0
	if motion.length() < 0.05:
		return true
	if _probe_shape == null:
		_probe_shape = SphereShape3D.new()
		_probe_shape.radius = clampf(radius * 0.6, 0.24, 0.5)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _probe_shape
	query.collision_mask = OBSTACLE_MASK | (collision_mask & GameConfig.ALL_GATES)  # (its own side's gates: open)
	query.transform = Transform3D(Basis(), global_position + Vector3(0, 0.45, 0))
	query.motion = motion
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.cast_motion(query)[0] >= 0.999


## The newest point of the hero's trail we can walk straight to (INF: none, or the slot is in reach anyway).
func _trail_point(slot: Vector3) -> Vector3:
	if not is_instance_valid(leader) or _clear_walk(slot):
		return Vector3.INF
	var points := leader.trail
	for i in range(points.size() - 1, -1, -1):
		if _clear_walk(points[i]):
			return points[i]
	return Vector3.INF


func _release_arrow() -> void:
	if is_dead or GameConfig.is_gone(target):
		return
	var from := global_position + Vector3(0, 0.55, 0)
	var aim := target.global_position
	if target is CharacterBody3D:
		aim += (target as CharacterBody3D).velocity * 0.2
	var direction := aim - from
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return
	direction = direction.normalized()
	face_now(direction)
	if weapon == "wizard":
		_fight()
		NetSpawn.projectile(&"magic_bolt", from + direction * 0.4, direction, hit_damage(melee_damage), self)
		return
	_fight()
	NetSpawn.projectile(&"arrow", from + direction * 0.4, direction, hit_damage(melee_damage), self)


## Healer: walk up to its patient and heal it every cooldown (stepping back from enemies that get close).
func _heal_move(delta: float) -> Vector3:
	var to := _flat(_patient.global_position - global_position)
	if to.length() > HEAL_RANGE:
		return steer(to.normalized(), delta)
	look_override = to.normalized() if to.length() > 0.1 else Vector3.ZERO
	if _melee_timer <= 0.0 and _action_time <= 0.0 and multiplayer.is_server():
		_melee_timer = melee_cooldown * randf_range(0.9, 1.1)
		play_action("holding-right-shoot", 0.4, ARM_RIGHT)
		var amount := roundf(hit_damage(float(WEAPON_STATS.healer.heal) * (1.0 + RANK_BONUS * rank)))
		_patient.heal(amount)
		_net_heal_fx.rpc(_patient.get_path())
		_heals += 1
		if progression and _heals % HEALS_PER_KILL == 0:
			kills += 1
			_check_rank()
	var away := _keep_away_cached()
	return steer(away, delta) if away != Vector3.ZERO else settle(delta)


@rpc("authority", "call_local", "unreliable")
func _net_heal_fx(path: NodePath) -> void:
	var patient := get_node_or_null(path) as Node3D
	if patient and is_inside_tree():
		HitFx.flash(patient.global_position + Vector3(0, 0.9, 0), HitFx.REVIVE_SPARKLE, Color(HEAL_COLOR, 0.9), 1.0, 0.4)


## Healer (server, every think): the most wounded friend within HEAL_SIGHT (its hero first), or null — picked by
## its commander (`brain_patient`, BrainJob._soldier); the healer only checks they are still there.
func _find_patient() -> Unit:
	var unit := instance_from_id(brain_patient) as Unit if brain_patient != 0 else null
	if unit == null or GameConfig.is_gone(unit) or unit.team_id != team_id \
			or flat_distance_to(unit) > HEAL_SIGHT + ORDER_SLACK:
		return null
	return unit


func _walk_to(point: Vector3, delta: float) -> Vector3:
	var to := point - global_position
	to.y = 0.0
	return steer(to.normalized(), delta) if to.length() > 0.05 else Vector3.ZERO


func _think() -> void:
	if not is_instance_valid(leader):
		_find_leader()
	if squad > 0 and is_instance_valid(leader):
		_order_serial = leader.order_serial  # a squad takes its orders from the map, not the hero's army orders
	if is_instance_valid(leader) and leader.order_serial != _order_serial:
		_obey()
	shoot_range = archer_range()
	if is_instance_valid(leader):
		var walking := leader.velocity
		walking.y = 0.0
		if walking.length() > 0.8:
			_heading = _heading.slerp(walking.normalized(), 0.5).normalized()
	_via = Vector3.INF
	_think_orders()
	if breach_point != Vector3.INF and _nav:
		_nav.target_position = breach_point
	if is_healer():
		target = null  # healers never fight: they follow the orders and heal (`_heal_move`)
		_patient = _find_patient()


func _think_orders() -> void:
	if mustering:
		_think_muster()
		return
	if squad > 0:
		_think_squad()
		return
	var order := _order()
	if order == Player.Order.KILL:
		_think_kill()
		return
	if order == Player.Order.MARCH:
		_think_march()
		return
	if _regroup > 0.0:
		# Carrying out an order: go to the new spot, ignore fights on the way.
		_update_slot()
		target = null
		if not GameConfig.is_gone(leader) and _slot_point().distance_to(global_position) < regroup_arrive:
			_regroup = 0.0
		return
	if order != Player.Order.FOLLOW:
		_think_order(order)
		return
	var sight := _sight()
	if GameConfig.is_gone(leader):
		target = _commit_target(target if is_instance_valid(target) and target is Unit else null,
				_best_enemy(global_position, sight), sight + 2.5)
		return
	_update_slot()
	if global_position.distance_to(leader.global_position) > leash_range:
		target = null
		_via = _trail_point(_slot_point())
		return
	var unit_target := target if is_instance_valid(target) and target is Unit else null
	# Archers stand behind the hero: they look out from the hero, as far as they shoot and a bit more.
	var candidate := _best_enemy(leader.global_position, shoot_range + 3.0) if shoots() \
			else _best_enemy(global_position, sight)
	target = _commit_target(unit_target, candidate, sight + 2.5)
	if target == null:
		_via = _trail_point(_slot_point())


## Squad (server, every think): the leader heads for the squad's goal, the rest follow the leader (a ring around
## it) and, once it is there, stand on a ring around the goal; on the way they fight what comes within aggro_range,
## there what comes within ConquestSquads.GUARD of the goal.
func _think_squad() -> void:
	var squads := get_tree().get_first_node_in_group(&"conquest_squads") as ConquestSquads
	var goal := squads.goal(squad) if squads else Vector3.INF
	if goal == Vector3.INF:
		squad = 0  # its squad is gone: back to its hero
		squad_leader = false
		mustering = true
		return
	_regroup = 0.0
	_ensure_nav()
	var mates := squads.members(squad)
	var head: Ally = mates[0] if not mates.is_empty() and mates[0].squad_leader else null
	var there := _flat(goal - global_position).length() < ConquestSquads.GUARD
	if squad_leader or head == null:
		_squad_spot = goal
	else:
		var index := maxi(mates.find(self) - 1, 0)
		var count := maxi(mates.size() - 1, 1)
		var ring := Vector3(cos(TAU * index / count), 0.0, sin(TAU * index / count)) * (2.6 if is_ranged() else 1.7)
		var head_there := _flat(goal - head.global_position).length() < ConquestSquads.ARRIVE * 2.0
		_squad_spot = (goal if head_there else head.global_position) + ring
	_nav.target_position = _squad_spot
	var guard := ConquestSquads.GUARD if there else aggro_range
	var reach := guard + (shoot_range if shoots() else 0.0)
	var candidate := _best_enemy(goal if there else global_position, reach)
	target = _commit_target(target if is_instance_valid(target) and target is Unit else null, candidate, reach + 4.0)
	if target and _flat(target.global_position - (goal if there else global_position)).length() > reach + 6.0:
		target = null  # don't get dragged away


## Server (ConquestSquads.command): a new squad order: drop the fight and go.
func squad_ordered() -> void:
	target = null
	_target_lock = 0.0
	_think_timer = 0.0


## Soldiers standing still with nothing to fight or heal (an army waiting around its hero) think every other frame
## (nobody sees a standing soldier step); so does every soldier not using an action in a huge fight
## (GameConfig.overloaded) until it calms down.
func _physics_step_frames() -> int:
	if _action_time > 0.0:
		return 1
	if GameConfig.overloaded:
		return 2
	var idle := GameConfig.is_gone(target) and GameConfig.is_gone(_patient) and not mustering 			and velocity.length_squared() < 0.01
	return 2 if idle else 1


## Conquest: where it wants to be — its target, its squad's spot or its hero's ordered point (INF = with the hero).
func wanted_point() -> Vector3:
	if is_healer() or mustering:
		return Vector3.INF
	if not GameConfig.is_gone(target):
		return target.global_position
	if squad > 0:
		return _squad_spot
	if is_instance_valid(leader) and _order() != Player.Order.FOLLOW:
		return leader.army_point
	return Vector3.INF


## Server (ConquestDemons): go hit the gate at `point` (INF: done, back to the orders).
func set_breach(point: Vector3) -> void:
	if point == breach_point:
		return
	breach_point = point
	if point != Vector3.INF:
		_ensure_nav()
		_nav.target_position = point


## The leader's army order (FOLLOW without a leader).
func _order() -> int:
	return leader.army_order if is_instance_valid(leader) else Player.Order.FOLLOW


## How far a soldier looks for enemies: archers a little past their shooting range.
func _sight() -> float:
	return maxf(aggro_range, shoot_range + 1.5) if is_ranged() else aggro_range


## Melee soldiers finish the enemy they're after: no switching to a closer one that got in the way (they
## steer around those, `chase_avoid_mask`), only to one that is hitting the hero or a squadmate while ours
## isn't. A new target once it's dead or out of `keep_range`. Archers pick again every think (`_best_enemy`
## keeps the current one a little ahead).
func _commit_target(current: Node3D, candidate: Node3D, keep_range: float) -> Node3D:
	if GameConfig.is_gone(current) or flat_distance_to(current) > keep_range or is_ranged():
		return candidate
	if candidate and candidate != current and _defending(candidate) and not _defending(current):
		return candidate
	return current


## `enemy` is attacking our hero or one of our squad.
func _defending(enemy: Node3D) -> bool:
	var victim: Variant = enemy.get("target")
	if not victim is Node3D or not is_instance_valid(victim):
		return false
	return victim == leader or (victim is Ally and (victim as Ally).owner_peer == owner_peer)


## Who to fight within `max_range` of `origin` (else within `own_range` of itself): it tells its commander what it
## needs (`scan_*`, for the next cycle) and takes the commander's pick (`brain_best`) if that still fits — alive,
## hostile, in reach. The teamwork is in the pick (BrainJob._pick): the closest, but enemies hitting the hero count
## as DEFEND_BONUS m closer (hitting a soldier of the army: GUARD_BONUS); melee soldiers add CROWD_PENALTY per
## comrade already on it (they spread over the enemies); shooters prefer the wounded. A shooter looks along its
## line of fire itself: blocked, and the commander's second choice is clear → that one.
func _best_enemy(origin: Vector3, max_range: float, own_range: float = 0.0) -> Node3D:
	var own := origin.distance_squared_to(global_position) < 0.01
	scan_origin = Vector3.INF if own else origin
	scan_range = max_range
	scan_own = own_range
	var pick := _ordered_pick(brain_best, origin, max_range, own_range)
	if pick and brain_alt != 0 and shoots() and not _clear_shot(pick):
		var other := _ordered_pick(brain_alt, origin, max_range, own_range)
		if other and _clear_shot(other):
			return other
	return pick


func _ordered_pick(id: int, origin: Vector3, max_range: float, own_range: float) -> Node3D:
	var pick := ordered_foe(id, max_range + ORDER_SLACK, origin)
	if pick == null and own_range > 0.0:
		pick = ordered_foe(id, own_range + ORDER_SLACK)
	return pick


## A new order: drop the current fight and go (KILL: straight for the target).
func _obey() -> void:
	_order_serial = leader.order_serial
	target = null
	_target_lock = 0.0
	_regroup = 0.0 if leader.army_order == Player.Order.KILL or leader.army_order == Player.Order.MARCH else regroup_time
	_patrol_angle = randf() * TAU  # MARCH: each soldier its own spot on the ring


## Where this soldier stands in the formation: around the player (FOLLOW) or the ordered point.
func _slot_point() -> Vector3:
	var anchor := leader.global_position if _order() == Player.Order.FOLLOW else leader.army_point
	return anchor + _slot_offset


## MARCH: the path to this soldier's spot on the patrol ring (the ring turns once they are there), and who to
## fight: near itself on the way, anything near the territory once arrived.
func _think_march() -> void:
	_regroup = 0.0  # a long walk: no "ignore every fight" window, aggro_range keeps them on the road
	_ensure_nav()
	var point := leader.army_point
	var arrived := _flat(point - global_position).length() < MARCH_ARRIVE
	if arrived:
		_patrol_angle += PATROL_TURN * 0.3
	_slot_offset = Vector3(cos(_patrol_angle), 0.0, sin(_patrol_angle)) * PATROL_RADIUS
	_nav.target_position = point + _slot_offset
	var guard := MARCH_GUARD if arrived else aggro_range
	var candidate := _best_enemy(point if arrived else global_position, guard)
	target = _commit_target(target if is_instance_valid(target) and target is Unit else null, candidate, guard + 4.0)
	if target and not arrived and _flat(target.global_position - global_position).length() > guard + 4.0:
		target = null  # keep marching


## MARCH: along the navigation path to the patrol spot (straight at it while there is no path: no navigation
## mesh, or it is still baking).
func _march_move(delta: float) -> Vector3:
	return _nav_move(leader.army_point + _slot_offset, delta, 0.6)


## A NavigationAgent3D, made the first time a soldier walks somewhere far on its own (march, muster).
func _ensure_nav() -> void:
	if _nav:
		return
	_nav = NavigationAgent3D.new()
	_nav.radius = radius
	_nav.path_desired_distance = 1.0
	_nav.target_desired_distance = 0.8
	add_child(_nav)


## Mustered: on its way to the General; joins the formation once close (then obeys orders like the rest).
func _think_muster() -> void:
	if GameConfig.is_gone(leader):
		mustering = false
		return
	if _flat(leader.global_position - global_position).length() < MUSTER_JOIN:
		mustering = false
		_order_serial = leader.order_serial
		return
	_ensure_nav()
	_nav.target_position = leader.global_position
	var candidate := _best_enemy(global_position, aggro_range)
	target = _commit_target(target if is_instance_valid(target) and target is Unit else null, candidate, aggro_range + 4.0)


## Toward `goal` along the navigation path (straight at it while there is no path: no navigation mesh, or it is
## still baking); stands still within `arrive`.
func _nav_move(goal: Vector3, delta: float, arrive: float) -> Vector3:
	var to_goal := _flat(goal - global_position)
	if to_goal.length() < arrive:
		return settle(delta)
	var step := to_goal
	if _nav:
		var next := _flat(_nav.get_next_path_position() - global_position)
		if next.length() > 0.05:
			step = next
	return steer(step.normalized() * (1.0 if to_goal.length() > walk_distance else 0.5), delta)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## KILL: everyone on the ordered target, no leash, no switching (the player turns the order into a
## CHARGE once it is dead).
func _think_kill() -> void:
	_update_slot()
	if GameConfig.is_gone(leader.army_target):
		_think_order(Player.Order.CHARGE)
		return
	target = leader.army_target


## CHARGE / HOLD: fight what comes near the point (charging soldiers also fight on the way there).
func _think_order(order: int) -> void:
	_update_slot()
	var point := leader.army_point
	var guard := charge_radius if order == Player.Order.CHARGE else hold_radius
	# (charging soldiers also fight what is near them on the way there)
	var candidate := _best_enemy(point, guard, _sight() if order == Player.Order.CHARGE else 0.0)
	target = _commit_target(target if is_instance_valid(target) and target is Unit else null, candidate, guard + 6.0)
	if target and target.global_position.distance_to(point) > guard + 6.0:
		target = null  # don't get dragged away from the point


func _on_died() -> void:
	_forget_followers()
	remove_from_group(&"allies")
	remove_from_group(&"player_units")
