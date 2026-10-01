extends Node
## Training Field: real menu entry, unlimited ability, indestructible targets and F-style class switching.
##   "$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/training_test.gd

var t := 0.0
var step := 0
var failures := 0
var main: Node
var player: Player
var target: TrainingTarget
var field: TrainingField


func _ready() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _check(ok: bool, what: String) -> void:
	printerr(("PASS " if ok else "FAIL ") + what)
	if not ok:
		failures += 1


func _process(delta: float) -> void:
	t += delta
	if get_tree().current_scene == null:
		return
	match step:
		0:
			if t < 1.0:
				return
			var button := get_tree().current_scene.find_child("TrainingButton", true, false) as Button
			_check(button != null, "Training Field button is on the main menu")
			if button:
				button.pressed.emit()
			step = 1
			t = 0.0
		1:
			if t < 2.5 or get_tree().current_scene.name != "Main":
				return
			main = get_tree().current_scene
			player = main.get("local_player") as Player
			field = main.get("training_field") as TrainingField
			var targets := get_tree().get_nodes_in_group(&"breakable").filter(func(node: Node) -> bool: return node is TrainingTarget)
			_check(main.get("training_mode") == true and field != null, "Training Field loads as a local practice session")
			_check(player != null and player.training_mode, "training hero spawned")
			_check(targets.size() == 5, "five permanent damage targets spawned")
			_check(player.has_ability() and player.xp == 0 and player.ability_ready(), "special ability needs no XP")
			target = targets[0] as TrainingTarget
			# Begin toward the target, then turn away before the hit frame. The old direction must not damage it.
			player.global_position = target.global_position + Vector3(-1.65, 0.0, 0.0)
			player.net_position = player.global_position
			player.face_now(Vector3.RIGHT)
			player.melee()
			player.face_now(Vector3.LEFT)
			step = 2
			t = 0.0
		2:
			if t < 0.35:
				return
			_check(is_zero_approx(target.total_damage()), "turning away before impact does not hit the old target")
			step = 3
			t = 0.0
		3:
			if t < 0.25:
				return
			player.face_now(Vector3.RIGHT)
			player.melee()
			step = 4
			t = 0.0
		4:
			if t < 0.35:
				return
			_check(target.total_damage() > 0.0, "target takes damage when the hit sector really touches it")
			player.request_ability()
			_check(player.ability_active and player.xp == 0, "ability starts without spending or gaining XP")
			target.take_damage(99999.0, player)
			_check(not target.is_dead and target.is_inside_tree(), "damage target cannot be destroyed")
			# Bowman stands on the right pedestal.
			player.global_position = Vector3(5.5, 0.0, -13.0)
			field.update_player(player)
			main.call("_switch_training_class")
			step = 5
			t = 0.0
		5:
			if t < 0.5:
				return
			player = main.get("local_player") as Player
			_check(player != null and player.class_def.id == &"bowman" and player.training_mode, "F interaction switches to Bowman")
			_shoot_at_target()
			step = 6
			t = 0.0
		6:
			if t < 1.0:
				return
			_check(target.total_damage() > damage_before, "an arrow damages a training target")
			# Spearman stands on the middle pedestal.
			player.global_position = Vector3(0.0, 0.0, -13.0)
			field.update_player(player)
			main.call("_switch_training_class")
			step = 7
			t = 0.0
		7:
			if t < 0.5:
				return
			player = main.get("local_player") as Player
			_check(player != null and player.class_def.id == &"spearman", "F interaction switches to Spearman")
			player.switch_weapon()
			_check(player.current_weapon() == "javelin", "Spearman holds the javelin")
			_shoot_at_target()
			step = 8
			t = 0.0
		8:
			if t < 1.2:
				return
			_check(target.total_damage() > damage_before, "a thrown spear damages a training target")
			printerr("DONE failures=%d" % failures)
			get_tree().quit()


var damage_before := 0.0


## Shoots the ranged weapon in hand at the target from 6 m away.
func _shoot_at_target() -> void:
	damage_before = target.total_damage()
	player.global_position = target.global_position + Vector3(-6.0, 0.0, 0.0)
	player.net_position = player.global_position
	player.shoot(Vector3.RIGHT)
