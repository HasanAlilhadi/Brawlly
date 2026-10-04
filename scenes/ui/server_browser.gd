extends Node
## Server browser (main menu → Find Game): a table of the games hosted on your network (Net discovery), with
## search, "Hide full" / "Hide in progress" filters and Refresh. Click a row to select it, double-click or Join
## to join; locked games ask for their password. Direct Connect joins by "ip" or "ip:port" (recent addresses
## are remembered). Joining shows a Connecting… window; refusals ("That game is full.") show why.

const LOBBY_SCENE := "res://scenes/ui/lobby.tscn"
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const HOST_SCENE := "res://scenes/ui/host_menu.tscn"
const CONNECT_TIMEOUT: float = 8.0
const ROW_HEIGHT: float = 72.0
## Table columns: key, title, stretch ratio (0 = fixed `width`), shown on phones.
const COLUMNS := [
	{"key": "name", "title": "Server", "ratio": 3.0, "compact": true},
	{"key": "host", "title": "Host", "ratio": 1.6, "compact": false},
	{"key": "mode", "title": "Mode", "ratio": 1.8, "compact": false},
	{"key": "players", "title": "Players", "ratio": 0.0, "width": 150.0, "compact": true},
	{"key": "status", "title": "Status", "ratio": 0.0, "width": 180.0, "compact": false},
]

var _frame: Dictionary
var _search: LineEdit
var _hide_full: Button
var _hide_playing: Button
var _header: HBoxContainer
var _scroll: ScrollContainer
var _list: VBoxContainer
var _empty: Control
var _status: Label
var _join_button: Button
var _direct_button: Button
var _rows: Dictionary = {}  # "ip:port" -> row Button
var _row_group := ButtonGroup.new()
var _selected: String = ""
var _dialog: Dictionary = {}
var _connecting: float = 0.0
var _pending: Dictionary = {}  # the game being joined: {"address", "name", "direct"}
var _discovery_ok: bool = true
var _leaving: bool = false


func _ready() -> void:
	get_tree().paused = false
	_build()
	Net.servers_changed.connect(_refresh_list)
	Net.connection_failed.connect(_on_connection_failed)
	Net.lobby_changed.connect(_on_lobby_changed)
	get_viewport().size_changed.connect(_layout)
	_refresh()
	_layout()


func _exit_tree() -> void:
	Net.stop_discovery()


func _process(delta: float) -> void:
	if _connecting > 0.0:
		_connecting -= delta
		if _connecting <= 0.0:
			Net.close_connection()
			_message("Couldn't join", "Could not reach %s. Check the address, and that the host's game is still open." % _pending.get("name", "that game"))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if not _dialog.is_empty():
			if _connecting > 0.0:
				_cancel_connect()
			else:
				_close_dialog()
		else:
			_back()


# --- Building -------------------------------------------------------------------------

func _build() -> void:
	_frame = MenuKit.frame($UI, "Find a Game")
	var tools: HBoxContainer = _frame.tools
	_search = LineEdit.new()
	_search.name = "SearchEdit"
	_search.placeholder_text = "Search games"
	_search.custom_minimum_size = Vector2(320, 64)
	_search.add_theme_font_size_override("font_size", 26)
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_text: String) -> void: _refresh_list())
	tools.add_child(_search)
	_hide_full = _filter_toggle("Hide full")
	_hide_playing = _filter_toggle("Hide in progress")
	tools.add_child(_hide_full)
	tools.add_child(_hide_playing)

	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	(_frame.body as Control).add_child(panel)
	var table := VBoxContainer.new()
	table.add_theme_constant_override("separation", 10)
	panel.add_child(table)
	var header_bar := PanelContainer.new()
	header_bar.theme_type_variation = &"PanelBrown"
	table.add_child(header_bar)
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 16)
	header_bar.add_child(_header)
	for column in COLUMNS:
		_header.add_child(_cell(column, column.title, &"LabelLight"))
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	table.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.name = "ServerList"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list)
	_empty = _build_empty_state()
	_empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table.add_child(_empty)

	var bottom: HBoxContainer = _frame.bottom
	var back := MenuKit.button("Back")
	back.name = "BackButton"
	back.pressed.connect(_back)
	bottom.add_child(back)
	_status = MenuKit.label("", &"LabelLight", 26)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(_status)
	var refresh := MenuKit.button("Refresh")
	refresh.name = "RefreshButton"
	refresh.icon = MenuKit.ICON_REFRESH
	refresh.expand_icon = true
	refresh.add_theme_constant_override("icon_max_width", 34)
	refresh.add_theme_color_override("icon_normal_color", UiKit.PROMPT_INK)
	refresh.pressed.connect(_refresh)
	bottom.add_child(refresh)
	_direct_button = MenuKit.button("Direct Connect", false, Vector2(260, 80))
	_direct_button.name = "DirectButton"
	_direct_button.pressed.connect(_ask_address)
	bottom.add_child(_direct_button)
	_join_button = MenuKit.button("Join", true, Vector2(220, 80))
	_join_button.name = "JoinButton"
	_join_button.pressed.connect(func() -> void: _join_server(_selected))
	bottom.add_child(_join_button)


func _filter_toggle(text: String) -> Button:
	var toggle := Button.new()
	toggle.theme_type_variation = &"ButtonTab"
	toggle.toggle_mode = true
	toggle.text = text
	toggle.custom_minimum_size = Vector2(0, 64)
	toggle.add_theme_font_size_override("font_size", 24)
	toggle.toggled.connect(func(_on: bool) -> void: _refresh_list())
	return toggle


func _build_empty_state() -> Control:
	var center := CenterContainer.new()
	center.name = "EmptyState"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	var title := MenuKit.label("No games found yet", &"HeaderLabel")
	title.name = "EmptyTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var hint := MenuKit.label("Games hosted on the same Wi-Fi or network show up here by themselves.\n"
			+ "Somewhere else? Ask the host for their address and use Direct Connect.", &"HintLabel", 24)
	hint.name = "EmptyHint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(minf(760, get_viewport().get_visible_rect().size.x - 80), 0)
	box.add_child(hint)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 14)
	box.add_child(buttons)
	var host := MenuKit.button("Host a Game", true, Vector2(260, 80))
	host.pressed.connect(_go_to.bind(HOST_SCENE))
	buttons.add_child(host)
	var direct := MenuKit.button("Direct Connect", false, Vector2(260, 80))
	direct.pressed.connect(_ask_address)
	buttons.add_child(direct)
	return center


## One table cell, sized like its column header.
func _cell(column: Dictionary, text: String, variation: StringName = &"") -> Label:
	var cell := MenuKit.label(text, variation, 26)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.clip_text = true
	cell.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cell.set_meta(&"column", column.key)
	if column.ratio > 0.0:
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_stretch_ratio = column.ratio
	else:
		cell.custom_minimum_size = Vector2(column.width, 0)
		cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return cell


# --- List -----------------------------------------------------------------------------------

## Refresh: forget the list and listen again.
func _refresh() -> void:
	_discovery_ok = Net.start_discovery()
	_refresh_list()


func _visible_servers() -> Array:
	var query := _search.text.strip_edges().to_lower()
	var keys := []
	for key: String in Net.servers:
		var info: Dictionary = Net.servers[key]
		if _hide_full.button_pressed and int(info.get("players", 0)) >= int(info.get("max", Net.MAX_PLAYERS)):
			continue
		if _hide_playing.button_pressed and bool(info.get("in_game", false)):
			continue
		if query != "" and not (str(info.get("name", "")).to_lower().contains(query)
				or str(info.get("host", "")).to_lower().contains(query)):
			continue
		keys.append(key)
	# Joinable games first, then the busiest, then by name.
	keys.sort_custom(func(a: String, b: String) -> bool:
		var ia: Dictionary = Net.servers[a]
		var ib: Dictionary = Net.servers[b]
		if _joinable(ia) != _joinable(ib):
			return _joinable(ia)
		if int(ia.get("players", 0)) != int(ib.get("players", 0)):
			return int(ia.get("players", 0)) > int(ib.get("players", 0))
		return str(ia.get("name", "")).naturalnocasecmp_to(str(ib.get("name", ""))) < 0)
	return keys


func _joinable(info: Dictionary) -> bool:
	return not bool(info.get("in_game", false)) and int(info.get("players", 0)) < int(info.get("max", Net.MAX_PLAYERS))


func _refresh_list() -> void:
	var keys := _visible_servers()
	for key: String in _rows.keys():
		if not keys.has(key):
			(_rows[key] as Node).queue_free()
			_rows.erase(key)
	for i in keys.size():
		var key: String = keys[i]
		if not _rows.has(key):
			_rows[key] = _make_row(key)
			_list.add_child(_rows[key])
		_list.move_child(_rows[key], i)
		_fill_row(_rows[key], Net.servers[key])
	if not _rows.has(_selected):
		_selected = ""
	_scroll.visible = not keys.is_empty()
	_empty.visible = keys.is_empty()
	var empty_title := _empty.find_child("EmptyTitle", true, false) as Label
	if Net.servers.is_empty():
		empty_title.text = "Searching your network…" if _discovery_ok else "Can't search the network here"
	else:
		empty_title.text = "No games match your filters"
	var count := Net.servers.size()
	if not _discovery_ok:
		_status.text = "Use Direct Connect with the host's address."
	elif count == 0:
		_status.text = "Looking for games…"
	else:
		_status.text = "%d game%s found" % [count, "" if count == 1 else "s"]
	_update_join_button()


func _make_row(key: String) -> Button:
	var row := Button.new()
	row.name = "Server_" + key.validate_node_name()
	row.theme_type_variation = &"ButtonTab"
	row.toggle_mode = true
	row.button_group = _row_group
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.set_meta(&"key", key)
	var cells := HBoxContainer.new()
	cells.name = "Cells"
	cells.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cells.offset_left = 18
	cells.offset_right = -18
	cells.add_theme_constant_override("separation", 16)
	cells.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(cells)
	var name_box := HBoxContainer.new()
	name_box.name = "NameBox"
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.size_flags_stretch_ratio = COLUMNS[0].ratio
	name_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_box.add_theme_constant_override("separation", 8)
	name_box.set_meta(&"column", "name")
	cells.add_child(name_box)
	var lock := MenuKit.icon(MenuKit.ICON_LOCK, 30, UiKit.PROMPT_INK)
	lock.name = "Lock"
	name_box.add_child(lock)
	var name_cell := _cell(COLUMNS[0], "")
	name_cell.name = "Name"
	name_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.add_child(name_cell)
	for i in range(1, COLUMNS.size()):
		var cell := _cell(COLUMNS[i], "")
		cell.name = String(COLUMNS[i].key).capitalize()
		cells.add_child(cell)
	row.toggled.connect(func(on: bool) -> void:
		if on:
			_selected = key
		_update_join_button()
		_style_row(row))
	row.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click and click.double_click and click.button_index == MOUSE_BUTTON_LEFT:
			_selected = key
			_join_server(key))
	_layout_row(row)
	return row


func _fill_row(row: Button, info: Dictionary) -> void:
	var cells := row.get_node("Cells")
	(cells.get_node("NameBox/Name") as Label).text = str(info.get("name", "?"))
	(cells.get_node("NameBox/Lock") as Control).visible = bool(info.get("locked", false))
	(cells.get_node("Host") as Label).text = str(info.get("host", ""))
	(cells.get_node("Mode") as Label).text = Net.MODE_NAMES[clampi(int(info.get("mode", 0)), 0, Net.MODE_NAMES.size() - 1)]
	(cells.get_node("Players") as Label).text = "%d / %d" % [int(info.get("players", 0)), int(info.get("max", Net.MAX_PLAYERS))]
	var status := "In lobby"
	if bool(info.get("in_game", false)):
		status = "In match"
	elif int(info.get("players", 0)) >= int(info.get("max", Net.MAX_PLAYERS)):
		status = "Full"
	(cells.get_node("Status") as Label).text = status
	row.set_meta(&"joinable", _joinable(info))
	row.tooltip_text = "%s:%d" % [info.get("ip", ""), int(info.get("port", Net.PORT))]
	_style_row(row)


## Selected rows are dark wood with light text; games you can't join are faded.
func _style_row(row: Button) -> void:
	var light := row.button_pressed
	for cell in row.get_node("Cells").find_children("*", "Label", true, false):
		var label := cell as Label
		label.theme_type_variation = &"LabelLight" if light else &""
		if not light and label.name == "Status":
			label.add_theme_color_override("font_color", MenuKit.GOOD if row.get_meta(&"joinable", true) else MenuKit.BAD)
		else:
			label.remove_theme_color_override("font_color")
	var lock := row.get_node("Cells/NameBox/Lock") as TextureRect
	lock.self_modulate = Color.WHITE if light else UiKit.PROMPT_INK
	row.modulate.a = 1.0 if row.get_meta(&"joinable", true) else 0.65


func _update_join_button() -> void:
	var info: Dictionary = Net.servers.get(_selected, {})
	_join_button.disabled = info.is_empty() or not _joinable(info) or _connecting > 0.0


# --- Joining ----------------------------------------------------------------------------

func _join_server(key: String) -> void:
	var info: Dictionary = Net.servers.get(key, {})
	if info.is_empty():
		return
	if bool(info.get("in_game", false)):
		_message("Match in progress", "%s is already playing. Join when they are back in the lobby." % info.get("name", "That game"))
		return
	if not _joinable(info):
		_message("Game full", "%s has no free slots." % info.get("name", "That game"))
		return
	var target := {"address": "%s:%d" % [info.ip, int(info.port)], "name": str(info.get("name", "the game")), "direct": false}
	if bool(info.get("locked", false)):
		_ask_password(target, "")
	else:
		_connect(target, "")


func _connect(target: Dictionary, password: String) -> void:
	_close_dialog()
	_pending = target
	if Net.join(target.address, -1, password) != OK:
		_message("Couldn't join", "\"%s\" isn't an address. Use the host's IP, like 192.168.1.20 or 192.168.1.20:%d." % [target.address, Net.PORT])
		return
	_connecting = CONNECT_TIMEOUT
	_update_join_button()
	_dialog = MenuKit.dialog($UI, "Joining")
	var text := MenuKit.label("Connecting to %s…" % target.name, &"", 30)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	(_dialog.body as Control).add_child(text)
	var cancel := MenuKit.button("Cancel")
	cancel.name = "CancelButton"
	cancel.pressed.connect(_cancel_connect)
	(_dialog.buttons as Control).add_child(cancel)
	cancel.grab_focus.call_deferred()


func _cancel_connect() -> void:
	_connecting = 0.0
	Net.close_connection()
	_close_dialog()
	_update_join_button()


func _on_lobby_changed() -> void:
	if Net.is_online() and Net.players.has(Net.my_id()):
		if bool(_pending.get("direct", false)):
			Net.add_recent_address(_pending.address)
		_go_to(LOBBY_SCENE)


func _on_connection_failed(reason: String) -> void:
	if _connecting <= 0.0 and _pending.is_empty():
		return
	_connecting = 0.0
	if reason == Net.WRONG_PASSWORD:
		_ask_password(_pending, "Wrong password. Try again.")
		return
	_message("Couldn't join", reason)


# --- Dialogs ---------------------------------------------------------------------------------

func _ask_address() -> void:
	_close_dialog()
	_dialog = MenuKit.dialog($UI, "Direct Connect")
	var body: VBoxContainer = _dialog.body
	var hint := MenuKit.label("Type the host's address. The host sees it at the top of their lobby.", &"HintLabel", 24)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(hint)
	var address := LineEdit.new()
	address.name = "IpEdit"
	address.placeholder_text = "192.168.1.20 or 192.168.1.20:%d" % Net.PORT
	address.custom_minimum_size = Vector2(0, 76)
	address.add_theme_font_size_override("font_size", 30)
	address.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
	body.add_child(address)
	var error := MenuKit.label("", &"", 24)
	error.add_theme_color_override("font_color", MenuKit.BAD)
	error.visible = false
	body.add_child(error)
	var recent: Array = Net.profile.get("recent", [])
	if not recent.is_empty():
		body.add_child(MenuKit.label("Recent", &"HeaderLabel", 28))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 10)
		flow.add_theme_constant_override("v_separation", 10)
		body.add_child(flow)
		for entry: String in recent:
			var chip := MenuKit.button(entry, false, Vector2(0, 64))
			chip.add_theme_font_size_override("font_size", 24)
			chip.pressed.connect(func() -> void: address.text = entry)
			flow.add_child(chip)
	var submit := func() -> void:
		if Net.parse_address(address.text).is_empty():
			error.text = "That doesn't look like an address."
			error.visible = true
			return
		var text := address.text.strip_edges()
		_connect({"address": text, "name": text, "direct": true}, "")
	address.text_submitted.connect(func(_text: String) -> void: submit.call())
	var cancel := MenuKit.button("Cancel")
	cancel.pressed.connect(_close_dialog)
	(_dialog.buttons as Control).add_child(cancel)
	var connect_button := MenuKit.button("Connect", true)
	connect_button.name = "ConnectButton"
	connect_button.pressed.connect(submit)
	(_dialog.buttons as Control).add_child(connect_button)
	address.grab_focus.call_deferred()


func _ask_password(target: Dictionary, error_text: String) -> void:
	_close_dialog()
	_pending = target
	_dialog = MenuKit.dialog($UI, "Password needed")
	var body: VBoxContainer = _dialog.body
	var hint := MenuKit.label("%s is locked. Ask the host for the password." % target.name, &"HintLabel", 24)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(hint)
	var password := LineEdit.new()
	password.name = "PasswordEdit"
	password.secret = true
	password.placeholder_text = "Password"
	password.custom_minimum_size = Vector2(0, 76)
	password.add_theme_font_size_override("font_size", 30)
	body.add_child(password)
	if error_text != "":
		var error := MenuKit.label(error_text, &"", 24)
		error.add_theme_color_override("font_color", MenuKit.BAD)
		body.add_child(error)
	password.text_submitted.connect(func(text: String) -> void: _connect(target, text))
	var cancel := MenuKit.button("Cancel")
	cancel.pressed.connect(func() -> void:
		_pending = {}
		_close_dialog())
	(_dialog.buttons as Control).add_child(cancel)
	var join := MenuKit.button("Join", true)
	join.name = "PasswordJoinButton"
	join.pressed.connect(func() -> void: _connect(target, password.text))
	(_dialog.buttons as Control).add_child(join)
	password.grab_focus.call_deferred()


func _message(title: String, text: String) -> void:
	_close_dialog()
	_dialog = MenuKit.dialog($UI, title)
	var label := MenuKit.label(text, &"", 28)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	(_dialog.body as Control).add_child(label)
	var ok := MenuKit.button("OK", true)
	ok.name = "OkButton"
	ok.pressed.connect(_close_dialog)
	(_dialog.buttons as Control).add_child(ok)
	ok.grab_focus.call_deferred()


func _close_dialog() -> void:
	MenuKit.close_dialog(_dialog)
	_dialog = {}
	_update_join_button()


# --- Navigation / layout ------------------------------------------------------------------------

func _back() -> void:
	_cancel_connect()
	_go_to(MENU_SCENE)


## Changes scene once (the tree is gone right after a change starts).
func _go_to(path: String) -> void:
	if _leaving or not is_inside_tree():
		return
	_leaving = true
	_connecting = 0.0
	get_tree().change_scene_to_file(path)


## Phones: the filters go under the title, the Host / Mode / Status columns hide, buttons shrink.
func _layout() -> void:
	var compact := MenuKit.is_compact(_list)
	var tools: Control = _frame.tools
	var wanted_parent: Node = _frame.body if compact else _frame.top
	if tools.get_parent() != wanted_parent:
		tools.reparent(wanted_parent, false)
		wanted_parent.move_child(tools, 0 if compact else -1)
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL if compact else Control.SIZE_FILL
	_search.custom_minimum_size.x = 0.0 if compact else 320.0
	for child in _header.get_children():
		_show_column(child)
	for row: Button in _rows.values():
		_layout_row(row)
	for button in (_frame.bottom as Control).get_children():
		if button is Button:
			if not button.has_meta(&"wide_width"):
				button.set_meta(&"wide_width", (button as Button).custom_minimum_size.x)
			(button as Button).custom_minimum_size.x = 0.0 if compact else float(button.get_meta(&"wide_width"))
			(button as Button).add_theme_font_size_override("font_size", 26 if compact else 32)
	_direct_button.text = "Direct" if compact else "Direct Connect"
	_status.visible = not compact


func _layout_row(row: Button) -> void:
	for child in row.get_node("Cells").get_children():
		_show_column(child)


func _show_column(cell: Node) -> void:
	var key: String = cell.get_meta(&"column", "")
	for column in COLUMNS:
		if column.key == key:
			(cell as Control).visible = column.compact or not MenuKit.is_compact(_list)
