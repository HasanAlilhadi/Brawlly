extends Node
## Spearman Bull Rush: three-second shield charge, heavy WASD steering, correct spear grip and one hit per target.
##   "$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- \
##       --test=res://tests/bull_rush_test.gd --class=spearman

const TARGET_SCENE := preload("res://scenes/training/training_target.tscn")
const ORC_SCENE := "res://scenes/characters/enemies/orc_grunt.tscn"

var t := 0.0
var step := 0
var failures := 0
var player: Player
var training_world: Node3D
var lane_targets: Array[TrainingTarget] = []
var side_target: TrainingTarget
var front_attacker: Node3D
var lane_orcs: Array[Enemy] = []
var normal_collision_mask := 0


func _ready() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _check(ok: bool, what: String) -> void:
	printerr(("PASS " if ok else "FAIL ") + what)
	if not ok:
		failures += 1


func _target(world: Node3D, at: Vector3, title: String) -> TrainingTarget:
	var target := TARGET_SCENE.instantiate() as TrainingTarget
	target.title = title
	world.add_child(target)
	target.global_position = at
	return target


## The hand may slide along the shaft during a thrust, but it must stay over the visible shaft.
func _spear_is_in_hand() -> bool:
	var spear := player._weapon_items.get("spear") as Node3D
	if spear == null:
		return false
	var fist_in_spear := spear.transform.affine_inverse() * player._right_fist_position()
	return Vector2(fist_in_spear.x, fist_in_spear.z).length() < 0.001 \
			and fist_in_spear.y >= Player.SPEAR_MIN_SHAFT_BEHIND_HAND \
			and fist_in_spear.y <= 0.58


func _process(delta: float) -> void:
	t += delta
	if get_tree().current_scene == null:
		return
	match step:
		0:
			if t < 1.0:
				return
			var button := get_tree().current_scene.find_child("TrainingButton", true, false) as Button
			if button:
				button.pressed.emit()
			step = 1
			t = 0.0
		1:
			if t < 2.5 or get_tree().current_scene.name != "Main":
				return
			var main := get_tree().current_scene
			player = main.get("local_player") as Player
			training_world = main.get("world") as Node3D
			_check(player != null and player.class_def.id == &"spearman", "training starts as Spearman")
			_check(player.has_ability() and player.class_def.ability == &"bull_rush"
					and is_equal_approx(player.class_def.ability_duration, 3.0), "Spearman has a three-second Bull Rush")
			player.global_position = Vector3(-8.0, 0.0, 10.0)
			player.net_position = player.global_position
			player.face_now(Vector3.RIGHT)
			player.crit_chance = 0.0
			player.attack_melee_toward(Vector3.RIGHT)
			step = 11
			t = 0.0
		11:
			if t < 0.22:
				return
			_check(_spear_is_in_hand(), "normal spear thrust stays on the visible shaft in the hand")
			step = 12
			t = 0.0
		12:
			if t < 0.45:
				return
			player.global_position = Vector3(-8.0, 0.0, 10.0)
			player.net_position = player.global_position
			player.face_now(Vector3.RIGHT)
			for x in [-5.0, -2.0, 1.0]:
				lane_targets.append(_target(training_world, Vector3(x, 0.0, 10.0), "Lane Target"))
			side_target = _target(training_world, Vector3(-2.0, 0.0, 12.0), "Side Target")
			var walk_speed := player.running_speed()
			player.request_ability()
			_check(player.ability_active and player.current_weapon() == "spear", "Bull Rush starts with the spear ready")
			_check(is_equal_approx(player.move_speed, walk_speed * Player.BULL_RUSH_SPEED), "Bull Rush uses charge speed")
			_check(_spear_is_in_hand(), "Bull Rush spear stays on the visible shaft in the hand")
			front_attacker = Node3D.new()
			training_world.add_child(front_attacker)
			front_attacker.global_position = player.global_position + Vector3.RIGHT
			var health_before := player.health
			var shield_before := player.shield_health
			player.take_damage(20.0, front_attacker)
			_check(player._shield_is_guarding() and is_equal_approx(player.health, health_before)
					and is_equal_approx(player.shield_health, shield_before - 20.0),
					"Bull Rush automatically blocks front damage with the shield")
			# Steering can change the charge heading before the model finishes turning.
			player.face_now(Vector3.LEFT)
			front_attacker.global_position = player.global_position + Vector3.RIGHT
			health_before = player.health
			shield_before = player.shield_health
			player.take_damage(10.0, front_attacker)
			_check(is_equal_approx(player.health, health_before)
					and is_equal_approx(player.shield_health, shield_before - 10.0),
					"Bull Rush guards its travel direction even while the body turns")
			front_attacker.global_position = player.global_position + Vector3.FORWARD
			health_before = player.health
			shield_before = player.shield_health
			player.take_damage(10.0, front_attacker)
			_check(is_equal_approx(player.health, health_before - 10.0)
					and is_equal_approx(player.shield_health, shield_before),
					"side hits damage the Spearman without using shield durability")
			front_attacker.global_position = player.global_position + Vector3.LEFT
			health_before = player.health
			shield_before = player.shield_health
			player.take_damage(10.0, front_attacker)
			_check(is_equal_approx(player.health, health_before - 10.0)
					and is_equal_approx(player.shield_health, shield_before),
					"back hits damage the Spearman during Bull Rush")
			player.face_now(Vector3.RIGHT)
			player.joystick_vector = Vector2.UP
			var steered := player._get_move_input(0.25)
			_check(steered.angle_to(Vector3.RIGHT) > 0.1 and steered.angle_to(Vector3.FORWARD) > 0.1,
					"WASD turns Bull Rush gradually instead of snapping")
			player._bull_rush_direction = Vector3.RIGHT
			player.face_now(Vector3.RIGHT)
			player.joystick_vector = Vector2.ZERO
			step = 2
			t = 0.0
		2:
			if t < 2.0:
				return
			var expected := player.spear_damage * Player.BULL_RUSH_DAMAGE
			_check(player.ability_active and player.global_position.x > 0.0, "Bull Rush forces the Spearman forward")
			var shield_center := player._left_item.global_transform * player.class_def.shield_center
			var forearm := (player._left_item.get_parent() as Node3D).global_transform \
					* (Player.SHIELD_CARRY + player.class_def.hand_offset)
			var shield_in_model := player.model.global_transform.affine_inverse() * player._left_item.global_transform
			_check(shield_center.distance_to(forearm) < 0.2
					and shield_in_model.basis.orthonormalized().z.z > 0.9,
					"Bull Rush shield stays attached to the forearm and faces forward")
			_check(lane_targets.all(func(target: TrainingTarget) -> bool:
				return is_equal_approx(target.total_damage(), expected)), "every target in the lane is damaged once")
			_check(lane_targets.all(func(target: TrainingTarget) -> bool:
				return player.get_collision_exceptions().has(target)), "Bull Rush passes through enemy bodies")
			_check(is_zero_approx(side_target.total_damage()), "targets outside the charge lane are not damaged")
			step = 3
			t = 0.0
		3:
			if t < 1.25:
				return
			_check(not player.ability_active, "Bull Rush stops after three seconds")
			_check(player._bull_rush_direction == Vector3.ZERO and player._get_move_input(0.0) == Vector3.ZERO,
					"forced movement is cleared when Bull Rush ends")
			_check(lane_targets.all(func(target: TrainingTarget) -> bool:
				return not player.get_collision_exceptions().has(target)), "charge collision exceptions are removed")
			_check(is_equal_approx(player.move_speed, player.running_speed()), "normal movement speed returns")
			player.global_position = Vector3(-8.0, 0.0, 14.0)
			player.net_position = player.global_position
			player.face_now(Vector3.RIGHT)
			for x in [-5.0, -2.0, 1.0]:
				var orc := NetSpawn.unit(&"enemy", Vector3(x, 0.0, 14.0),
						{"scene": ORC_SCENE, "strength": 1.0, "coins": 0.0}) as Enemy
				orc.set_physics_process(false)
				orc.max_health = 5000.0  # one charge hit would kill a normal orc
				orc.health = 5000.0
				lane_orcs.append(orc)
			normal_collision_mask = player.collision_mask
			player.request_ability()
			_check(player.ability_active and (player.collision_mask & GameConfig.LAYER_ENEMIES) == 0,
					"Bull Rush ignores orc bodies from its first frame")
			_check((player.collision_mask & (GameConfig.LAYER_WORLD | GameConfig.LAYER_FENCE)) \
					== (normal_collision_mask & (GameConfig.LAYER_WORLD | GameConfig.LAYER_FENCE)),
					"Bull Rush still collides with walls and fences")
			step = 4
			t = 0.0
		4:
			if t < 1.75:
				return
			var damage := player.spear_damage * Player.BULL_RUSH_DAMAGE
			_check(player.global_position.x > 2.0, "Spearman passes through three real orcs (x=%.2f)" % player.global_position.x)
			_check(lane_orcs.all(func(orc: Enemy) -> bool:
				return is_equal_approx(orc.max_health - orc.health, damage)),
					"each real orc takes one charge hit")
			step = 5
			t = 0.0
		5:
			if t < 2.0:
				return
			_check(not player.ability_active and player.collision_mask == normal_collision_mask,
					"normal enemy collision returns after the charge")
			printerr("DONE failures=%d" % failures)
			get_tree().quit()
