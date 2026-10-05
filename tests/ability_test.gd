extends Node
## Special ability: orcs drop XP by their power, the hero collects it up to ClassDef.ability_xp, X spends it.
## Swordsman Whirlwind: spins for the ability's duration, hits everything around (not just in front),
## slower, can't attack or block meanwhile, then ends.
##   "$G" --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/ability_test.gd [--shot=<png>]
var t := 0.0
var step := 0
var player: Player
var orcs: Array[Enemy] = []
var failures := 0
var shot := ""
var _health_before: Array[float] = []
var _orb_xp := 0
var _whirlwind_arc_id: int = 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot = arg.substr(7)
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")


func _check(ok: bool, what: String) -> void:
	printerr(("PASS " if ok else "FAIL ") + what)
	if not ok: failures += 1


func _xp_orbs() -> Array[Pickup]:
	var found: Array[Pickup] = []
	for node in get_tree().current_scene.find_children("*", "Node3D", true, false):
		if node is Pickup and (node as Pickup).kind == Pickup.Kind.XP and not node.is_queued_for_deletion():
			found.append(node)
	return found


func _process(delta: float) -> void:
	t += delta
	var players := get_tree().get_nodes_in_group(&"players")
	if players.is_empty() or t < 2.0:
		return
	player = players[0]
	match step:
		0:
			player.max_health = 5000.0; player.health = 5000.0
			_check(player.has_ability() and player.class_def.ability == &"whirlwind" and player.xp == 0, "Swordsman has Whirlwind, no XP yet")
			_check(not player.ability_ready(), "not ready without XP")
			# Enemies (their bands far away, so paused) brought around the hero.
			for node in get_tree().get_nodes_in_group(&"enemies"):
				if node is Enemy and (node as Enemy).component(BossTrait) == null and (node as Enemy).faction == &"orc" and orcs.size() < 4:
					orcs.append(node)
			var all: Array = get_tree().get_nodes_in_group(&"enemies").filter(func(n: Node) -> bool: return n is Enemy)
			all.sort_custom(func(a: Enemy, b: Enemy) -> bool: return a.max_health < b.max_health)
			_check(all[-1].xp_drop() > all[0].xp_drop(), "stronger enemies drop more XP (%.0f hp: %d, %.0f hp: %d)" % [all[0].max_health, all[0].xp_drop(), all[-1].max_health, all[-1].xp_drop()])
			for orc in orcs:
				orc.process_mode = Node.PROCESS_MODE_INHERIT  # paused bands' members are out of physics
			_orb_xp = orcs[0].xp_drop()
			orcs[0].global_position = player.global_position + Vector3(3.0, 0, 0)
			orcs[0].die()
			step = 1; t = 1.6
		1:
			var orbs := _xp_orbs()
			var total := 0
			for orb in orbs:
				total += orb.amount
			_check(total == _orb_xp, "a killed orc drops %d XP" % total)
			for orb in orbs:
				orb.global_position = player.global_position
			step = 2; t = 1.6
		2:
			_check(player.xp == mini(_orb_xp, player.class_def.ability_xp), "walking over it collects it (%d XP)" % player.xp)
			player.xp = 9
			player.collect(Pickup.Kind.XP, 5)
			_check(player.xp == player.class_def.ability_xp and player.ability_ready(), "capped at %d, ready" % player.class_def.ability_xp)
			_check(not player.can_collect(Pickup.Kind.XP), "full: leaves orbs for others")
			# Go next to an orc band so it wakes up, then bring three of them around the hero.
			var band := _orc_band()
			player.global_position = band.global_position + Vector3(7.0, 0, 0)
			player.net_position = player.global_position
			step = 21; t = 0.5
		21:
			orcs.clear()
			for orc in _orc_band().members():
				if orcs.size() < 3:
					orcs.append(orc)
			_check(orcs.size() == 3 and orcs.all(func(o: Enemy) -> bool: return o.process_mode != Node.PROCESS_MODE_DISABLED), "band awake (%d orcs)" % orcs.size())
			var spots := [Vector3(1.2, 0, 0), Vector3(-1.2, 0, 0), Vector3(0, 0, 1.3)]
			_health_before.clear()
			player.crit_chance = 0.0  # deterministic Whirlwind pulse damage
			for i in 3:
				var orc := orcs[i]
				orc.max_health = 5000.0; orc.health = 5000.0
				orc.global_position = player.global_position + spots[i]
				orc.set_physics_process(false)  # stand still (calm band members would walk back to their spots)
				_health_before.append(orc.health)
			var walk := player.move_speed
			player.request_ability()
			_check(player.ability_active and player.xp == 0, "X starts it and spends the XP")
			_check(is_instance_valid(player._whirlwind_arc) and player._whirlwind_arc.visible,
					"Whirlwind shows its reusable slash effect")
			if is_instance_valid(player._whirlwind_arc):
				_whirlwind_arc_id = player._whirlwind_arc.get_instance_id()
			var spin_yaw := player._spin_world_yaw
			player.face_now(Vector3.RIGHT)
			var right_yaw := player.model.rotation.y + player._whirlwind_local_yaw()
			player.face_now(Vector3.LEFT)
			var left_yaw := player.model.rotation.y + player._whirlwind_local_yaw()
			_check(absf(angle_difference(right_yaw, spin_yaw)) < 0.001
					and absf(angle_difference(left_yaw, spin_yaw)) < 0.001,
					"running left or right does not change the Whirlwind rotation")
			_check(player.ability_xp_locked and not player.can_collect(Pickup.Kind.XP), "XP collection locks on activation")
			_check(not player.collect(Pickup.Kind.XP, 5) and player.xp == 0, "XP cannot increase during the lockout")
			_check(is_equal_approx(player.move_speed, walk * Player.WHIRLWIND_SPEED), "slower while spinning (%.2f -> %.2f)" % [walk, player.move_speed])
			var token := player.action_token
			player.attack_melee()
			player.set_input(Vector2.ZERO, Vector3.ZERO, Vector3.ZERO, true)
			_check(player.action_token == token and not player.shield_up, "no attacks or blocking while spinning")
			step = 3; t = 1.0
		3:
			var all_hit := true
			var pulse_damage := player.melee_damage * Player.WHIRLWIND_DAMAGE
			var expected := pulse_damage * 2.0  # completed rotations at 0.4 s and 0.8 s
			var pulse_count_ok := true
			for i in 3:
				all_hit = all_hit and orcs[i].health < _health_before[i]
				pulse_count_ok = pulse_count_ok and is_equal_approx(_health_before[i] - orcs[i].health, expected)
			_check(all_hit, "hits orcs on every side (%s)" % [orcs.map(func(o: Enemy) -> int: return int(o.health))])
			_check(pulse_count_ok,
				"hits once per completed spin (2 pulses in 1 s, %.0f damage each)" % pulse_damage)
			var skeleton := player.model.find_child("Skeleton3D", true, false) as Skeleton3D
			_check(skeleton.transform.basis.get_euler().y != 0.0 or player._spin_angle != 0.0, "the body spins")
			var arcs := player.find_children("WhirlwindArc", "MeshInstance3D", false, false)
			_check(arcs.size() == 1 and arcs[0].get_instance_id() == _whirlwind_arc_id,
					"Whirlwind moves one slash effect instead of spawning copies")
			var sword := player._weapon_items.get("sword") as Node3D
			var tip := player.to_local(sword.global_transform * player.sword_tip_point)
			var sword_yaw := atan2(tip.x, tip.z)
			var arc_head_yaw := player._whirlwind_arc.rotation.y \
					- deg_to_rad(Player.WHIRLWIND_ARC_DEGREES) * 0.5
			_check(absf(angle_difference(arc_head_yaw, sword_yaw)) < 0.01
					and is_equal_approx(player._whirlwind_arc.position.y, tip.y),
					"Whirlwind slash effect follows the sword tip")
			if shot != "":
				get_viewport().get_texture().get_image().save_png(shot)
			step = 4; t = 2.0 - 3.3
		4:
			_check(not player.ability_active, "over after %.0f s" % player.class_def.ability_duration)
			_check(is_instance_valid(player._whirlwind_arc) and not player._whirlwind_arc.visible,
					"Whirlwind hides the reusable slash effect when finished")
			_check(player.move_speed == player.running_speed(), "normal speed again")
			_check(player.ability_xp_locked and not player.can_collect(Pickup.Kind.XP), "XP stays locked after Whirlwind ends")
			step = 5; t = 2.0 - 6.0
		5:
			_check(not player.ability_xp_locked and player.can_collect(Pickup.Kind.XP), "XP collection unlocks after %.0f s" % player.class_def.ability_xp_lockout)
			# Bands roam: a passing enemy the spin killed may have left orbs right here, and they jump in the moment
			# XP changes. Clear them so this checks the lockout only.
			for orb in _xp_orbs():
				orb.get_parent().remove_child(orb)
				orb.queue_free()
			player.xp = 0
			_check(player.collect(Pickup.Kind.XP, 5) and player.xp == 5, "XP can increase again (%d)" % player.xp)
			printerr("DONE failures=%d" % failures)
			get_tree().quit()


## The smallest orc band with at least three members (orcs: no ghosts phasing through the Whirlwind; small:
## no stray kills dropping XP during the checks).
func _orc_band() -> Warband:
	var best: Warband = null
	for node in get_tree().get_nodes_in_group(&"warbands"):
		var band := node as Warband
		if band.faction == &"orc" and band.members().size() >= 3 and (best == null or band.size < best.size):
			best = band
	return best
