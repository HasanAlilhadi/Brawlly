extends Node
## Conquest is its own section of the main menu: presses the real buttons — Conquest (its own hub page, look and
## backdrop) → Host Conquest Game (up to 16 players) → Create Lobby (Conquest, four faction cards of four seats, no
## mode choice) → Join a faction → Leave (back to the hub) → Back; then the classic Host Game →
## Create Lobby (no Conquest among its modes) → Leave; the server browser lists only its own section's games.
##   "$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/conquest_menu_test.gd
## --out=<dir> also saves screenshots of the Conquest page and lobby (needs a window, no --headless).

var failures := 0
var t := 0.0
var step := 0
var wait_until := 0.0
var _out := ""


func _check(ok: bool, message: String) -> void:
	printerr(("PASS " if ok else "FAIL ") + message)
	if not ok:
		failures += 1


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _press(button_name: String) -> bool:
	var button := get_tree().current_scene.find_child(button_name, true, false) as Button
	if button == null:
		_check(false, "button %s in %s" % [button_name, get_tree().current_scene.name])
		return false
	button.pressed.emit()
	return true


func _shot(shot_name: String) -> void:
	if _out != "" and DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(_out)
		get_viewport().get_texture().get_image().save_png(_out.path_join("conquest_menu_%s.png" % shot_name))


func _finish() -> void:
	printerr("%s conquest menu: done (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(1 if failures else 0)


func _process(delta: float) -> void:
	t += delta
	if t < wait_until or get_tree().current_scene == null:
		return
	var scene := get_tree().current_scene.name
	match step:
		0:
			if scene != "MainMenu" or t < 1.0:
				return
			_check(get_tree().root.theme == null, "the main menu has the classic look")
			_check(_press("ConquestButton"), "the main menu has a Conquest entry")
			step = 1
			wait_until = t + 1.0
		1:
			_check(scene == "ConquestMenu" and Net.conquest_section, "Conquest opens its own hub page (%s)" % scene)
			_check(get_tree().root.theme == ConquestLook.theme(), "with Conquest's own look")
			_check(get_tree().current_scene.get_node_or_null("Backdrop") is ConquestBackdrop, "and the Demon's Lair backdrop")
			_shot("hub")
			_press("ConquestHostButton")
			step = 2
			wait_until = t + 1.0
		2:
			_check(Net.conquest_section, "the Conquest section")
			_check(get_tree().current_scene.find_children("*", "Label", true, false).any(
					func(l: Label) -> bool: return l.text == "Host a Conquest Game"), "its own Host page")
			_check(get_tree().root.theme == ConquestLook.theme(), "in Conquest's look")
			var slider: HSlider = get_tree().current_scene.find_child("MaxPlayersSlider", true, false)
			_check(slider.max_value == Net.CONQUEST_MAX_PLAYERS, "takes up to 16 players (%d)" % slider.max_value)
			slider.value = Net.CONQUEST_MAX_PLAYERS
			_shot("host")
			_press("CreateButton")
			step = 3
			wait_until = t + 1.5
		3:
			_check(Net.mode() == Net.Mode.CONQUEST and Net.settings.team_count == ConquestMode.FACTIONS,
					"its lobby plays Conquest, four factions")
			_check(int(Net.server_info.max_players) == 16 and Net.faction_seats() == 4, "16 players, four seats a faction")
			_check(Net.settings.time_limit == ConquestMode.DEFAULT_TIME and Net.settings.score_limit == ConquestMode.DEFAULT_SCORE,
					"with Conquest's limits (%d min, %d points)" % [Net.settings.time_limit, Net.settings.score_limit])
			var lobby := get_tree().current_scene
			var mode_option: OptionButton = lobby.get("_mode_option")
			_check(mode_option != null and not (mode_option.get_parent() as Control).visible, "no mode choice in a Conquest lobby")
			var picker: Control = lobby.get("_class_picker")
			var note: Control = lobby.get("_classless_note")
			_check(not picker.visible and note.visible, "no hero class to pick: Conquest heroes buy their weapon")
			var board: Control = lobby.get("_faction_board")
			_check(board.visible and board.get_child_count() == ConquestMode.FACTIONS, "four faction cards instead of a list")
			_check((lobby.get("_conquest_info") as Label).visible, "and what Conquest is")
			_check(get_tree().root.theme == ConquestLook.theme(), "in Conquest's look")
			_press("JoinFaction_2")
			step = 31
			wait_until = t + 0.5
		31:
			_check(int(Net.players[1].team) == 2, "Join puts you in that faction")
			_shot("lobby")
			_press("LeaveButton")
			step = 32
			wait_until = t + 1.2
		32:
			_check(scene == "ConquestMenu", "Leave goes back to the Conquest hub (%s)" % scene)
			_press("BackButton")
			step = 4
			wait_until = t + 1.0
		4:
			_check(scene == "MainMenu" and get_tree().root.theme == null and not Net.conquest_section,
					"Back goes to the main menu, in the classic look")
			_press("HostButton")
			step = 5
			wait_until = t + 1.0
		5:
			_check(not Net.conquest_section, "the classic Host Game is outside the Conquest section")
			_press("CreateButton")
			step = 6
			wait_until = t + 1.5
		6:
			_check(Net.mode() == Net.Mode.COOP, "a classic lobby starts in Co-op")
			_check(int(Net.server_info.max_players) <= Net.MAX_PLAYERS, "the classic game takes up to 8")
			_check(not (get_tree().current_scene.get("_faction_board") as Control).visible, "its lobby lists the players")
			var mode_option: OptionButton = get_tree().current_scene.get("_mode_option")
			var names := []
			for i in mode_option.item_count:
				names.append(mode_option.get_item_text(i))
			_check(names.size() == Net.CLASSIC_MODES.size() and not names.has("Conquest"), "its modes: %s (no Conquest)" % [names])
			var classic_picker: ClassPicker = get_tree().current_scene.get("_class_picker")
			_check(classic_picker.visible and classic_picker.find_children("*", "Button", true, false).size() == ClassDef.pickable().size()
					and ClassDef.pickable().size() == 2, "the classic lobby picks Swordsman / Bowman (no Conquest-only class)")
			mode_option.item_selected.emit(2)
			_check(Net.mode() == Net.Mode.LAST_STAND, "picking the third mode plays Last Stand")
			_press("LeaveButton")
			step = 7
			wait_until = t + 1.0
		7:
			var conquest_game := {"mode": Net.Mode.CONQUEST}
			var classic_game := {"mode": Net.Mode.KING_OF_THE_HILL}
			Net.conquest_section = true
			_check(Net.in_section(conquest_game) and not Net.in_section(classic_game), "Find Conquest Game lists only Conquest games")
			Net.conquest_section = false
			_check(not Net.in_section(conquest_game) and Net.in_section(classic_game), "Find Game lists only the classic ones")
			_finish()
