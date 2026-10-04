extends Node
## Saves a screenshot of every screen (menus, lobby, match, spawn area, soldiers, upgrades sheet, pause) to check layouts.
## Needs a window (not --headless):
##   "$G" --path . res://tests/test_runner.tscn -- --test=res://tests/screenshot_test.gd --out=/tmp/shots [--mobile]

const STEPS := [
	["main_menu", "res://scenes/ui/main_menu.tscn", 2.0],
	["server_browser", "res://scenes/ui/server_browser.tscn", 2.0],
	["host_menu", "res://scenes/ui/host_menu.tscn", 2.0],
	["controls", "res://scenes/ui/controls_menu.tscn", 2.0],
	["lobby", "lobby", 2.0],
	["match", "res://scenes/main/main.tscn", 5.0],
	["spawn", "spawn", 2.0],  # zoomed out over the open spawn area (starter chest, no camps)
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
		"soldiers":
			_set_zoom(1.0)
			var player: Player = get_tree().get_nodes_in_group(&"players")[0]
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
