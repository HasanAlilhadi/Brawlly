extends Node
## Desktop controls: WASD moves, left mouse swings toward the cursor, Q switches to the bow, right mouse aims + shoots on release,
## K shoots at the nearest enemy (Space does nothing), E does nothing away from a stall and opens / closes the Blacksmith's shop at it,
## and touch controls stay hidden.
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
var at_stall := false
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
## Every stall (all building types) is in reach from each of its four sides, 1 m from its building, and out
## of reach 3 m away (like the barracks: no front-only spot).
func _check_stall_sides() -> void:
	var saved := player.global_position
	var kinds := {}
	for stall: ShopStation in get_tree().get_nodes_in_group(&"shop_stations"):
		if kinds.has(stall.stall_id):
			continue
		kinds[stall.stall_id] = true
		var rect: Rect2 = stall._footprint()
		var near := PackedStringArray()
		var far := PackedStringArray()
		for side in 4:
			for gap: float in [1.0, 3.0]:
				var c := rect.get_center()
				var local: Vector2 = [Vector2(c.x, rect.end.y + gap), Vector2(c.x, rect.position.y - gap),
						Vector2(rect.position.x - gap, c.y), Vector2(rect.end.x + gap, c.y)][side]
				player.global_position = stall.to_global(Vector3(local.x, 0, local.y))
				var in_reach := stall._distance(player) < ShopStation.INTERACT_RANGE
				if gap < 2.0 and not in_reach:
					near.append(["front", "back", "left", "right"][side])
				elif gap > 2.0 and in_reach:
					far.append(["front", "back", "left", "right"][side])
		_check(near.is_empty() and far.is_empty(), "%s: in reach from every side (missing %s, too far %s)" % [stall.title(), near, far])
	player.global_position = saved


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
			_check(player.weapons == PackedStringArray(["sword"]), "starts with the sword only")
			player.buy_weapon("bow")  # as if bought in the shop
			player.switch_weapon()  # back to the sword
			_check(not Platform.mobile_layout, "desktop layout")
			_check(not hud.joystick.visible and not hud.bow_stick.visible, "touch controls hidden")
			_check(is_equal_approx(main.camera.zoom, main.CAMERA_ZOOM), "default camera zoom with the sword (%.2f)" % main.camera.zoom)
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
				_check(is_equal_approx(main.camera.zoom, main.CAMERA_ZOOM + 0.2), "the bow zooms the camera out by 0.2 (%.2f)" % main.camera.zoom)
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
				_key(KEY_K, true)
				_next()
		5:
			if pt > 0.1:
				_key(KEY_K, false)
				_check(player.arrows < arrows_before, "K shoots")
				var space := InputEventKey.new()
				space.physical_keycode = KEY_SPACE
				_check(InputMap.get_actions().all(func(action: StringName) -> bool:
						return action.begins_with("ui_") or not InputMap.event_is_action(space, action)), "Space is not bound to any game action")
				_key(KEY_E, true)
				_key(KEY_E, false)
				_next()
		6:
			if pt > 0.2 and not at_stall:
				_check(not main.shop_menu.visible and not hud._stall_prompt.visible, "E does nothing away from a stall")
				_check_stall_sides()
				for stall: ShopStation in get_tree().get_nodes_in_group(&"shop_stations"):
					if stall.stall_id == &"blacksmith":
						player.global_position = stall.front()
						break
				at_stall = true
				pt = 0.0
			elif at_stall and pt > 0.3:
				_check(hud._stall_prompt.visible, "the stall prompt shows at the Blacksmith")
				_key(KEY_E, true)
				_key(KEY_E, false)
				_next()
		7:
			if pt > 0.2:
				_check(main.shop_menu.visible and main.shop_menu._title.text == "Blacksmith", "E opens the Blacksmith's shop")
				var rows: Array = main.shop_menu._rows.filter(func(r: Dictionary) -> bool: return (r.panel as Control).visible)
				_check(rows.size() == 1 and rows[0].def.id == &"blade", "it only sells the Sharp Blade")
				_key(KEY_E, true)
				_key(KEY_E, false)
				_next()
		8:
			if pt > 0.2:
				_check(not main.shop_menu.visible, "E closes the shop")
				var touch := InputEventScreenTouch.new()
				touch.pressed = true
				touch.position = Vector2(50, 50)
				Input.parse_input_event(touch)
				_next()
		9:
			if pt > 0.1:
				_check(hud.joystick.visible, "a real touch shows the touch controls")
				_check(hud._stall_prompt.visible, "the stall prompt stays for touch (tap it)")
				_key(KEY_W, true)
				_key(KEY_W, false)
				_next()
		10:
			if pt > 0.1:
				_check(not hud.joystick.visible, "keyboard hides them again")
				_key(KEY_R, true)
				_key(KEY_R, false)
				_next()
		11:
			if pt > 1.0:
				var cam: FollowCamera3D = main.camera
				_check(is_equal_approx(cam.view_yaw(), PI / 2.0), "R turns the camera exactly 90° (%.4f rad)" % cam.view_yaw())
				var look := -cam.global_basis.z
				_check(look.x < -0.4 and absf(look.z) < 0.01, "the camera looks along -X now (%s)" % look)
				start_pos = player.global_position
				_key(KEY_D, true)
				_next()
		12:
			if pt > 0.6:
				_key(KEY_D, false)
				var moved := player.global_position - start_pos
				# Screen right in the turned view is world -Z.
				_check(moved.z < -1.0 and absf(moved.x) < 0.3, "D moves screen-right in the turned view (%s)" % moved)
				for i in 3:
					_key(KEY_R, true)
					_key(KEY_R, false)
				_next()
		13:
			if pt > 1.0:
				var cam: FollowCamera3D = main.camera
				_check(is_zero_approx(fposmod(cam.view_yaw(), TAU)), "four turns bring the camera back (%.4f rad)" % cam.view_yaw())
				_log("DONE failures=%d" % failures)
				get_tree().quit(1 if failures > 0 else 0)
