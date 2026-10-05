extends Node
## Saves a screenshot of every screen (menus, lobby, match, spawn area, every enemy type, a graveyard, soldiers,
## upgrades sheet, pause) to check layouts and models.
## Needs a window (not --headless):
##   "$G" --path . res://tests/test_runner.tscn -- --test=res://tests/screenshot_test.gd --out=/tmp/shots [--mobile]

const STEPS := [
	["main_menu", "res://scenes/ui/main_menu.tscn", 2.0],
	["server_browser", "res://scenes/ui/server_browser.tscn", 2.0],
	["host_menu", "res://scenes/ui/host_menu.tscn", 2.0],
	["controls", "res://scenes/ui/controls_menu.tscn", 2.0],
	["lobby", "lobby", 2.0],
	["match", "res://scenes/main/main.tscn", 5.0],
	["spawn", "spawn", 2.0],  # zoomed out over the open spawn area (starter chest, no warbands)
	["enemies", "enemies", 2.5],  # every enemy type in a row (AI off)
	["graveyard", "graveyard", 2.5],  # the nearest graveyard (Graveyard Kit)
	["soldiers", "soldiers", 2.5],
	["soldiers_turned_90", "turn", 1.5],  # R: the camera orbits 90° (the sides normally unseen)
	["upgrades", "upgrades", 1.0],
	["upgrades_army", "upgrades_army", 1.0],
	["pause", "pause", 1.0],
]

var _out := "user://screenshots"
var _step := -1
var _wait := 0.0
var _zoom := 1.0  # camera offset factor of the zoomed-out shot


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	_next()


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s%s.png" % [_out, STEPS[_step][0], "_mobile" if Platform.mobile_layout else ""]
	image.save_png(path)
	printerr("saved ", path, " ", image.get_size())
	_next()


func _next() -> void:
	_step += 1
	if _step >= STEPS.size():
		get_tree().quit()
		return
	var target: String = STEPS[_step][1]
	_wait = STEPS[_step][2]
	match target:
		"lobby":
			Net.host()
			get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")
		"spawn":
			_set_zoom(2.4)
		"enemies":
			_set_zoom(0.6)
			var player: Player = get_tree().get_nodes_in_group(&"players")[0]
			player.global_position += Vector3(0, 0, 6)  # out of the way, below the lineup
			var types := Array(DirAccess.get_files_at("res://scenes/characters/enemies/")).filter(
					func(file: String) -> bool: return file.ends_with(".tscn"))
			for i in types.size():
				# Two rows (the big ones at the back), facing the camera.
				var row := 0 if i < 6 else 1
				var column := i if row == 0 else i - 6
				var count := 6 if row == 0 else types.size() - 6
				var at := player.global_position + Vector3((column - (count - 1) * 0.5) * 1.6, 0, -3.6 + row * 2.3)
				var enemy := NetSpawn.unit(&"enemy", at, {"scene": "res://scenes/characters/enemies/" + types[i],
						"strength": 1.0, "coins": 0.0}) as Enemy
				enemy.add_to_group(&"screenshot_enemies")
				enemy.set_physics_process(false)
		"graveyard":
			for enemy in get_tree().get_nodes_in_group(&"screenshot_enemies"):
				enemy.queue_free()
			var player: Player = get_tree().get_nodes_in_group(&"players")[0]
			var world := get_tree().current_scene.get_node("World")
			for child in world.get_children():
				if child.name.begins_with("Graveyard_"):
					player.global_position = (child as Node3D).global_position + Vector3(0, 0, 3)
					break
			_set_zoom(1.9)
		"soldiers":
			_set_zoom(1.0)
			var player: Player = get_tree().get_nodes_in_group(&"players")[0]
			player.global_position = Vector3.ZERO
			for i in 6:
				NetSpawn.unit(&"ally", player.global_position + Vector3(i - 2.5, 0, 2.0), {"team": player.team_id,
						"owner": player.peer_id, "weapon": player.class_def.ally_weapon})
		"turn":
			get_tree().current_scene.camera.rotate_step(1)
		"upgrades":
			var main := get_tree().current_scene
			main.camera.rotate_step(3)  # back to the default view after the turned shot
			main.hud.upgrade_sheet.open_sheet()
		"upgrades_army":
			var sheet: UpgradeSheet = get_tree().current_scene.hud.upgrade_sheet
			sheet._army_tab.button_pressed = true
			sheet._show_tab()
		"pause":
			get_tree().current_scene.hud.upgrade_sheet.close_sheet()
			get_tree().current_scene.get_node("PauseMenu").open()
		_:
			get_tree().change_scene_to_file(target)


func _set_zoom(factor: float) -> void:
	get_tree().current_scene.camera.offset *= factor / _zoom
	_zoom = factor
