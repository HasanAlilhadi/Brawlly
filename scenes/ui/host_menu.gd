extends Node
## Host Game (main menu → Host Game): the server's options before it opens — server name, max players,
## password and whether it is listed in other players' server browser — then Create Lobby (`Net.host()`).
## The match settings (mode, camps, difficulty, …) are picked in the lobby. The last options are remembered
## (never the password).

const LOBBY_SCENE := "res://scenes/ui/lobby.tscn"
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const FORM_WIDTH: float = 980.0
const LABEL_WIDTH: float = 260.0

var _frame: Dictionary
var _form: PanelContainer
var _name_edit: LineEdit
var _max_slider: HSlider
var _max_label: Label
var _password_edit: LineEdit
var _listed_tab: Button
var _private_tab: Button
var _visibility_hint: Label
var _dialog: Dictionary = {}
var _leaving: bool = false


func _ready() -> void:
	get_tree().paused = false
	_build()
	_load_options()
	get_viewport().size_changed.connect(_layout)
	_layout()
	_name_edit.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _dialog.is_empty():
			_go_to(MENU_SCENE)
		else:
			MenuKit.close_dialog(_dialog)
			_dialog = {}


func _build() -> void:
	_frame = MenuKit.frame($UI, "Host a Game")
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	(_frame.body as Control).add_child(center)
	_form = PanelContainer.new()
	center.add_child(_form)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 22)
	_form.add_child(rows)

	_name_edit = LineEdit.new()
	_name_edit.name = "ServerNameEdit"
	_name_edit.max_length = 32
	_name_edit.placeholder_text = Net.default_server_name()
	_name_edit.text_submitted.connect(func(_text: String) -> void: _create())
	rows.add_child(_row("Server name", _field(_name_edit)))

	var players := HBoxContainer.new()
	players.add_theme_constant_override("separation", 18)
	_max_slider = HSlider.new()
	_max_slider.name = "MaxPlayersSlider"
	_max_slider.min_value = Net.MIN_PLAYERS
	_max_slider.max_value = Net.MAX_PLAYERS
	_max_slider.step = 1
	_max_slider.custom_minimum_size = Vector2(0, 48)
	_max_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_max_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	players.add_child(_max_slider)
	_max_label = MenuKit.label("", &"", 30)
	_max_label.custom_minimum_size = Vector2(150, 0)
	_max_label.add_theme_color_override("font_color", MenuKit.ACCENT)
	players.add_child(_max_label)
	_max_slider.value_changed.connect(func(value: float) -> void: _max_label.text = "%d players" % int(value))
	rows.add_child(_row("Max players", players))

	_password_edit = LineEdit.new()
	_password_edit.name = "PasswordEdit"
	_password_edit.secret = true
	_password_edit.max_length = 32
	_password_edit.placeholder_text = "Optional: empty = anyone can join"
	_password_edit.text_submitted.connect(func(_text: String) -> void: _create())
	rows.add_child(_row("Password", _field(_password_edit)))

	var visibility := VBoxContainer.new()
	visibility.add_theme_constant_override("separation", 10)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	visibility.add_child(tabs)
	var group := ButtonGroup.new()
	_listed_tab = _tab("Listed", group)
	_listed_tab.name = "ListedTab"
	_private_tab = _tab("Private", group)
	_private_tab.name = "PrivateTab"
	tabs.add_child(_listed_tab)
	tabs.add_child(_private_tab)
	_visibility_hint = MenuKit.label("", &"HintLabel", 22)
	_visibility_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	visibility.add_child(_visibility_hint)
	_listed_tab.toggled.connect(func(_on: bool) -> void: _update_hint())
	rows.add_child(_row("Who can find it", visibility))

	var info := PanelContainer.new()
	info.theme_type_variation = &"PanelInset"
	var info_text := MenuKit.label(_address_hint(), &"", 22)
	info_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(info_text)
	rows.add_child(info)

	var bottom: HBoxContainer = _frame.bottom
	var back := MenuKit.button("Back")
	back.name = "BackButton"
	back.pressed.connect(_go_to.bind(MENU_SCENE))
	bottom.add_child(back)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)
	var create := MenuKit.button("Create Lobby", true, Vector2(320, 80))
	create.name = "CreateButton"
	create.pressed.connect(_create)
	bottom.add_child(create)


## A form row: label on the left, the control filling the rest (stacked on phones).
func _row(text: String, control: Control) -> Control:
	var row := BoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.set_meta(&"form_row", true)
	var label := MenuKit.label(text, &"", 30)
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _field(edit: LineEdit) -> LineEdit:
	edit.custom_minimum_size = Vector2(0, 72)
	edit.add_theme_font_size_override("font_size", 30)
	return edit


func _tab(text: String, group: ButtonGroup) -> Button:
	var tab := Button.new()
	tab.theme_type_variation = &"ButtonTab"
	tab.toggle_mode = true
	tab.button_group = group
	tab.text = text
	tab.custom_minimum_size = Vector2(0, 68)
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return tab


func _update_hint() -> void:
	_visibility_hint.text = ("Shows up in Find Game for everyone on your Wi-Fi or network." if _listed_tab.button_pressed
			else "Hidden from Find Game: players join with Direct Connect and your address.")


func _address_hint() -> String:
	var addresses := Net.local_addresses()
	var address := ("%s:%d" % [addresses[0], Net.port]) if not addresses.is_empty() else "your IP address"
	return ("Your address: %s. Friends on the same network can use Direct Connect with it.\n"
			+ "Playing over the internet needs UDP port %d forwarded on your router.") % [address, Net.port]


func _load_options() -> void:
	var saved: Dictionary = Net.profile.get("host", {})
	_name_edit.text = str(saved.get("name", ""))
	_max_slider.value = int(saved.get("max_players", Net.MAX_PLAYERS))
	_max_label.text = "%d players" % int(_max_slider.value)
	(_listed_tab if bool(saved.get("listed", true)) else _private_tab).button_pressed = true
	_update_hint()


func _create() -> void:
	if _leaving:
		return
	var options := {
		"name": _name_edit.text.strip_edges(),
		"max_players": int(_max_slider.value),
		"password": _password_edit.text,
		"listed": _listed_tab.button_pressed,
	}
	Net.remember_host_options(options)
	var err := Net.host(options)
	if err != OK:
		_dialog = MenuKit.dialog($UI, "Couldn't host")
		var text := MenuKit.label("Port %d is busy. Is another game already open on this computer?" % Net.port, &"", 28)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		(_dialog.body as Control).add_child(text)
		var ok := MenuKit.button("OK", true)
		ok.pressed.connect(func() -> void:
			MenuKit.close_dialog(_dialog)
			_dialog = {})
		(_dialog.buttons as Control).add_child(ok)
		ok.grab_focus.call_deferred()
		return
	_go_to(LOBBY_SCENE)


func _go_to(path: String) -> void:
	if _leaving or not is_inside_tree():
		return
	_leaving = true
	get_tree().change_scene_to_file(path)


## Phones: the form fills the width and every label sits above its control.
func _layout() -> void:
	var compact := MenuKit.is_compact(_form)
	var width := get_viewport().get_visible_rect().size.x
	_form.custom_minimum_size.x = (width - 32.0) if compact else FORM_WIDTH
	for row in _form.find_children("*", "BoxContainer", true, false):
		if row.has_meta(&"form_row"):
			(row as BoxContainer).vertical = compact
