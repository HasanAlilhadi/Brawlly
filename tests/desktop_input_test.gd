extends Node
## Desktop controls: WASD moves, left mouse swings toward the cursor, Q switches to the bow, right mouse aims + shoots on release,
## Space shoots at the nearest enemy, B opens / closes the shop, and touch controls stay hidden.
##   "$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/desktop_input_test.gd

var t := 0.0
var phase := 0
var switched := false
var pt := 0.0
var main: Node
var player: Player
var hud: Hud
var start_pos: Vector3
var arrows_before := 0
var failures := 0


func _ready() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")


func _log(msg: String) -> void:
	printerr("[%.1fs] %s" % [t, msg])


func _check(ok: bool, what: String) -> void:
	_log(("PASS " if ok else "FAIL ") + what)
	if not ok:
		failures += 1


func _next() -> void:
	phase += 1
	pt = 0.0


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func _mouse(button: MouseButton, pressed: bool, at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = at
	e.global_position = at
	Input.parse_input_event(e)


## Screen point 3 m to the right of the player.
func _right_of_player() -> Vector2:
	var camera := get_viewport().get_camera_3d()
	return camera.unproject_position(player.global_position + Vector3(3, 0, 0))


func _process(delta: float) -> void:
	t += delta
	pt += delta
	main = get_tree().current_scene
	if main == null or not main.has_node("HUD"):
		return
	hud = main.get_node("HUD")
	var players := get_tree().get_nodes_in_group(&"players")
	if players.is_empty():
		return
	player = players[0]
	match phase:
		0:
			if pt < 1.0:
				return
			player.max_health = 1e6
			player.health = 1e6
			_check(not Platform.mobile_layout, "desktop layout")
			_check(not hud.joystick.visible and not hud.bow_stick.visible, "touch controls hidden")
			start_pos = player.global_position
			_key(KEY_D, true)
			_next()
		1:
			if pt > 0.6:
				_key(KEY_D, false)
				_check(player.global_position.x - start_pos.x > 1.0, "D moves right (%.2f)" % (player.global_position.x - start_pos.x))
				_mouse(MOUSE_BUTTON_LEFT, true, _right_of_player())
				_next()
		2:
			if pt > 0.1:
				_check(player.facing().x > 0.8, "left mouse swings toward the cursor (facing %s)" % player.facing())
				_mouse(MOUSE_BUTTON_LEFT, false, _right_of_player())
				_check(player.holds_melee() and player._right_item.visible and not player._left_item.visible,
						"starts with the sword in hand, bow put away")
				_key(KEY_Q, true)
				_key(KEY_Q, false)
				_next()
		3:
			if pt > 0.15 and not switched:
				switched = true
				_check(player.holds_ranged() and player._left_item.visible and not player._right_item.visible,
						"Q switches to the bow (sword put away)")
				arrows_before = player.arrows
				_mouse(MOUSE_BUTTON_RIGHT, true, _right_of_player())
				pt = 0.0
			elif switched and pt > 0.3:
				_check(player.is_aiming(), "right mouse aims the bow")
				_mouse(MOUSE_BUTTON_RIGHT, false, _right_of_player())
				_next()
		4:
			if pt > 0.3:
				_check(player.arrows == arrows_before - 1 and not player.is_aiming(), "release shoots (%d -> %d arrows)" % [arrows_before, player.arrows])
				arrows_before = player.arrows
				_key(KEY_SPACE, true)
				_next()
		5:
			if pt > 0.1:
				_key(KEY_SPACE, false)
				_check(player.arrows < arrows_before, "Space shoots")
				_key(KEY_B, true)
				_key(KEY_B, false)
				_next()
		6:
			if pt > 0.2:
				_check(main.shop_menu.visible, "B opens the shop")
				_key(KEY_B, true)
				_key(KEY_B, false)
				_next()
		7:
			if pt > 0.2:
				_check(not main.shop_menu.visible, "B closes the shop")
				var touch := InputEventScreenTouch.new()
				touch.pressed = true
				touch.position = Vector2(50, 50)
				Input.parse_input_event(touch)
				_next()
		8:
			if pt > 0.1:
				_check(hud.joystick.visible, "a real touch shows the touch controls")
				_key(KEY_W, true)
				_key(KEY_W, false)
				_next()
		9:
			if pt > 0.1:
				_check(not hud.joystick.visible, "keyboard hides them again")
				_log("DONE failures=%d" % failures)
				get_tree().quit(1 if failures > 0 else 0)
