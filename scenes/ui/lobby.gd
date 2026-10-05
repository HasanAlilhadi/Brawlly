extends Node
## Lobby of a multiplayer match, in two columns (stacked on phones):
## - left: the players — one slot per seat up to the server's max (host crown, class, team, Ready), with
##   Kick for the host; team buttons in team modes.
## - right: your hero (ArmyPreview + ClassPicker), then the match settings — editable for the host, a plain
##   summary for everyone else.
## The title is the server name; the invite address (with Copy) sits top right. Bottom: Leave, then Ready
## (joined players) or Start (host, with the ready count). Everything comes from Net.players / Net.settings /
## Net.server_info and refreshes on Net.lobby_changed.

## Score limit range / default per mode (index = Net.Mode).
const SCORE_LIMITS := [
	Vector3i(0, 0, 0),       # co-op: not used
	Vector3i(30, 300, 120),  # king of the hill: seconds held
	Vector3i(0, 0, 0),       # last stand: not used (ten circles)
]
const PLAYERS_WIDTH: float = 700.0
const SLOT_HEIGHT: float = 70.0
const CROWN_COLOR := Color("e0a830")

var _frame: Dictionary
var _invite_label: Label
var _copy_button: Button
var _lock_icon: TextureRect
var _columns: BoxContainer
var _players_panel: PanelContainer
var _player_count: Label
var _player_list: VBoxContainer
var _team_box: VBoxContainer
var _team_row: HBoxContainer
var _settings_box: VBoxContainer
var _summary: VBoxContainer  # read-only settings for joined players
var _status: Label
var _leave_button: Button
var _ready_button: Button
var _start_button: Button

var _updating: bool = false
var _mode_option: OptionButton
var _mode_hint: Label
var _map_option: OptionButton
var _map_hint: Label
var _difficulty_option: OptionButton
var _events_option: OptionButton
var _sliders: Dictionary = {}  # key -> {slider, value_label, row}
var _countdown_overlay: Control
var _countdown_number: Label
var _class_picker: ClassPicker
var _preview: ArmyPreview


func _ready() -> void:
	get_tree().paused = false
	_build()
	_build_settings()
	Net.lobby_changed.connect(_refresh)
	Net.countdown_started.connect(_show_countdown)
	get_viewport().size_changed.connect(_layout)
	_build_countdown_overlay()
	_layout()
	_refresh()
	if Net.game_in_progress and Net.countdown_remaining() > 0:
		_show_countdown(Net.countdown_remaining())  # opened after the countdown began


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _countdown_overlay.visible:
		get_viewport().set_input_as_handled()
		Net.leave()


# --- Building ------------------------------------------------------------------------

func _build() -> void:
	_frame = MenuKit.frame($UI, "Lobby")
	var tools: HBoxContainer = _frame.tools
	_lock_icon = MenuKit.icon(MenuKit.ICON_LOCK, 36)
	_lock_icon.tooltip_text = "Password protected"
	_lock_icon.mouse_filter = Control.MOUSE_FILTER_PASS
	tools.add_child(_lock_icon)
	_invite_label = MenuKit.label("", &"LabelLight", 28)
	_invite_label.name = "InviteLabel"
	tools.add_child(_invite_label)
	_copy_button = MenuKit.button("Copy", false, Vector2(130, 64))
	_copy_button.name = "CopyButton"
	_copy_button.add_theme_font_size_override("font_size", 26)
	_copy_button.pressed.connect(_copy_invite)
	tools.add_child(_copy_button)

	_columns = BoxContainer.new()
	_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_columns.add_theme_constant_override("separation", 18)
	(_frame.body as Control).add_child(_columns)

	# Left: players
	_players_panel = PanelContainer.new()
	_columns.add_child(_players_panel)
	var players := VBoxContainer.new()
	players.add_theme_constant_override("separation", 10)
	_players_panel.add_child(players)
	var header := HBoxContainer.new()
	players.add_child(header)
	var title := MenuKit.label("Players", &"HeaderLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_player_count = MenuKit.label("", &"HeaderLabel")
	_player_count.name = "PlayerCount"
	header.add_child(_player_count)
	var list_scroll := ScrollContainer.new()
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	players.add_child(list_scroll)
	_player_list = VBoxContainer.new()
	_player_list.name = "PlayerList"
	_player_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_player_list.add_theme_constant_override("separation", 8)
	list_scroll.add_child(_player_list)
	_team_box = VBoxContainer.new()
	_team_box.add_theme_constant_override("separation", 8)
	players.add_child(_team_box)
	_team_box.add_child(MenuKit.label("Teams", &"HeaderLabel", 30))
	_team_row = HBoxContainer.new()
	_team_row.name = "TeamRow"
	_team_row.add_theme_constant_override("separation", 8)
	_team_box.add_child(_team_row)

	# Right: your hero + match settings
	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_columns.add_child(right)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	scroll.add_child(box)
	box.add_child(MenuKit.label("Your hero", &"HeaderLabel"))
	_preview = ArmyPreview.new()
	_preview.custom_minimum_size = Vector2(0, 170)
	_preview.set_color(Net.SELF_COLOR)
	box.add_child(_preview)
	_class_picker = ClassPicker.new()
	box.add_child(_class_picker)
	_class_picker.picked.connect(func(class_id: StringName) -> void:
		if not Net.game_in_progress:
			Net.set_class(class_id))
	box.add_child(HSeparator.new())
	box.add_child(MenuKit.label("Match settings", &"HeaderLabel"))
	_settings_box = VBoxContainer.new()
	_settings_box.name = "SettingsBox"
	_settings_box.add_theme_constant_override("separation", 14)
	box.add_child(_settings_box)
	_summary = VBoxContainer.new()
	_summary.add_theme_constant_override("separation", 6)
	box.add_child(_summary)

	# Bottom: Leave · status · Ready / Start
	var bottom: HBoxContainer = _frame.bottom
	_leave_button = MenuKit.button("Leave", false, Vector2(220, 88))
	_leave_button.name = "LeaveButton"
	_leave_button.pressed.connect(func() -> void: Net.leave())
	bottom.add_child(_leave_button)
	_status = MenuKit.label("", &"LabelLight", 28)
	_status.name = "Waiting"
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(_status)
	_ready_button = MenuKit.button("Ready", true, Vector2(300, 88))
	_ready_button.name = "ReadyButton"
	_ready_button.toggle_mode = true
	_ready_button.toggled.connect(func(on: bool) -> void:
		if not _updating:
			Net.set_ready(on))
	bottom.add_child(_ready_button)
	_start_button = MenuKit.button("Start", true, Vector2(340, 88))
	_start_button.name = "StartButton"
	_start_button.pressed.connect(func() -> void: Net.start_game())
	bottom.add_child(_start_button)


## Big "3… 2… 1…" over the lobby on every player's screen once the host presses Start.
func _build_countdown_overlay() -> void:
	_countdown_overlay = ColorRect.new()
	(_countdown_overlay as ColorRect).color = Color(0, 0, 0, 0.55)
	_countdown_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_countdown_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_countdown_overlay.visible = false
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_countdown_overlay.add_child(box)
	_countdown_number = Label.new()
	_countdown_number.theme_type_variation = &"TitleLabel"
	_countdown_number.add_theme_font_size_override("font_size", 170)
	_countdown_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_countdown_number)
	var ready_label := Label.new()
	ready_label.theme_type_variation = &"LabelLight"
	ready_label.text = "Get ready!"
	ready_label.add_theme_font_size_override("font_size", 40)
	ready_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(ready_label)
	$UI.add_child(_countdown_overlay)


func _show_countdown(seconds: int) -> void:
	_refresh()
	_countdown_overlay.visible = true
	for remaining in range(seconds, 0, -1):
		if not is_inside_tree():
			return
		_countdown_number.text = str(remaining)
		_countdown_number.pivot_offset = _countdown_number.size * 0.5
		_countdown_number.scale = Vector2.ONE * 1.6
		_countdown_number.modulate.a = 0.0
		var tween := create_tween().set_parallel(true)
		tween.tween_property(_countdown_number, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(_countdown_number, "modulate:a", 1.0, 0.2)
		await get_tree().create_timer(1.0).timeout


func _copy_invite() -> void:
	DisplayServer.clipboard_set(Net.invite_address())
	_copy_button.text = "Copied!"
	get_tree().create_timer(1.5).timeout.connect(func() -> void:
		if is_instance_valid(_copy_button):
			_copy_button.text = "Copy")


func _can_edit() -> bool:
	return Net.is_host() and not Net.game_in_progress


# --- Settings controls ------------------------------------------------------------

func _summary_row(label_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()
	var label := MenuKit.label(label_text, &"", 26)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var value := MenuKit.label(value_text, &"", 26)
	value.add_theme_color_override("font_color", MenuKit.ACCENT)
	row.add_child(value)
	_summary.add_child(row)


func _refresh_summary(settings: Dictionary) -> void:
	for child in _summary.get_children():
		child.queue_free()
	var match_mode: int = settings.mode
	_summary_row("Mode", Net.MODE_NAMES[match_mode])
	var hint := MenuKit.label(Net.MODE_HINTS[match_mode], &"HintLabel", 20)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.add_child(hint)
	var map := MapCatalog.get_map(int(settings.get("map", 0)))
	_summary_row("Map", map.name)
	var map_hint := MenuKit.label(map.hint, &"HintLabel", 20)
	map_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.add_child(map_hint)
	_summary_row("Orc camps", str(settings.camp_count))
	_summary_row("Difficulty", Net.DIFFICULTY_NAMES[settings.difficulty])
	_summary_row("World events", "On" if settings.get("events", true) else "Off")
	_summary_row("Starting coins", str(settings.start_coins))
	if Net.is_team_mode(match_mode):
		_summary_row("Teams", str(settings.team_count))
	if match_mode == Net.Mode.KING_OF_THE_HILL:
		_summary_row(Net.SCORE_LIMIT_LABELS[match_mode], str(settings.score_limit))
		_summary_row("Time limit", "%d min" % settings.time_limit)


func _build_settings() -> void:
	_mode_option = _add_option("Mode", Net.MODE_NAMES, func(index: int) -> void:
		Net.set_setting("mode", index)
		var limits: Vector3i = SCORE_LIMITS[index]
		if limits.y > 0:
			Net.set_setting("score_limit", limits.z))
	_mode_hint = MenuKit.label("", &"HintLabel", 22)
	_mode_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_settings_box.add_child(_mode_hint)
	_map_option = _add_option("Map", MapCatalog.names(), func(index: int) -> void:
		Net.set_setting("map", index))
	_map_option.name = "MapOption"
	_map_hint = MenuKit.label("", &"HintLabel", 22)
	_map_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_settings_box.add_child(_map_hint)
	_add_slider("camp_count", "Orc camps", 0, 60, 1)
	_difficulty_option = _add_option("Difficulty", Net.DIFFICULTY_NAMES, func(index: int) -> void:
		Net.set_setting("difficulty", index))
	_events_option = _add_option("World events", PackedStringArray(["On: goblin + Warlord + Waves", "Off"]), func(index: int) -> void:
		Net.set_setting("events", index == 0))
	_add_slider("start_coins", "Starting coins", 0, 1000, 50)
	_add_slider("team_count", "Teams", 2, 4, 1)
	_add_slider("score_limit", "Score to win", 1, 50, 1)
	_add_slider("time_limit", "Time limit (minutes)", 3, 30, 1)


func _add_option(label_text: String, items: PackedStringArray, on_select: Callable) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_settings_box.add_child(row)
	var label := MenuKit.label(label_text)
	label.custom_minimum_size = Vector2(160 if MenuKit.is_compact(_settings_box) else 230, 0)
	row.add_child(label)
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.custom_minimum_size = Vector2(0, 72)
	option.add_theme_font_size_override("font_size", 26)
	option.fit_to_longest_item = false  # phones: never wider than the column
	option.clip_text = true
	for item in items:
		option.add_item(item)
	option.item_selected.connect(func(index: int) -> void:
		if not _updating:
			on_select.call(index))
	row.add_child(option)
	return option


func _add_slider(key: String, label_text: String, min_value: float, max_value: float, step: float) -> void:
	var row := VBoxContainer.new()
	_settings_box.add_child(row)
	var header := HBoxContainer.new()
	row.add_child(header)
	var label := MenuKit.label(label_text)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)
	var value_label := MenuKit.label("")
	value_label.add_theme_color_override("font_color", MenuKit.ACCENT)
	header.add_child(value_label)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.custom_minimum_size = Vector2(0, 48)
	slider.value_changed.connect(func(value: float) -> void:
		value_label.text = str(int(value))
		if not _updating:
			Net.set_setting(key, int(value)))
	row.add_child(slider)
	_sliders[key] = {"slider": slider, "value": value_label, "row": row, "label": label}


# --- Refresh from Net ------------------------------------------------------------------

func _refresh() -> void:
	if not multiplayer.has_multiplayer_peer() or Net.players.is_empty():
		return
	_updating = true
	var settings := Net.settings
	var match_mode: int = settings.mode
	var team_mode := Net.is_team_mode(match_mode)
	var max_players := int(Net.server_info.get("max_players", Net.MAX_PLAYERS))

	(_frame.title as Label).text = str(Net.server_info.get("name", "Lobby"))
	var invite := Net.invite_address()
	_invite_label.text = ("Invite: " + invite) if invite != "" else ""
	_copy_button.visible = invite != ""
	_lock_icon.visible = bool(Net.server_info.get("locked", false))

	# Players: one slot per seat
	for child in _player_list.get_children():
		child.queue_free()
	var peers := Net.players.keys()
	peers.sort()
	for peer in peers:
		_player_list.add_child(_player_row(peer, team_mode))
	if not MenuKit.is_compact(_player_list):
		for i in maxi(max_players - peers.size(), 0):
			_player_list.add_child(_open_slot())
	_player_count.text = "%d / %d" % [peers.size(), max_players]

	# Team buttons
	for child in _team_row.get_children():
		child.queue_free()
	_team_box.visible = team_mode
	if team_mode:
		for team in settings.team_count:
			var button := Button.new()
			var mine: bool = Net.players.get(Net.my_id(), {}).get("team", -1) == team
			button.text = "Your team" if mine else "Join %s" % Net.team_label(team)
			button.theme_type_variation = &"ButtonBeige"
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.custom_minimum_size = Vector2(0, 68)
			button.add_theme_font_size_override("font_size", 24)
			button.add_theme_color_override("font_color", Net.team_color(team).darkened(0.3))
			button.add_theme_color_override("font_disabled_color", Net.team_color(team).darkened(0.3))
			button.disabled = mine or Net.game_in_progress
			button.pressed.connect(Net.request_team.bind(team))
			_team_row.add_child(button)

	# Settings: controls for the host, a plain summary for everyone else
	var editable := _can_edit()
	_settings_box.visible = editable
	_summary.visible = not editable
	if not editable:
		_refresh_summary(settings)
	_mode_option.select(match_mode)
	_mode_option.disabled = not editable
	_mode_hint.text = Net.MODE_HINTS[match_mode]
	var map_index := clampi(int(settings.get("map", 0)), 0, MapCatalog.MAPS.size() - 1)
	_map_option.select(map_index)
	_map_option.disabled = not editable
	_map_hint.text = MapCatalog.get_map(map_index).hint
	_difficulty_option.select(settings.difficulty)
	_difficulty_option.disabled = not editable
	_events_option.select(0 if settings.get("events", true) else 1)
	_events_option.disabled = not editable
	for key in _sliders:
		var entry: Dictionary = _sliders[key]
		var slider: HSlider = entry.slider
		slider.editable = editable
		if key == "score_limit":
			var limits: Vector3i = SCORE_LIMITS[match_mode]
			slider.min_value = maxi(limits.x, 1)
			slider.max_value = maxi(limits.y, 1)
			slider.step = 10 if match_mode == Net.Mode.KING_OF_THE_HILL else 1
			(entry.label as Label).text = Net.SCORE_LIMIT_LABELS[match_mode]
		slider.value = settings.get(key, slider.min_value)
		(entry.value as Label).text = str(int(slider.value))
	(_sliders.team_count.row as Control).visible = team_mode
	(_sliders.score_limit.row as Control).visible = match_mode == Net.Mode.KING_OF_THE_HILL
	(_sliders.time_limit.row as Control).visible = match_mode == Net.Mode.KING_OF_THE_HILL

	# Bottom row
	var host := Net.is_host()
	var my_ready := Net.is_ready(Net.my_id())
	_start_button.visible = host
	_start_button.disabled = Net.game_in_progress
	_ready_button.visible = not host
	_ready_button.disabled = Net.game_in_progress
	_ready_button.button_pressed = my_ready
	_ready_button.text = "Ready!" if my_ready else "Ready up"
	var ready_players := Net.ready_count()
	if Net.game_in_progress:
		_status.text = "Starting…"
	elif host:
		if ready_players.y == 0:
			_status.text = "Waiting for players. You can also start alone."
		elif ready_players.x == ready_players.y:
			_status.text = "Everyone is ready!"
		else:
			_status.text = "%d / %d players ready" % [ready_players.x, ready_players.y]
	else:
		_status.text = "Waiting for the host to start…" if my_ready else "Pick your hero, then ready up."
	_class_picker.select(Net.class_of(Net.my_id()))
	_preview.set_class(Net.class_of(Net.my_id()))
	_updating = false


func _player_row(peer: int, team_mode: bool) -> Control:
	var slot := PanelContainer.new()
	slot.name = "Player_%d" % peer
	slot.theme_type_variation = &"PanelInset"
	slot.custom_minimum_size = Vector2(0, SLOT_HEIGHT)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	slot.add_child(row)
	var swatch := ColorRect.new()
	swatch.color = Net.color_of(peer)
	swatch.custom_minimum_size = Vector2(12, 44)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(swatch)
	if peer == 1:
		var crown := MenuKit.icon(MenuKit.ICON_CROWN, 34, CROWN_COLOR)
		crown.tooltip_text = "Host"
		crown.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(crown)
	var name_label := MenuKit.label(Net.name_of(peer) + ("  (you)" if peer == Net.my_id() else ""), &"", 28)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	row.add_child(name_label)
	var hero := ClassDef.find(Net.class_of(peer))
	row.add_child(MenuKit.icon(load(UiKit.GLYPHS % hero.icon), 30, UiKit.PROMPT_INK))
	var class_label := MenuKit.label(hero.display_name, &"", 22)
	class_label.add_theme_color_override("font_color", MenuKit.ACCENT)
	class_label.visible = not MenuKit.is_compact(_player_list)  # phones: the class glyph only
	row.add_child(class_label)
	if team_mode:
		var team: int = Net.players[peer].get("team", 0)
		var team_label := MenuKit.label(Net.team_label(team), &"", 24)
		team_label.add_theme_color_override("font_color", Net.team_color(team).darkened(0.25))
		row.add_child(team_label)
	var state := MenuKit.label("", &"", 24)
	state.custom_minimum_size = Vector2(0 if MenuKit.is_compact(_player_list) else 104, 0)
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if peer == 1:
		state.text = "Host"
		state.add_theme_color_override("font_color", MenuKit.ACCENT)
	elif Net.is_ready(peer):
		state.text = "Ready"
		state.add_theme_color_override("font_color", MenuKit.GOOD)
	else:
		state.text = "Not ready"
		state.add_theme_color_override("font_color", Color(MenuKit.BAD, 0.8))
	row.add_child(state)
	if Net.is_host() and peer != 1 and not Net.game_in_progress:
		var kick := Button.new()
		kick.name = "Kick_%d" % peer
		kick.theme_type_variation = &"ButtonBeige"
		kick.text = "Kick"
		kick.custom_minimum_size = Vector2(0, 52)
		kick.add_theme_font_size_override("font_size", 22)
		kick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		kick.tooltip_text = "Remove %s from the game" % Net.name_of(peer)
		kick.pressed.connect(Net.kick.bind(peer))
		row.add_child(kick)
	return slot


func _open_slot() -> Control:
	var slot := PanelContainer.new()
	slot.theme_type_variation = &"PanelInset"
	slot.custom_minimum_size = Vector2(0, SLOT_HEIGHT)
	slot.modulate.a = 0.45
	var label := MenuKit.label("Open slot", &"HintLabel", 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot.add_child(label)
	return slot


## Desktop: players left, hero + settings right. Phones: stacked, the players list only as tall as needed.
func _layout() -> void:
	var compact := MenuKit.is_compact(_columns)
	_columns.vertical = compact
	_players_panel.custom_minimum_size.x = 0.0 if compact else PLAYERS_WIDTH
	_players_panel.size_flags_vertical = Control.SIZE_FILL if compact else Control.SIZE_EXPAND_FILL
	var list_scroll := _player_list.get_parent() as ScrollContainer
	list_scroll.size_flags_vertical = Control.SIZE_FILL if compact else Control.SIZE_EXPAND_FILL
	list_scroll.vertical_scroll_mode = (ScrollContainer.SCROLL_MODE_DISABLED if compact
			else ScrollContainer.SCROLL_MODE_AUTO)
	(_frame.tools as Control).visible = not compact
	for tab in _class_picker.find_children("*", "Button", true, false):
		(tab as Button).add_theme_font_size_override("font_size", 22 if compact else 28)
		(tab as Button).add_theme_constant_override("icon_max_width", 24 if compact else 34)
	for button: Button in [_leave_button, _ready_button, _start_button]:
		if not button.has_meta(&"wide_width"):
			button.set_meta(&"wide_width", button.custom_minimum_size.x)
		button.custom_minimum_size.x = 0.0 if compact else float(button.get_meta(&"wide_width"))
	_status.visible = not compact
	_refresh()
