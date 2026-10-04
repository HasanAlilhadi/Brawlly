extends Node
## Desktop controls, as a Spearman: WASD moves, left mouse thrusts toward the cursor (hits exactly the aim wedge), E switches
## to throwing, right mouse aims + throws on release, K throws at the nearest enemy (Space does nothing), F does nothing in a
## match (no stalls), T opens / closes the upgrades sheet (Hero: class upgrades + Vitality + Potion; Army: Recruit, Soldier
## Damage / Health, Command), and touch controls stay hidden.
##   "$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/desktop_input_test.gd --class=spearman

var t := 0.0
var phase := 0
var switched := false
var pt := 0.0
var main: Node
var player: Player
var hud: Hud
var start_pos: Vector3
var shots_before := ""
var failures := 0
var test_trees: Array[ChoppableTree] = []


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


## Trees around the swing that just started (x right, z forward): at the hit area's edge (just inside it), point-blank,
## beside it and past its reach. Fan weapons (sword) by angle, lane weapons (spear) by width.
func _spawn_test_trees() -> void:
	var forward: Vector3 = player._melee_dir
	var reach := player.melee_reach()
	var spots: Array[Vector2] = []
	if player.melee_lane() > 0.0:
		var half := player.melee_lane() * 0.5
		spots = [Vector2(half - 0.15, reach - 0.75), Vector2(0.0, 0.45), Vector2(half + 0.55, 1.2), Vector2(0.0, reach + 0.6)]
	else:
		var half := player.melee_arc() * 0.5
		for spot in [[half - 3.0, reach - 0.25], [0.0, 0.45], [half + 15.0, 1.2], [0.0, reach + 0.6]]:
			spots.append(Vector2(sin(deg_to_rad(spot[0])), cos(deg_to_rad(spot[0]))) * spot[1])
	var side := forward.cross(Vector3.UP)
	for spot in spots:
		var tree := preload("res://scenes/world/choppable_tree.tscn").instantiate() as ChoppableTree
		main.add_child(tree)
		tree.global_position = player.global_position - side * spot.x + forward * spot.y
		test_trees.append(tree)


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
			_check(player.weapons == PackedStringArray(["spear"]), "the Spearman starts with the spear thrust only")
			player.grant_upgrade(&"spear_throw")
			player.grant_upgrade(&"shield")
			_check(player.weapons == PackedStringArray(["spear", "javelin"]), "Can Throw + Shield bought: thrust + throw")
			_check(not Platform.mobile_layout, "desktop layout")
			_check(not hud.joystick.visible and not hud.bow_stick.visible, "touch controls hidden")
			_check(is_equal_approx(main.camera.zoom, main.CAMERA_ZOOM + 0.05), "spear thrust: nearly the default camera zoom (%.2f)" % main.camera.zoom)
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
			if pt > 0.1 and test_trees.is_empty():
				_check(player.facing().x > 0.8, "left mouse thrusts toward the cursor (facing %s)" % player.facing())
				_mouse(MOUSE_BUTTON_LEFT, false, _right_of_player())
				_check(player.holds_melee() and player._weapon_items.spear.visible and player._weapon_items.sword == null \
						and player._weapon_items.bow == null and player.has_shield(), "the spear in hand and a shield, no sword or bow")
				_spawn_test_trees()
			elif pt > 0.45 and not test_trees.is_empty():
				# Damage lands 0.24 s into the swing: everything inside the aim wedge, nothing outside it.
				var hit: Array[bool] = []
				for tree in test_trees:
					hit.append(tree.health < tree.max_health)
					tree.queue_free()
				_check(hit == [true, true, false, false],
						"the spear hits trees in the wedge (edge, point-blank) and not outside it (side, too far): %s" % [hit])
				_key(KEY_E, true)
				_key(KEY_E, false)
				_next()
		3:
			if pt > 0.15 and not switched:
				switched = true
				_check(player.holds_ranged() and player.current_weapon() == "javelin" and player._weapon_items.javelin.visible,
						"E switches to throwing (spear still in hand)")
				_check(is_equal_approx(main.camera.zoom, main.CAMERA_ZOOM + 0.1), "throwing zooms the camera out by 0.1 (%.2f)" % main.camera.zoom)
				shots_before = player.action_token
				_mouse(MOUSE_BUTTON_RIGHT, true, _right_of_player())
				pt = 0.0
			elif switched and pt > 0.3:
				_check(player.is_aiming(), "right mouse aims the throw")
				_mouse(MOUSE_BUTTON_RIGHT, false, _right_of_player())
				_next()
		4:
			if pt > 1.2:  # the throw cooldown is over
				_check(player.action_token != shots_before and not player.is_aiming(), "release throws (no ammo needed)")
				shots_before = player.action_token
				_key(KEY_K, true)
				_next()
		5:
			if pt > 0.1:
				_key(KEY_K, false)
				_check(player.action_token != shots_before, "K throws")
				var space := InputEventKey.new()
				space.physical_keycode = KEY_SPACE
				_check(InputMap.get_actions().all(func(action: StringName) -> bool:
						return action.begins_with("ui_") or not InputMap.event_is_action(space, action)), "Space is not bound to any game action")
				_key(KEY_F, true)
				_key(KEY_F, false)
				_next()
		6:
			if pt > 0.2:
				var sheet: UpgradeSheet = hud.upgrade_sheet
				_check(not sheet.is_open and get_tree().get_node_count_in_group(&"shop_stations") == 0,
						"F does nothing in a match (no stalls)")
				_key(KEY_T, true)
				_key(KEY_T, false)
				_next()
		7:
			if pt > 0.5:
				var sheet: UpgradeSheet = hud.upgrade_sheet
				var hero := sheet._hero_grid.get_children().map(func(c: Node) -> String: return String(c.name).trim_prefix("Card_"))
				var army := sheet._army_grid.get_children().map(func(c: Node) -> String: return String(c.name).trim_prefix("Card_"))
				_check(sheet.is_open and sheet.visible, "T opens the upgrades sheet")
				_check(hero.slice(hero.size() - 2) == ["vitality", "potion"] and hero.has("spear_damage"),
						"Hero tab: class upgrades, then Vitality and Potion (%s)" % [hero])
				_check(army == ["recruit", "soldier_damage", "soldier_health", "command"], "Army tab: %s" % [army])
				_key(KEY_T, true)
				_key(KEY_T, false)
				_next()
		8:
			if pt > 0.5:
				_check(not hud.upgrade_sheet.is_open, "T closes it")
				var touch := InputEventScreenTouch.new()
				touch.pressed = true
				touch.position = Vector2(50, 50)
				Input.parse_input_event(touch)
				_next()
		9:
			if pt > 0.1:
				_check(hud.joystick.visible, "a real touch shows the touch controls")
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
