extends Node
## Multiplayer menu: your name, color and class, Host a game, or Join one — from the list of games found on
## your Wi-Fi, or by typing the host's IP address (shown in the host's lobby).

const LOBBY_SCENE := "res://scenes/ui/lobby.tscn"
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const CONNECT_TIMEOUT: float = 8.0

@onready var _name_edit: LineEdit = %NameEdit
@onready var _colors: GridContainer = %Colors
@onready var _preview: ArmyPreview = %ArmyPreview
@onready var _host_button: Button = %HostButton
@onready var _server_list: VBoxContainer = %ServerList
@onready var _ip_edit: LineEdit = %IpEdit
@onready var _join_button: Button = %JoinButton
@onready var _status: Label = %Status
@onready var _back_button: Button = %BackButton

var _color_index: int = 0
var _class_picker: ClassPicker
var _color_buttons: Array[Button] = []
var _connecting: float = 0.0
var _leaving: bool = false


func _ready() -> void:
	get_tree().paused = false
	_name_edit.text = Net.profile.name
	_color_index = Net.profile.color
	for i in Net.PLAYER_COLORS.size():
		_add_color_button(i)
	_update_color_buttons()
	_build_class_picker()
	_name_edit.text_changed.connect(func(_text: String) -> void: _save_profile())
	_host_button.pressed.connect(_host)
	_join_button.pressed.connect(func() -> void: _join(_ip_edit.text))
	_back_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(MENU_SCENE))
	Net.servers_changed.connect(_refresh_servers)
	Net.connection_failed.connect(_on_connection_failed)
	Net.lobby_changed.connect(_on_lobby_changed)
	Net.start_discovery()
	_refresh_servers()


func _exit_tree() -> void:
	Net.stop_discovery()


func _process(delta: float) -> void:
	if _connecting > 0.0:
		_connecting -= delta
		if _connecting <= 0.0:
			Net.close_connection()
			_status.text = "Could not reach that game."
			_set_buttons_enabled(true)


## "Your class" under the colors; the preview shows the class and its soldiers.
func _build_class_picker() -> void:
	var row := _colors.get_parent()
	var label := Label.new()
	label.text = "Your class"
	row.get_parent().add_child(label)
	row.get_parent().move_child(label, row.get_index() + 1)
	_class_picker = ClassPicker.new()
	row.get_parent().add_child(_class_picker)
	row.get_parent().move_child(_class_picker, label.get_index() + 1)
	_class_picker.select(Net.profile["class"])
	_preview.set_class(Net.profile["class"])
	_class_picker.picked.connect(func(class_id: StringName) -> void:
		Net.set_class(class_id)
		_preview.set_class(class_id))


func _add_color_button(index: int) -> void:
	var button := Button.new()
	button.custom_minimum_size = Vector2(66, 60)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void:
		_color_index = index
		_update_color_buttons()
		_save_profile())
	_colors.add_child(button)
	_color_buttons.append(button)


func _update_color_buttons() -> void:
	_preview.set_color(Net.PLAYER_COLORS[_color_index])
	for i in _color_buttons.size():
		var style := StyleBoxFlat.new()
		style.bg_color = Net.PLAYER_COLORS[i]
		style.set_corner_radius_all(10)
		var selected := i == _color_index
		style.set_border_width_all(6 if selected else 2)
		style.border_color = Color("fff4de") if selected else Color(0.2, 0.1, 0.05, 0.6)
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			_color_buttons[i].add_theme_stylebox_override(state, style)
		_color_buttons[i].text = "✓" if selected else ""


func _save_profile() -> void:
	Net.set_profile(_name_edit.text, _color_index)


func _host() -> void:
	_save_profile()
	if Net.host() == OK:
		_go_to_lobby()
	else:
		_status.text = "Could not start a game (is another one already running on this device?)."


func _join(address: String) -> void:
	if address.strip_edges() == "":
		_status.text = "Type the host's IP address (shown in their lobby), or pick a game from the list."
		return
	_save_profile()
	if Net.join(address) != OK:
		_status.text = "That address doesn't look right."
		return
	_status.text = "Connecting to %s…" % address
	_connecting = CONNECT_TIMEOUT
	_set_buttons_enabled(false)


func _on_lobby_changed() -> void:
	if Net.is_online() and Net.players.has(Net.my_id()):
		_go_to_lobby()


## Opens the lobby once. (Hosting also emits lobby_changed, and Godot removes this scene from the tree
## as soon as a scene change starts — a second change_scene call would hit a null tree.)
func _go_to_lobby() -> void:
	if _leaving or not is_inside_tree():
		return
	_leaving = true
	_connecting = 0.0
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_connection_failed(reason: String) -> void:
	_connecting = 0.0
	_status.text = reason
	_set_buttons_enabled(true)


func _set_buttons_enabled(enabled: bool) -> void:
	_host_button.disabled = not enabled
	_join_button.disabled = not enabled
	for child in _server_list.get_children():
		if child is Button:
			child.disabled = not enabled


func _refresh_servers() -> void:
	for child in _server_list.get_children():
		child.queue_free()
	if Net.servers.is_empty():
		var label := Label.new()
		label.text = "Looking for games on your Wi-Fi…"
		label.add_theme_font_size_override("font_size", 22)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_server_list.add_child(label)
		return
	for ip: String in Net.servers:
		var info: Dictionary = Net.servers[ip]
		var button := Button.new()
		button.theme_type_variation = &"ButtonBeige"
		button.custom_minimum_size = Vector2(0, 80)
		button.add_theme_font_size_override("font_size", 26)
		var mode_name: String = Net.MODE_NAMES[clampi(int(info.get("mode", 0)), 0, Net.MODE_NAMES.size() - 1)]
		button.text = "%s's game — %s (%d/%d)" % [info.get("name", "?"), mode_name, int(info.get("players", 0)), int(info.get("max", 8))]
		button.disabled = bool(info.get("in_game", false))
		if button.disabled:
			button.text += "  playing"
		button.pressed.connect(_join.bind(ip))
		_server_list.add_child(button)
