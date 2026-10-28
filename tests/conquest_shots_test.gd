extends Node
## Conquest screenshots: the match HUD (score + stock lines), an enemy Citadel's walls and gate with the
## battering ram and catapult at work (zoomed out, then close), and the Army tab with the siege engines.
## Needs a window (not --headless):
##   "$G" --path . res://tests/test_runner.tscn -- --test=res://tests/conquest_shots_test.gd --out=/tmp/shots

var _out := "user://screenshots"
var t := 0.0
var _step := 0
var main: Node


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	Net.open_offline_lobby()
	Net.settings.mode = Net.Mode.CONQUEST
	Net.settings.seed = 777
	Net.settings.events = []
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")


func _shot(shot_name: String) -> void:
	var path := _out.path_join("conquest_%s.png" % shot_name)
	get_viewport().get_texture().get_image().save_png(path)
	printerr("saved ", path)


func _process(delta: float) -> void:
	t += delta
	main = get_tree().current_scene
	if main == null or main.name != "Main" or main.get("local_player") == null:
		return
	var player: Player = main.local_player
	var mode := main.game_mode as ConquestMode
	player.health = player.max_health
	var gate := mode.territories[1].gate
	var outside := gate.global_position + gate.global_basis.z.normalized() * 9.0
	outside.y = 0.0
	match _step:
		0:
			if t < 3.0:
				return
			_shot("hud")
			player.global_position = outside
			player.net_position = outside
			_step = 1
		1:
			if t < 5.0:
				return
			player.coins = 1000
			for id in [&"siege_ram", &"siege_catapult"]:
				for def in Player.CATALOG.upgrades:
					if def.id == id:
						player.buy_upgrade(def)
			main.camera.zoom = 2.2  # zoomed out: the walls, the gate and both engines at work
			_step = 2
		2:
			player.global_position = outside
			player.net_position = outside
			if t < 12.0:
				return
			_shot("siege_at_enemy_gate")
			main.camera.zoom = 0.9  # close-up of the engines
			_step = 4
		4:
			player.global_position = outside
			player.net_position = outside
			if t < 13.0:
				return
			_shot("siege_close")
			main.camera.zoom = 1.2
			main.hud.toggle_upgrades()
			var sheet: UpgradeSheet = main.hud.upgrade_sheet
			sheet._army_tab.button_pressed = true
			sheet._show_tab()
			_step = 3
		3:
			if t < 14.5:
				return
			_shot("upgrades")
			get_tree().quit()
