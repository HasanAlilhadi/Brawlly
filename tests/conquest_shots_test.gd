extends Node
## Conquest screenshots: the match HUD (score + stock lines), a zone 1 place (houses), the Demon's Lair, the M map (with
## a squad on the road), a squad's leader with its banner, an enemy Citadel's walls and gate with the
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
			if main.conquest_panel._hovered == &"":
				# The left column: the hero's level, the supplies with a minute of flows, the Weapons card open.
				for i in 5:
					player.credit_kill(player)
				mode.territories[player.team_id].train_kind = 1
				for i in 3:
					mode.logistics.tick()
				main.conquest_panel._hover(&"equipment")
				return
			_shot("hud")
			main.conquest_panel._hover(&"")
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
			var sheet: UpgradeSheet = main.hud.upgrade_sheet
			sheet._hero_tab.button_pressed = true  # the weapons an Unarmed hero buys
			sheet._show_tab()
			_step = 9
		9:
			if t < 15.0:
				return
			_shot("upgrades_hero")
			main.hud.toggle_upgrades()
			_step = 5
		5:
			# A zone 1 place: no walls, houses around the ring.
			var plain: TerritoryNode = mode.territories.filter(func(n: TerritoryNode) -> bool: return n.zone == 1 and n.gate == null)[0]
			player.global_position = plain.position + Vector3(0.0, 0.0, plain.radius() + 6.0)
			player.net_position = player.global_position
			if t < 16.5:
				return
			_shot("zone1_houses")
			_step = 6
		6:
			# The Demon's Lair in the middle.
			player.global_position = Vector3(0.0, 0.0, 19.0)
			player.net_position = player.global_position
			main.camera.zoom = 2.0
			if t < 19.0:
				return
			_shot("demon_lair")
			# The M map with our Citadel's card, a route from it to a City we hold, and its courier on the road.
			var city: TerritoryNode = mode.territories.filter(func(n: TerritoryNode) -> bool: return n.kind == TerritoryNode.Kind.CITY and n.zone >= 5)[0]
			city._captured_by(player.team_id)
			var home := mode.territories[player.team_id]
			home.lord = player.peer_id
			home.treasury = 120
			home.armed[1] = 5  # archers in training (rank II), swordsmen fresh, the rest of the people unarmed
			home.drill[1] = Ally.DRILL_SECONDS[2]
			home.armed[0] = 10
			mode.place_action(player, home.index, &"train", 1)
			mode.place_action(player, home.index, &"route", city.index)
			# A squad of 8 swordsmen (2 stay) sent from the Citadel toward the City.
			player.follower_cap += 20
			mode.place_action(player, home.index, &"muster", 0 + 10 * 1)
			var ids := mode.squads.of_player(player.peer_id)
			if not ids.is_empty():
				mode.squads.command(player, ids[0], &"go", city.index, Vector3.ZERO)
			mode.logistics.tick()
			main.conquest_map.toggle()
			main.conquest_map._selected = home
			_step = 7
		7:
			if t < 20.0:
				return
			_shot("map")
			main.conquest_map.toggle()
			main.camera.zoom = 0.6
			_step = 8
		8:
			# Close to the squad on the road: its leader carries the banner.
			var ids := mode.squads.of_player(player.peer_id)
			var head := mode.squads.leader_of(ids[0]) if not ids.is_empty() else null
			if head:
				player.global_position = head.global_position + Vector3(3.0, 0.0, 0.5)
				player.net_position = player.global_position
			if t < 23.0:
				return
			_shot("squad_banner")
			get_tree().quit()
