extends Node
## Shield (Swordsman / Spearman): blocks hits from the front only while up, slows the hero, no attacks behind it,
## held up in front, breaks, gone until respawn.
##   "$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/shield_test.gd [--class=spearman]
var t := 0.0
var step := 0
var player: Player
var failures := 0
func _ready() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
func _check(ok: bool, what: String) -> void:
	printerr(("PASS " if ok else "FAIL ") + what)
	if not ok: failures += 1
func _process(delta: float) -> void:
	t += delta
	var players := get_tree().get_nodes_in_group(&"players")
	if players.is_empty() or t < 2.0:
		return
	player = players[0]
	var front := player.global_position + Vector3(1.0, 0, 0)
	var back := player.global_position + Vector3(-1.0, 0, 0)
	match step:
		0:
			player.max_health = 1000.0; player.health = 1000.0; player.regen_per_second = 0.0
			_check(player.has_shield() and player._left_item != null and player._left_item.visible, "%s carries a shield (%.0f)" % [player.class_def.id, player.shield_health])
			var base := player.move_speed
			player.set_input(Vector2.ZERO, Vector3(1, 0, 0), Vector3.ZERO, true)
			player.face_now(Vector3(1, 0, 0))
			_check(player.shield_up and is_equal_approx(player.move_speed, base * Player.BLOCK_SPEED), "right mouse raises it, slower (%.2f -> %.2f)" % [base, player.move_speed])
			var dummy := Node3D.new(); dummy.name = "Front"; get_tree().current_scene.add_child(dummy); dummy.global_position = front
			var shield_before := player.shield_health
			player.take_damage(40.0, dummy)
			_check(is_equal_approx(player.health, 1000.0) and is_equal_approx(player.shield_health, shield_before - 40.0), "a hit from the front is blocked (shield %.0f)" % player.shield_health)
			dummy.global_position = back
			player.take_damage(40.0, dummy)
			_check(player.health < 1000.0, "a hit from behind gets through (%.0f)" % player.health)
			var before_attack := player.action_token
			player.attack_melee()
			_check(player.action_token == before_attack, "can't attack with the shield up")
			get_tree().current_scene._mouse_block = true  # keep it up through the game's own input
			step = 1; t = 1.7
		1:
			var rel := player.model.global_transform.affine_inverse() * player._left_item.global_transform
			_check(rel.basis.orthonormalized().z.dot(Vector3(0, 0, 1)) > 0.95 and rel.origin.z > 0.15, "held up in front, facing forward (%s, front %s)" % [rel.origin.snapped(Vector3.ONE * 0.01), rel.basis.orthonormalized().z.snapped(Vector3.ONE * 0.01)])
			_check(player._left_hold.influence > 0.9, "left arm raised")
			get_tree().current_scene._mouse_block = false
			player.set_input(Vector2.ZERO, Vector3.ZERO, Vector3.ZERO, false)
			_check(not player.shield_up and is_equal_approx(player.move_speed, player._base_move_speed), "released: down, full speed")
			var dummy := get_tree().current_scene.get_node("Front") as Node3D
			dummy.global_position = front
			var health := player.health
			player.take_damage(10.0, dummy)
			_check(player.health < health, "down, a hit from the front gets through")
			player.set_input(Vector2.ZERO, Vector3(1, 0, 0), Vector3.ZERO, true)
			player.face_now(Vector3(1, 0, 0))
			player.take_damage(1000.0, dummy)
			_check(player.shield_health <= 0.0 and not player.shield_up and not player.has_shield(), "a big hit breaks it")
			player.set_input(Vector2.ZERO, Vector3(1, 0, 0), Vector3.ZERO, true)
			_check(not player.shield_up, "a broken shield can't go up")
			step = 2; t = 1.5
		2:
			_check(not player._left_item.visible, "broken shield is gone")
			player.revive(player.global_position)
			_check(player.has_shield() and player.shield_health == player.class_def.shield_health, "back on respawn")
			printerr("DONE failures=%d" % failures)
			get_tree().quit()
