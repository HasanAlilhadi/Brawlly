extends Node
## Host/client pair through the real menus: the client finds the host's locked game in the server browser
## (LAN discovery; direct connect if this network blocks broadcasts), is refused with a wrong password, joins
## with the right one, readies up in the lobby, is kicked by the host and lands in the main menu with the reason.
## Run two test_runner processes with --test=res://tests/lobby_test.gd --role=host / --role=client and the
## same --port (no --fixed-fps for network runs).

const SERVER_NAME := "Lobby Test"
const PASSWORD := "secret"

var role := "host"
var failures := 0
var finished := false


func _check(ok: bool, message: String) -> void:
	printerr(("PASS " if ok else "FAIL ") + role + ": " + message)
	if not ok:
		failures += 1


func _ready() -> void:
	name = "LobbyTest"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.substr(7)
	get_tree().create_timer(40.0).timeout.connect(func() -> void:
		if not finished:
			printerr("FAIL %s: lobby test timed out" % role)
			get_tree().quit(1))
	if role == "host":
		_host()
	else:
		_client()


func _finish() -> void:
	finished = true
	printerr("%s %s: done (%d failures)" % ["PASS" if failures == 0 else "FAIL", role, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _wait(condition: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call():
		if Time.get_ticks_msec() > end:
			return false
		await get_tree().process_frame
	return true


func _press(button_name: String) -> bool:
	var button := get_tree().current_scene.find_child(button_name, true, false) as Button
	if button:
		button.pressed.emit()
	return button != null


# --- Host ---------------------------------------------------------------------------------

func _host() -> void:
	Net.profile.name = "Hosty"
	get_tree().change_scene_to_file("res://scenes/ui/host_menu.tscn")
	await get_tree().create_timer(0.5).timeout
	var menu := get_tree().current_scene
	(menu.find_child("ServerNameEdit", true, false) as LineEdit).text = SERVER_NAME
	(menu.find_child("PasswordEdit", true, false) as LineEdit).text = PASSWORD
	(menu.find_child("MaxPlayersSlider", true, false) as HSlider).value = 4
	var saved_options: Dictionary = Net.profile.get("host", {}).duplicate()
	_check(_press("CreateButton"), "Create Lobby pressed")
	Net.remember_host_options(saved_options)  # keep the player's own saved host options
	_check(await _wait(_in_scene.bind("Lobby"), 3.0), "host is in the lobby")
	_check(Net.server_info.get("name") == SERVER_NAME and Net.server_info.get("max_players") == 4
			and Net.server_info.get("locked") == true, "server options applied: %s" % Net.server_info)
	_check(await _wait(_player_count_is.bind(2), 25.0), "client joined with the password")
	var client := 0
	for peer in Net.players:
		if peer != 1:
			client = peer
	_check(await _wait(Net.is_ready.bind(client), 5.0), "client is ready")
	await get_tree().create_timer(0.3).timeout
	_check(get_tree().current_scene.find_child("Kick_%d" % client, true, false) != null, "Kick button shown")
	_check(_press("Kick_%d" % client), "kick pressed")
	_check(await _wait(_player_count_is.bind(1), 3.0), "kicked client left the lobby")
	await get_tree().create_timer(2.0).timeout  # let the client see its notice
	_finish()


# --- Client --------------------------------------------------------------------------------------

func _client() -> void:
	Net.profile.name = "Clienty"
	get_tree().change_scene_to_file("res://scenes/ui/server_browser.tscn")
	await get_tree().create_timer(0.5).timeout
	var browser := get_tree().current_scene
	var found := await _wait(_listed, 8.0)
	_check(found, "host's game listed in the server browser (needs LAN broadcast)")
	if found:
		var info: Dictionary = Net.servers[_server_key()]
		_check(info.locked and int(info.max) == 4 and info.host == "Hosty", "listing shows lock / max / host: %s" % info)
		browser._join_server(_server_key())
	else:
		# Direct connect without a password: the host refuses, so the browser asks for one.
		browser._connect({"address": "127.0.0.1:%d" % Net.port, "name": SERVER_NAME, "direct": false}, "")
	_check(await _wait(_has_node.bind(browser, "PasswordEdit"), 5.0), "password asked")
	await _submit_password(browser, "wrong")
	_check(await _wait(_dialog_says.bind(browser, "Wrong password"), 5.0), "wrong password refused")
	await _submit_password(browser, PASSWORD)
	_check(await _wait(_in_scene.bind("Lobby"), 5.0), "client is in the lobby")
	await get_tree().create_timer(0.5).timeout
	var lobby := get_tree().current_scene
	_check((lobby.find_child("InviteLabel", true, false) as Label).text.contains(str(Net.port)), "invite address shown")
	var ready_button := lobby.find_child("ReadyButton", true, false) as Button
	_check(ready_button != null and ready_button.visible, "Ready button shown")
	_check(not lobby.find_child("StartButton", true, false).visible, "no Start button for players")
	ready_button.button_pressed = true
	_check(await _wait(Net.is_ready.bind(Net.my_id()), 3.0), "ready reached the host")
	_check(await _wait(_in_scene.bind("MainMenu"), 8.0), "kicked back to the main menu")
	await get_tree().create_timer(0.8).timeout
	_check(_dialog_text(get_tree().current_scene).contains("removed you"), "notice says why")
	_finish()


func _server_key() -> String:
	for key: String in Net.servers:
		if Net.servers[key].get("name") == SERVER_NAME:
			return key
	return ""


func _submit_password(browser: Node, password: String) -> void:
	var edit := browser.find_child("PasswordEdit", true, false) as LineEdit
	edit.text = password
	(browser.find_child("PasswordJoinButton", true, false) as Button).pressed.emit()
	await get_tree().create_timer(0.2).timeout


func _dialog_text(scene: Node) -> String:
	var dialog := scene.find_child("Dialog", true, false)
	if dialog == null:
		return ""
	var text := ""
	for label in dialog.find_children("*", "Label", true, false):
		text += (label as Label).text + " "
	return text


func _in_scene(scene_name: String) -> bool:
	return get_tree().current_scene != null and get_tree().current_scene.name == scene_name


func _player_count_is(count: int) -> bool:
	return Net.players.size() == count


func _listed() -> bool:
	return _server_key() != ""


func _has_node(scene: Node, node_name: String) -> bool:
	return scene.find_child(node_name, true, false) != null


func _dialog_says(scene: Node, text: String) -> bool:
	return _dialog_text(scene).contains(text)
