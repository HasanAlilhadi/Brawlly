extends Node
## Lobby of a multiplayer match. The host edits the match settings; joined players see a plain summary
## of them and can pick a team in team modes. Everyone picks their class (ClassPicker) and sees the others'.
## Everything shown here comes from Net.players / Net.settings and refreshes on Net.lobby_changed.

## Score limit range / default per mode (index = Net.Mode).
const SCORE_LIMITS := [
	Vector3i(0, 0, 0),       # co-op: not used
	Vector3i(1, 50, 10),     # deathmatch: kills
	Vector3i(1, 50, 15),     # team deathmatch: team kills
	Vector3i(1, 10, 3),      # capture the flag: captures
	Vector3i(30, 300, 120),  # king of the hill: seconds held
]

@onready var _title: Label = %Title
@onready var _info: Label = %Info
@onready var _players_title: Label = %PlayersTitle
@onready var _player_list: VBoxContainer = %PlayerList
@onready var _team_row: HBoxContainer = %TeamRow
@onready var _settings_box: VBoxContainer = %SettingsBox
@onready var _start_button: Button = %StartButton
@onready var _leave_button: Button = %LeaveButton
@onready var _waiting: Label = %Waiting

var _updating: bool = false
var _mode_option: OptionButton
var _mode_hint: Label
var _difficulty_option: OptionButton
var _events_option: OptionButton
var _sliders: Dictionary = {}  # key -> {slider, value_label, row}
var _summary: VBoxContainer  # read-only settings for joined players
var _countdown_overlay: Control
var _countdown_number: Label
var _class_picker: ClassPicker
var _preview: ArmyPreview


func _ready() -> void:
	get_tree().paused = false
	_build_settings()
	_build_class_picker()
	_start_button.pressed.connect(func() -> void: Net.start_game())
	_leave_button.pressed.connect(func() -> void: Net.leave())
	Net.lobby_changed.connect(_refresh)
	Net.countdown_started.connect(_show_countdown)
	_build_countdown_overlay()
	_refresh()
	if Net.game_in_progress and Net.countdown_remaining() > 0:
		_show_countdown(Net.countdown_remaining())  # opened after the countdown began


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


## "Your class" right under the team buttons: a preview of your hero and soldiers (in your blue), then the tabs.
func _build_class_picker() -> void:
	var box := _team_row.get_parent()
	var label := Label.new()
	label.text = "Your class"
	box.add_child(label)
	box.move_child(label, _team_row.get_index() + 1)
	_preview = ArmyPreview.new()
	_preview.custom_minimum_size = Vector2(0, 170)
	_preview.set_color(Net.SELF_COLOR)
	box.add_child(_preview)
	box.move_child(_preview, label.get_index() + 1)
	_class_picker = ClassPicker.new()
	box.add_child(_class_picker)
	box.move_child(_class_picker, _preview.get_index() + 1)
	_class_picker.picked.connect(func(class_id: StringName) -> void:
		if not Net.game_in_progress:
			Net.set_class(class_id))


func _can_edit() -> bool:
	return Net.is_host() and not Net.game_in_progress


# --- Settings controls ------------------------------------------------------------

func _build_summary() -> void:
	_summary = VBoxContainer.new()
	_summary.add_theme_constant_override("separation", 6)
	_settings_box.get_parent().add_child(_summary)
	_settings_box.get_parent().move_child(_summary, _settings_box.get_index() + 1)


func _summary_row(label_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 26)
	row.add_child(label)
	var value := Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", 26)
	value.add_theme_color_override("font_color", Color("8a4b1c"))
	row.add_child(value)
	_summary.add_child(row)


func _refresh_summary(settings: Dictionary) -> void:
	for child in _summary.get_children():
		child.queue_free()
	var match_mode: int = settings.mode
	_summary_row("Mode", Net.MODE_NAMES[match_mode])
	var hint := Label.new()
	hint.text = Net.MODE_HINTS[match_mode]
	hint.add_theme_font_size_override("font_size", 20)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.add_child(hint)
	_summary_row("Orc camps", str(settings.camp_count))
	_summary_row("Difficulty", Net.DIFFICULTY_NAMES[settings.difficulty])
	_summary_row("World events", "On" if settings.get("events", true) else "Off")
	_summary_row("Starting coins", str(settings.start_coins))
	if Net.is_team_mode(match_mode):
		_summary_row("Teams", str(settings.team_count))
	if match_mode != Net.Mode.COOP:
		_summary_row(Net.SCORE_LIMIT_LABELS[match_mode], str(settings.score_limit))
		_summary_row("Time limit", "%d min" % settings.time_limit)


func _build_settings() -> void:
	_build_summary()
	_mode_option = _add_option("Mode", Net.MODE_NAMES, func(index: int) -> void:
		Net.set_setting("mode", index)
		var limits: Vector3i = SCORE_LIMITS[index]
		if limits.y > 0:
			Net.set_setting("score_limit", limits.z))
	_mode_hint = Label.new()
	_mode_hint.add_theme_font_size_override("font_size", 22)
	_mode_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_settings_box.add_child(_mode_hint)
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
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(230, 0)
	row.add_child(label)
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.custom_minimum_size = Vector2(0, 72)
	option.add_theme_font_size_override("font_size", 26)
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
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)
	var value_label := Label.new()
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

	_title.text = "Lobby"
	if Net.is_host():
		var addresses := Net.local_addresses()
		_info.text = "Friends on your Wi-Fi can join from Multiplayer → Join.%s" % (
				("\nYour IP: " + ", ".join(addresses)) if not addresses.is_empty() else "")
	else:
		_info.text = "Connected. The host picks the settings."

	# Players
	for child in _player_list.get_children():
		child.queue_free()
	var peers := Net.players.keys()
	peers.sort()
	for peer in peers:
		_player_list.add_child(_player_row(peer, team_mode))

	# Team buttons
	for child in _team_row.get_children():
		child.queue_free()
	_team_row.visible = team_mode
	if _team_row.visible:
		for team in settings.team_count:
			var button := Button.new()
			var mine: bool = Net.players.get(Net.my_id(), {}).get("team", -1) == team
			button.text = "Your team" if mine else "Join %s" % Net.team_label(team)
			button.theme_type_variation = &"ButtonBeige"
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.custom_minimum_size = Vector2(0, 72)
			button.add_theme_font_size_override("font_size", 26)
			button.add_theme_color_override("font_color", Net.team_color(team).darkened(0.3))
			button.add_theme_color_override("font_disabled_color", Net.team_color(team).darkened(0.3))
			button.disabled = mine
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
	(_sliders.score_limit.row as Control).visible = match_mode != Net.Mode.COOP
	(_sliders.time_limit.row as Control).visible = match_mode != Net.Mode.COOP

	_start_button.visible = Net.is_host()
	_start_button.disabled = Net.game_in_progress
	_start_button.text = "Start (%d players)" % Net.players.size()
	_class_picker.select(Net.class_of(Net.my_id()))
	_preview.set_class(Net.class_of(Net.my_id()))
	_waiting.visible = not Net.is_host()
	_updating = false


func _player_row(peer: int, team_mode: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var swatch := ColorRect.new()
	swatch.color = Net.color_of(peer)
	swatch.custom_minimum_size = Vector2(40, 40)
	row.add_child(swatch)
	var name_label := Label.new()
	var tags := PackedStringArray()
	if peer == 1:
		tags.append("host")
	if peer == Net.my_id():
		tags.append("you")
	name_label.text = Net.name_of(peer) + ("  (%s)" % ", ".join(tags) if not tags.is_empty() else "")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var hero := ClassDef.find(Net.class_of(peer))
	var class_label := Label.new()
	class_label.text = hero.display_name
	class_label.add_theme_color_override("font_color", Color("8a4b1c"))
	row.add_child(class_label)
	if team_mode:
		var team: int = Net.players[peer].get("team", 0)
		var team_label := Label.new()
		team_label.text = Net.team_label(team)
		team_label.add_theme_color_override("font_color", Net.team_color(team).darkened(0.25))
		row.add_child(team_label)
	return row
