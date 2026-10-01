extends Node
## Shield motion (Swordsman, or --class=spearman): carried upright on the forearm, face out, off the ground; it
## swings with the arm when running; up, it bobs / sways with the walk (walk clip, never sprint); a blocked hit
## knocks it back and it settles without re-blending the arms.
##   "$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/shield_motion_test.gd
var failures := 0
func _check(ok: bool, what: String) -> void:
	printerr(("PASS " if ok else "FAIL ") + what)
	if not ok: failures += 1
var t := 0.0
var step := 0
var player: Player
var samples: Array = []
func _ready() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
func _rel() -> Transform3D:
	# The shield's middle (the rectangular one has its origin at the bottom edge).
	var model_space := player.model.global_transform.affine_inverse() * player._left_item.global_transform
	return model_space * Transform3D(Basis.IDENTITY, player.class_def.shield_center)
func _fmt(x: Transform3D) -> String:
	var b := x.basis.orthonormalized()
	return "pos=%s up=%s face=%s" % [x.origin.snapped(Vector3.ONE * 0.01), b.y.snapped(Vector3.ONE * 0.01), b.z.snapped(Vector3.ONE * 0.01)]
func _process(delta: float) -> void:
	t += delta
	var players := get_tree().get_nodes_in_group(&"players")
	if players.is_empty() or t < 2.0:
		return
	player = players[0]
	var main := get_tree().current_scene
	match step:
		0:
			var idle := _rel()
			_check(idle.basis.orthonormalized().y.y > 0.95 and idle.basis.orthonormalized().z.x > 0.6 and idle.origin.y > 0.15,
					"idle: upright on the forearm, face out to the side, off the ground (%s)" % _fmt(idle))
			main.hud.joystick.output = Vector2(1, 0)  # run
			step = 1; t = 2.0; samples.clear()
		1:
			samples.append(_rel().origin.y)
			if t > 2.6:
				_check(samples.max() - samples.min() > 0.1, "running: swings with the arm (height %.2f..%.2f)" % [samples.min(), samples.max()])
				main._mouse_block = true
				samples.clear()
				step = 2; t = 2.0
		2:
			if t > 2.25: samples.append(_rel().origin)
			if t > 2.8:
				var ys := samples.map(func(v): return v.y)
				var xs := samples.map(func(v): return v.x)
				var zs := samples.map(func(v): return v.z)
				_check(ys.max() - ys.min() > 0.02 and zs.min() > 0.15, "up + walking: bobs (y %.2f..%.2f, x %.2f..%.2f), stays in front" % [ys.min(), ys.max(), xs.min(), xs.max()])
				_check(player.anim.current_animation == "walk", "walks (no sprint) behind the shield (%s)" % player.anim.current_animation)
				main.hud.joystick.output = Vector2.ZERO
				step = 3; t = 2.0
		3:
			if t > 2.6:
				var rest := _rel()
				_check(rest.basis.orthonormalized().z.z > 0.95, "up, standing: square in front (%s)" % _fmt(rest))
				set_meta(&"rest", rest)
				var dummy := Node3D.new(); main.add_child(dummy)
				dummy.global_position = player.global_position + player.facing() * 1.0
				player.take_damage(30.0, dummy)
				samples.clear()
				step = 4; t = 2.0
		4:
			samples.append(_rel().origin.distance_to((get_meta(&"rest") as Transform3D).origin))
			if t > 2.6:
				_check(samples.max() > 0.05 and samples[-1] < 0.01 and player._left_hold.influence > 0.9,
						"a blocked hit knocks it back %.2f m, it settles (%.3f), the arm stays up" % [samples.max(), samples[-1]])
				printerr("DONE failures=%d" % failures)
				get_tree().quit(1 if failures > 0 else 0)
