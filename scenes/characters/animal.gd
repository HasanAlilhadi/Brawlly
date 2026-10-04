class_name Animal
extends Unit
## Wildlife (Kenney Cube Pets, `assets/characters/pets/`), on its own team (`GameConfig.ANIMAL_TEAM`): heroes and
## soldiers can hit it, orcs never do (and it never fights them). Animals graze in groups around their herd's
## home (`AnimalHerd`): walk to a spot, eat a while, walk on.
## - Shy ones (pig, cow, deer, fox) run away from heroes / soldiers that come close or hit them, and the whole
##   group bolts with them (`alarm`).
## - The wild pig (hog) charges like a bull: anyone close or anyone who hits it gets a lowered head, a short wind-up
##   and a straight dash that rams the first one in its way (`CHARGE_*`), again and again until it calms down.
##   While angry it counts as an enemy (group `active_enemies`), so soldiers fight it too.
## Every animal drops COINS_MIN..COINS_MAX coins when it dies, and a health potion HEALTH_DROP_CHANCE of the time.
## Species are rows in SPECIES; `set_species()` (every peer, before entering the tree) swaps the model.

enum Temper { SHY, WILD }

const TARGET_GROUPS: Array[StringName] = [&"player_units"]
## id -> model, temper, health, speeds (walk = grazing, run = fleeing / charging), size (model scale; the
## pets' feet are 0.3 model units below their origin), radius, and for the wild one its charge damage.
const SPECIES: Dictionary = {
	"pig": {"model": preload("res://assets/characters/pets/pig.glb"), "temper": Temper.SHY, "health": 60.0,
			"walk": 1.3, "run": 4.3, "scale": 0.38, "radius": 0.3},
	"cow": {"model": preload("res://assets/characters/pets/cow.glb"), "temper": Temper.SHY, "health": 110.0,
			"walk": 1.0, "run": 3.5, "scale": 0.46, "radius": 0.36},
	"deer": {"model": preload("res://assets/characters/pets/deer.glb"), "temper": Temper.SHY, "health": 55.0,
			"walk": 1.4, "run": 5.2, "scale": 0.4, "radius": 0.32},
	"fox": {"model": preload("res://assets/characters/pets/fox.glb"), "temper": Temper.SHY, "health": 45.0,
			"walk": 1.5, "run": 5.4, "scale": 0.34, "radius": 0.26},
	"hog": {"model": preload("res://assets/characters/pets/hog.glb"), "temper": Temper.WILD, "health": 150.0,
			"walk": 1.2, "run": 2.6, "scale": 0.42, "radius": 0.33, "damage": 18.0},
}
const COINS_MIN: int = 3
const COINS_MAX: int = 8
const HEALTH_DROP_CHANCE: float = 0.2
const HEALTH_DROP: int = 30
## Grazing: at most this far from the herd's home; eats this long between walks.
const GRAZE_RADIUS: float = 5.0
const EAT_TIME := Vector2(2.0, 6.0)
## Shy animals: run when a hero / soldier comes this close (or hits them) and keep running this long after.
const FLEE_RANGE: float = 5.0
const FLEE_TIME: float = 3.5
## Herd mates this close take fright together.
const ALARM_RANGE: float = 9.0
## Wild pig: gets angry at anyone this close; wind-up, then a dash of CHARGE_SPEED for at most CHARGE_TIME
## (CHARGE_REACH in front of it hits; knockback CHARGE_SHOVE), rests CHARGE_REST, and calms down CALM_TIME after
## its target got away (beyond CALM_RANGE) or nobody hit it.
const AGGRO_RANGE: float = 4.0
const WIND_UP: float = 0.6
const CHARGE_SPEED: float = 7.5
const CHARGE_TIME: float = 1.0
const CHARGE_REACH: float = 0.55
const CHARGE_SHOVE: float = 2.6
const CHARGE_REST: float = 1.1
const CALM_TIME: float = 6.0
const CALM_RANGE: float = 14.0
## Nobody within this distance: the animal stands still and thinks rarely (saves the server work).
const SLEEP_RANGE: float = 45.0

## Set before entering the tree (spawn data, every peer).
var species: String = "pig"
## The herd's home (server; from the spawn data).
var home: Vector3

var _temper: Temper = Temper.SHY
var _walk_speed: float = 1.3
var _run_speed: float = 4.0
var _charge_damage: float = 0.0
var _think_timer: float = 0.0
var _graze_point: Vector3 = Vector3.INF
var _eating: float = 0.0
var _flee_left: float = 0.0
var _threat: Node3D
# Wild pig: who it is after (`target`, read by soldiers deciding whom to defend).
var target: Node3D
var _calm_left: float = 0.0
var _wind_up_left: float = 0.0
var _charge_left: float = 0.0
var _charge_dir: Vector3 = Vector3.ZERO
var _rest_left: float = 0.0
var _charge_hit: Dictionary = {}
var _asleep: bool = false


## Every peer, before entering the tree: this species' model, size and stats.
func set_species(id: String) -> void:
	species = id if SPECIES.has(id) else "pig"
	var row: Dictionary = SPECIES[species]
	var old := get_node_or_null("Model")
	if old:
		remove_child(old)
		old.free()
	# The pet goes in a scaled holder: some clips key the pet's own root scale, which would undo a size set on it.
	var body := Node3D.new()
	body.name = "Model"
	body.scale = Vector3.ONE * float(row.scale)
	body.position.y = 0.3 * float(row.scale)
	body.add_child((row.model as PackedScene).instantiate())
	add_child(body)
	max_health = row.health
	health = max_health  # now, not in Unit._ready(): dropping from the default 100 there would read as a hit
	radius = row.radius
	_walk_speed = row.walk
	_run_speed = row.run
	move_speed = _walk_speed
	_temper = row.temper
	_charge_damage = row.get("damage", 0.0)
	health_bar_height = float(row.scale) * 2.1
	var shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape and shape.shape is CapsuleShape3D:
		var capsule := (shape.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
		capsule.radius = radius
		capsule.height = maxf(radius * 2.0 + 0.1, float(row.scale) * 1.6)
		shape.shape = capsule
		shape.position.y = capsule.height * 0.5


func _ready() -> void:
	if model.get_child_count() == 0:  # instanced without set_species(): the default species
		set_species(species)
		model = $Model
		anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	team_id = GameConfig.ANIMAL_TEAM
	knockback_power = CHARGE_SHOVE
	super()
	add_to_group(&"animals")
	for clip in ["run", "eat"]:
		if anim and anim.has_animation(clip):
			anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	if home == Vector3.ZERO:
		home = global_position
	_think_timer = randf() * 0.5
	_eating = randf_range(0.0, EAT_TIME.y)


func is_wild() -> bool:
	return _temper == Temper.WILD


func is_angry() -> bool:
	return is_instance_valid(target)


func _move_anim(strength: float) -> String:
	return "run" if strength > 0.75 or move_speed > _walk_speed + 0.5 else "walk"


func _idle_anim() -> String:
	return "eat" if _eating > 0.0 else "idle"


## Pets have no attack / death clips: missing ones are skipped (the animal keeps its current clip).
func _play_action_local(anim_name: String, duration: float, release_arms: int) -> void:
	if anim and anim.has_animation(anim_name):
		super(anim_name, duration, release_arms)
	else:
		_action_time = duration
		_full_body_action = false


func _get_move_input(delta: float) -> Vector3:
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = 1.0 if _asleep else 0.25 + randf() * 0.1
		_think()
	if _asleep:
		return Vector3.ZERO
	if is_wild() and is_angry():
		return _wild_move(delta)
	if _flee_left > 0.0:
		_flee_left -= delta
		if is_instance_valid(_threat):
			move_speed = _run_speed
			_eating = 0.0
			return steer(_away_from(_threat.global_position), delta)
	move_speed = _walk_speed
	return _graze(delta)


func _think() -> void:
	_asleep = find_nearest([&"players"], SLEEP_RANGE) == null
	if _asleep:
		_calm_down()
		return
	var near := find_nearest(TARGET_GROUPS, AGGRO_RANGE if is_wild() else FLEE_RANGE)
	if is_wild():
		if is_angry():
			if GameConfig.is_gone(target) or flat_distance_to(target) > CALM_RANGE:
				_calm_left -= 0.3
				if _calm_left <= 0.0:
					_calm_down()
			else:
				_calm_left = CALM_TIME
		elif near:
			_get_angry(near)
	elif near:
		_scare(near, true)


## Walk to a spot near home, eat a while, walk to another one.
func _graze(delta: float) -> Vector3:
	if _eating > 0.0:
		_eating -= delta
		return Vector3.ZERO
	if _graze_point == Vector3.INF or global_position.distance_to(home) > GRAZE_RADIUS * 1.6:
		_graze_point = _pick_graze_point()
	var to := _graze_point - global_position
	to.y = 0.0
	if to.length() < 0.35:
		_graze_point = Vector3.INF
		_eating = randf_range(EAT_TIME.x, EAT_TIME.y)
		return Vector3.ZERO
	return steer(to.normalized() * 0.6, delta)


func _pick_graze_point() -> Vector3:
	var angle := randf() * TAU
	var distance := sqrt(randf()) * GRAZE_RADIUS
	return GameConfig.clamp_to_world(home + Vector3(cos(angle), 0.0, sin(angle)) * distance)


## Away from `from`, bending along the world edge instead of running into it.
func _away_from(from: Vector3) -> Vector3:
	var away := global_position - from
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 0.001 else Vector3.FORWARD
	var ahead := global_position + away * 5.0
	var edge := GameConfig.world_half - 4.0
	if absf(ahead.x) > edge:
		away.x *= -0.3
		away.z += signf(away.z if away.z != 0.0 else 1.0)
	if absf(ahead.z) > edge:
		away.z *= -0.3
		away.x += signf(away.x if away.x != 0.0 else 1.0)
	return away.normalized()


## Shy: run from `threat` (and tell the herd when `spread`).
func _scare(threat: Node3D, spread: bool) -> void:
	if is_wild() or is_dead:
		return
	_threat = threat
	_flee_left = FLEE_TIME
	_eating = 0.0
	_graze_point = Vector3.INF
	if spread:
		for node in get_tree().get_nodes_in_group(&"animals"):
			var mate := node as Animal
			if mate != self and not mate.is_dead and mate.home.distance_to(home) < 1.0 \
					and mate.global_position.distance_to(global_position) < ALARM_RANGE:
				mate.alarm(threat)


## A herd mate saw `threat`: shy ones run too, the wild pig turns on it.
func alarm(threat: Node3D) -> void:
	if is_wild():
		if not is_angry():
			_get_angry(threat)
	elif _flee_left <= 0.5:
		_scare(threat, false)


func _on_damaged(attacker: Node3D) -> void:
	if not multiplayer.is_server() or is_dead or attacker == null or not GameConfig.is_hostile(self, attacker):
		return
	var culprit := attacker
	if not culprit is Unit:
		var shooter: Variant = attacker.get("_shooter")
		if shooter is Node3D and is_instance_valid(shooter):
			culprit = shooter
	_asleep = false
	if is_wild():
		if not is_angry() or (culprit is Player and not target is Player):
			_get_angry(culprit)
		_calm_left = CALM_TIME
		_rest_left = minf(_rest_left, 0.3)  # a hit makes it charge sooner
	else:
		_scare(culprit, true)


# --- Wild pig -------------------------------------------------------------------

func _get_angry(at: Node3D) -> void:
	if GameConfig.is_gone(at):
		return
	target = at
	_calm_left = CALM_TIME
	_eating = 0.0
	add_to_group(&"active_enemies")
	if _charge_left <= 0.0 and _wind_up_left <= 0.0:
		_wind_up_left = WIND_UP
		play_action("gesture-negative", WIND_UP, ARM_BOTH)


func _calm_down() -> void:
	target = null
	_wind_up_left = 0.0
	_charge_left = 0.0
	remove_from_group(&"active_enemies")


## Wind up (face the target), charge in a straight line, rest; again while angry.
func _wild_move(delta: float) -> Vector3:
	if GameConfig.is_gone(target):
		_calm_down()
		return Vector3.ZERO
	var to := target.global_position - global_position
	to.y = 0.0
	if _charge_left > 0.0:
		_charge_left -= delta
		move_speed = CHARGE_SPEED
		_charge_hits()
		if _charge_left <= 0.0:
			_rest_left = CHARGE_REST
		return _charge_dir
	if _wind_up_left > 0.0:
		_wind_up_left -= delta
		face(to, delta * 4.0)
		if _wind_up_left <= 0.0:
			_charge_dir = to.normalized() if to.length_squared() > 0.001 else facing()
			face_now(_charge_dir)
			_charge_left = CHARGE_TIME
			_charge_hit.clear()
		return Vector3.ZERO
	if _rest_left > 0.0:
		_rest_left -= delta
		face(to, delta * 2.0)
		move_speed = _walk_speed
		return Vector3.ZERO
	# Close in a little at a trot until in charging distance, then wind up again.
	if to.length() > CHARGE_SPEED * CHARGE_TIME * 0.8:
		move_speed = _run_speed
		return steer(to.normalized(), delta, target, true)
	_wind_up_left = WIND_UP
	play_action("gesture-negative", WIND_UP, ARM_BOTH)
	return Vector3.ZERO


## Server, while charging: the first hostile hero / soldier (or anything breakable) in front takes the ram once
## per charge, which then ends; a wall ends it too.
func _charge_hits() -> void:
	var sphere := SphereShape3D.new()
	sphere.radius = CHARGE_REACH
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis(), global_position + _charge_dir * (radius + 0.2) + Vector3(0, 0.45, 0))
	query.collision_mask = GameConfig.LAYER_PLAYER | GameConfig.LAYER_ALLIES | GameConfig.LAYER_WORLD
	query.exclude = [get_rid()]
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 8):
		var collider := hit.collider as Node3D
		if collider == null:
			continue
		if collider is Unit and GameConfig.is_hostile(self, collider) and not (collider as Unit).is_dead:
			if not _charge_hit.has(collider.get_instance_id()):
				_charge_hit[collider.get_instance_id()] = true
				collider.take_damage(_charge_damage, self, true, false)
				(collider as Unit).shove(_charge_dir * CHARGE_SHOVE * 3.0)  # bowled over, even heroes
				HitFx.flash(collider.global_position + Vector3(0, 0.5, 0), HitFx.HIT_SPARK, Color(1.0, 0.7, 0.4), 1.2, 0.2)
				_end_charge()
				return
		elif not collider is Unit:
			_end_charge()  # rammed a tree / a wall
			return


func _end_charge() -> void:
	_charge_left = 0.0
	_rest_left = CHARGE_REST


# --- Death --------------------------------------------------------------------

func _death_visuals() -> void:
	collision_layer = 0
	collision_mask = 0
	_health_bar.hide()
	if anim:
		anim.pause()
	var tween := create_tween()
	tween.tween_property(model, "rotation:z", PI * 0.5, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	HitFx.flash(global_position + Vector3(0, 0.4, 0), HitFx.DEATH_SMOKE, Color(0.85, 0.85, 0.8, 0.8), 1.2, 0.6,
			Vector2(0.5, 1.3), false)


func _on_died() -> void:
	remove_from_group(&"animals")
	remove_from_group(&"active_enemies")
	if not multiplayer.is_server():
		return
	var coins := randi_range(COINS_MIN, COINS_MAX)
	var first := coins / 2
	Pickup.drop(get_parent(), global_position, Pickup.Kind.COIN, first)
	Pickup.drop(get_parent(), global_position, Pickup.Kind.COIN, coins - first)
	if randf() < HEALTH_DROP_CHANCE:
		Pickup.drop(get_parent(), global_position, Pickup.Kind.HEALTH, HEALTH_DROP)
