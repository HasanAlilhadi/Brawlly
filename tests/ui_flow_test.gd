extends Node
## Presses the real menu buttons: Host Game → Create Lobby → Leave, then Find Game → Back (no single player:
## no Play button), then Host Game → Create Lobby → Start.
var t := 0.0
var step := 0
var wait_until := 0.0

func _ready() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

func _press(button_name: String) -> void:
	var button := get_tree().current_scene.find_child(button_name, true, false) as Button
	printerr("[%.1f] press %s in %s -> %s" % [t, button_name, get_tree().current_scene.name, "found" if button else "MISSING"])
	if button:
		button.pressed.emit()

func _process(delta: float) -> void:
	t += delta
	if t < wait_until or get_tree().current_scene == null:
		return
	var scene := get_tree().current_scene.name
	match step:
		0: if scene == "MainMenu" and t > 1.0: _press("HostButton"); step = 1; wait_until = t + 1.0
		1: printerr("  now in: ", scene); _press("CreateButton"); step = 2; wait_until = t + 1.5
		2: printerr("  now in: ", scene, " online=", Net.is_online(), " players=", Net.players.size(), " server=", Net.server_info.get("name")); _press("LeaveButton"); step = 3; wait_until = t + 1.0
		3: printerr("  now in: ", scene, " online=", Net.is_online(), " Play button: ", get_tree().current_scene.find_child("PlayButton", true, false)); _press("FindButton"); step = 4; wait_until = t + 1.0
		4: printerr("  now in: ", scene); _press("BackButton"); step = 5; wait_until = t + 1.0
		5: printerr("  now in: ", scene); _press("HostButton"); step = 6; wait_until = t + 1.0
		6: printerr("  now in: ", scene); _press("CreateButton"); step = 7; wait_until = t + 1.5
		7: printerr("  now in: ", scene); _press("StartButton"); step = 8; wait_until = t + 8.0
		8:
			printerr("  now in: ", scene, " players spawned=", get_tree().get_nodes_in_group(&"players").size())
			get_tree().quit()
