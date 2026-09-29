class_name Hud
extends CanvasLayer
## On-screen UI: health, arrows, allies, camps left, minimap, touch controls and the end screen.
## Touch controls only show in `Platform.touch_mode` (phones, or a touchscreen on desktop).
## Also: off-screen arrows (goblin, Warlord, downed teammates, pings), the Warlord's health bar, army
## order buttons, a ping button (online), the "You're down" / revive messages and the match awards.

signal restart_requested
signal main_menu_requested
signal pause_requested
signal shop_requested
signal army_command_requested(order: int)
signal ping_requested
signal weapon_switch_requested

const ARMY_ORDERS: PackedStringArray = ["Follow", "Charge", "Hold", "Kill"]
const ARMY_KEYS: PackedStringArray = ["1", "2", "3", "4"]
## The Warlord's bar shows while it is this close to you.
const BOSS_BAR_RANGE: float = 40.0
const DOWNED_PANEL_WIDTH: float = 380.0
const DOWNED_PANEL_MARGIN: float = 48.0
## Touch layouts lift the card above the sticks.
const DOWNED_PANEL_TOUCH_LIFT: float = 300.0
## Touch control skins (Kenney Mobile Controls, style A).
const TOUCH_PAD := preload("res://assets/ui/touch/joystick_circle_pad_a.png")
const TOUCH_NUB := preload("res://assets/ui/touch/joystick_circle_nub_a.png")
const TOUCH_NUB_HELD := preload("res://assets/ui/touch/highlights/joystick_circle_nub_highlight.png")
const TOUCH_BUTTON := preload("res://assets/ui/touch/button_circle.png")
const TOUCH_BUTTON_HELD := preload("res://assets/ui/touch/highlights/button_circle_highlight.png")
const SPEAR_ICON := preload("res://assets/ui/icons/game/spear.svg")

@onready var root: Control = $Root
@onready var joystick: TouchJoystick = %Joystick
@onready var melee_button: TouchAimStick = %MeleeButton
@onready var bow_stick: TouchAimStick = %BowStick
@onready var health_bar: ProgressBar = %HealthBar
@onready var arrows_label: Label = %ArrowsLabel
@onready var allies_label: Label = %AlliesLabel
@onready var camps_label: Label = %CampsLabel
@onready var minimap: Minimap = %Minimap
@onready var end_panel: Control = %EndPanel
@onready var end_title: Label = %EndTitle
@onready var end_subtitle: Label = %EndSubtitle
@onready var restart_button: Button = %RestartButton
@onready var menu_button: Button = %MenuButton
@onready var pause_button: Button = %PauseButton
@onready var coins_label: Label = %CoinsLabel
@onready var toast: Control = %Toast
@onready var toast_label: Label = %ToastLabel
@onready var score_panel: Control = %ScorePanel
@onready var score_label: Label = %ScoreLabel
@onready var respawn_label: Label = %RespawnLabel

var _player: Player
var _poll_timer: float = 0.0
var _toast_tween: Tween
var _hurt_overlay: TextureRect
var _hurt_tween: Tween
var _ended: bool = false
var markers: OffscreenMarkers
var _boss_panel: Control
var _boss_bar: ProgressBar
var _army_row: VBoxContainer
var _army_buttons: Array[Button] = []
var _kill_picking: bool = false
var _ping_button: Button
var _switch_button: TouchButton
var _stall_prompt: Button
var _stall_key: HBoxContainer
var _stall_label: Label
var _weapon_bar: PanelContainer
var _weapon_slots: HBoxContainer
var _weapon_icons: Dictionary = {}  # weapon id -> texture for the touch buttons
var _arrow_icon: TextureRect
var _arrow_texture: Texture2D
var _downed_panel: PanelContainer
var _downed_title: Label
var _downed_seconds: Label
var _downed_hint: Label
var _bleed_bar: ProgressBar
var _revive_progress_bar: ProgressBar
var _revive_label: Label
var _awards_box: GridContainer
var _awards_header: Label
var _end_buttons: BoxContainer


func _ready() -> void:
	end_panel.hide()
	restart_button.pressed.connect(restart_requested.emit)
	menu_button.pressed.connect(main_menu_requested.emit)
	pause_button.pressed.connect(pause_requested.emit)
	_apply_safe_area()
	_build_hurt_overlay()
	if not Platform.mobile_layout:
		pause_button.tooltip_text = "Pause (Esc)"
	joystick.pad_texture = TOUCH_PAD
	joystick.knob_texture = TOUCH_NUB
	joystick.knob_held_texture = TOUCH_NUB_HELD
	for stick: TouchAimStick in [melee_button, bow_stick]:
		stick.button_texture = TOUCH_BUTTON
		stick.held_texture = TOUCH_BUTTON_HELD
		stick.knob_texture = TOUCH_NUB
	_arrow_icon = get_node("Root/TopLeft/Rows/InfoRow/ArrowIcon") as TextureRect
	_arrow_texture = _arrow_icon.texture
	Platform.touch_mode_changed.connect(_show_touch_controls)
	_show_touch_controls(Platform.touch_mode)
	_build_extras()
	_apply_design()


func _show_touch_controls(enabled: bool) -> void:
	if _ended:
		return
	if not enabled:
		reset_touch_controls()
	joystick.visible = enabled
	_update_weapon_controls()


func setup(player: Player, camps: Array[Camp]) -> void:
	_player = player
	player.weapon_changed.connect(func(_weapon: String) -> void: _update_weapon_controls())
	_update_weapon_controls()
	player.health_changed.connect(_on_health_changed)
	player.arrows_changed.connect(_on_arrows_changed)
	player.spears_changed.connect(_on_arrows_changed)
	player.coins_changed.connect(_on_coins_changed)
	player.soldier_ready.connect(func() -> void: show_toast("A soldier is ready at the barracks"))
	_on_coins_changed(player.coins)
	_on_health_changed(player.health, player.max_health)
	_on_arrows_changed(player.arrows)
	minimap.setup(player, camps)
	markers.origin = player
	player.army_order_changed.connect(_on_army_order_changed)
	_on_army_order_changed(player.army_order)


func set_camps(left: int, total: int) -> void:
	camps_label.text = "%d/%d" % [left, total]


## Mode scoreboard line (hidden when empty, e.g. co-op).
func set_mode_label(text: String) -> void:
	score_label.text = text
	score_panel.visible = text != ""


## "Respawning in N" while the local player is down (0 hides it).
func show_respawn(seconds: int) -> void:
	respawn_label.visible = seconds > 0
	respawn_label.text = "Respawning in %d" % seconds


## `restart_label` empty hides the restart button (e.g. clients waiting for the host).
func show_end(title: String, subtitle: String, restart_label: String = "Play again") -> void:
	restart_button.text = restart_label
	restart_button.visible = restart_label != ""
	respawn_label.hide()
	_downed_panel.hide()
	_revive_label.hide()
	_boss_panel.hide()
	_army_row.hide()
	_ping_button.hide()
	_ended = true
	reset_touch_controls()
	joystick.hide()
	melee_button.hide()
	bow_stick.hide()
	_switch_button.hide()
	_weapon_bar.hide()
	pause_button.hide()
	_stall_prompt.hide()
	end_title.text = title
	end_subtitle.text = subtitle
	end_subtitle.visible = subtitle != ""
	_layout_end_screen()
	end_panel.show()


## Clears held touches (call when pausing: paused controls never see the finger lift).
func reset_touch_controls() -> void:
	joystick.release()
	melee_button.reset()
	bow_stick.reset()
	if _switch_button:
		_switch_button.reset()


func _process(delta: float) -> void:
	_poll_timer -= delta
	if _poll_timer <= 0.0:
		_poll_timer = 0.25
		if not is_instance_valid(_player) or not _player.is_inside_tree():
			return  # the match is closing
		var followers := _player.followers().size()
		allies_label.text = str(followers)
		if not _ended:
			_army_row.visible = followers > 0
			_update_boss_bar()
			_update_downed()


## Red glow around the screen edges when the local player is hit (strength 0..1).
func flash_hurt(strength: float) -> void:
	if _hurt_tween:
		_hurt_tween.kill()
	_hurt_overlay.modulate.a = lerpf(0.45, 0.95, strength)
	_hurt_tween = create_tween()
	_hurt_tween.tween_property(_hurt_overlay, "modulate:a", 0.0, 0.45).set_ease(Tween.EASE_OUT)


func _build_hurt_overlay() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.85, 0.05, 0.05, 0.0))
	gradient.set_color(1, Color(0.85, 0.05, 0.05, 0.85))
	gradient.set_offset(0, 0.45)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.05, 0.5)
	texture.width = 128
	texture.height = 128
	_hurt_overlay = TextureRect.new()
	_hurt_overlay.texture = texture
	_hurt_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hurt_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	_hurt_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hurt_overlay.modulate.a = 0.0
	root.add_child(_hurt_overlay)
	root.move_child(_hurt_overlay, 0)


## Short message banner under the top UI (fades out by itself).
func show_toast(message: String, duration: float = 2.5) -> void:
	toast_label.text = message
	toast.show()
	toast.modulate.a = 0.0
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(toast, "modulate:a", 1.0, 0.2)
	_toast_tween.tween_interval(duration)
	_toast_tween.tween_property(toast, "modulate:a", 0.0, 0.4)
	_toast_tween.tween_callback(toast.hide)


func _on_coins_changed(count: int) -> void:
	coins_label.text = str(count)


func _on_health_changed(current: float, maximum: float) -> void:
	health_bar.max_value = maximum
	health_bar.value = current


## Ammo of the ranged weapon you carry (arrows for the bow, spears for the spear; hidden with the
## sword alone). Connected to both ammo signals, so the count argument is ignored.
func _on_arrows_changed(_count: int = 0) -> void:
	if _player == null:
		return
	# Ammo of the ranged weapon in hand; with the sword in hand, of the carried one (bow first).
	var held := _player.current_weapon()
	var spear := held == "spear" or (held != "bow" and not _player.weapons.has("bow") and _player.weapons.has("spear"))
	var ammo := _player.spears if spear else _player.arrows
	var ranged := _player.weapons.has("spear") or _player.weapons.has("bow")
	arrows_label.text = str(ammo)
	arrows_label.visible = ranged
	_arrow_icon.visible = ranged
	_arrow_icon.texture = SPEAR_ICON if spear else _arrow_texture
	bow_stick.badge = str(ammo)
	bow_stick.disabled = ammo <= 0


## Keeps UI away from notches / rounded corners on phones.
func _apply_safe_area() -> void:
	if not OS.has_feature("mobile"):
		return
	var safe := DisplayServer.get_display_safe_area()
	var window := Vector2(DisplayServer.window_get_size())
	if window.x <= 0.0:
		return
	var ratio := root.get_viewport_rect().size.x / window.x
	root.offset_left = safe.position.x * ratio
	root.offset_top = safe.position.y * ratio
	root.offset_right = -(window.x - safe.end.x) * ratio
	root.offset_bottom = -(window.y - safe.end.y) * ratio


# --- Multiplayer extras ----------------------------------------------------------------

func _build_extras() -> void:
	markers = OffscreenMarkers.new()
	root.add_child(markers)
	root.move_child(markers, 1)

	# Warlord health (top center, under the score line).
	_boss_panel = PanelContainer.new()
	_boss_panel.theme_type_variation = &"PanelCompact"
	_boss_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_panel.offset_left = -200.0
	_boss_panel.offset_right = 200.0
	_boss_panel.offset_top = 272.0  # under the toast banner
	_boss_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var boss_box := VBoxContainer.new()
	boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_box.add_theme_constant_override("separation", 2)
	_boss_panel.add_child(boss_box)
	var boss_name := _small_label("Orc Warlord", 20)
	boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_box.add_child(boss_name)
	_boss_bar = ProgressBar.new()
	_boss_bar.custom_minimum_size = Vector2(0, 16)
	_boss_bar.show_percentage = false
	_boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_box.add_child(_boss_bar)
	_boss_panel.hide()
	root.add_child(_boss_panel)

	# Army orders (a column at the top right, under the soldier count).
	_army_row = VBoxContainer.new()
	_army_row.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_army_row.offset_top = 220.0
	_army_row.offset_right = -12.0
	_army_row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_army_row.add_theme_constant_override("separation", 4)
	for order in ARMY_ORDERS.size():
		var button := Button.new()
		button.text = ARMY_ORDERS[order]
		button.theme_type_variation = &"ButtonBeige"
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = HudStyle.BUTTON_WIDE
		button.add_theme_font_size_override("font_size", HudStyle.FONT_BUTTON)
		if not Platform.mobile_layout:
			button.tooltip_text = "%s (%s)" % [ARMY_ORDERS[order], ARMY_KEYS[order]]
			# Key prompt (1 / 2 / 3 / 4) at the left of the label.
			button.icon = load("res://assets/ui/prompts/keyboard/%s.png" % ARMY_KEYS[order])
			for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
				button.add_theme_color_override(state, UiKit.PROMPT_INK)  # same dark key cap as UiKit.prompt
			button.add_theme_constant_override("h_separation", 6)
		button.pressed.connect(func() -> void:
			_on_army_order_changed(_player.army_order if _player else 0)  # the server confirms the change
			army_command_requested.emit(order))
		_army_row.add_child(button)
		_army_buttons.append(button)
	_army_row.hide()
	root.add_child(_army_row)

	# Ping (online only): next to the pause button.
	_ping_button = Button.new()
	_ping_button.text = "!"
	_ping_button.theme_type_variation = &"ButtonSquare"
	_ping_button.focus_mode = Control.FOCUS_NONE
	_ping_button.add_theme_font_size_override("font_size", 28)
	_ping_button.position = Vector2(148, 104)
	_ping_button.size = Vector2(60, 60)
	_ping_button.custom_minimum_size = Vector2(60, 60)
	if not Platform.mobile_layout:
		_ping_button.tooltip_text = "Ping (G / middle mouse) · Help (H)"
	_ping_button.pressed.connect(ping_requested.emit)
	_ping_button.visible = Net.is_online()
	root.add_child(_ping_button)

	_build_downed_panel()
	_build_weapon_controls()
	_build_stall_prompt()

	_revive_label = _small_label("", 26)
	_revive_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_revive_label.offset_left = -300.0
	_revive_label.offset_right = 300.0
	_revive_label.offset_top = -300.0
	_revive_label.offset_bottom = -260.0
	_revive_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_revive_label.hide()
	root.add_child(_revive_label)

	_build_end_screen()


## "E  Blacksmith" (bottom center) while the local player stands at a trading post stall; click / tap it
## or press interact to open that stall's shop.
func _build_stall_prompt() -> void:
	_stall_prompt = Button.new()
	_stall_prompt.theme_type_variation = &"ButtonBeige"
	_stall_prompt.focus_mode = Control.FOCUS_NONE
	_stall_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_stall_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_stall_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_stall_prompt.offset_bottom = -DOWNED_PANEL_MARGIN
	_stall_prompt.pressed.connect(shop_requested.emit)
	# Key + label, centered on the button's face: inset by the style's content margins (the beige
	# button has a drop-shadow lip at the bottom, so its face sits a little above the rect's middle).
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(HudStyle.GAP))
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	var face := _stall_prompt.get_theme_stylebox(&"normal")
	row.offset_left = face.get_margin(SIDE_LEFT)
	row.offset_top = face.get_margin(SIDE_TOP)
	row.offset_right = -face.get_margin(SIDE_RIGHT)
	row.offset_bottom = -face.get_margin(SIDE_BOTTOM)
	_stall_prompt.add_child(row)
	_stall_key = HBoxContainer.new()
	_stall_key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_stall_key)
	_stall_label = Label.new()
	_stall_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stall_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stall_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_stall_label.add_theme_font_size_override("font_size", HudStyle.FONT_TITLE)
	row.add_child(_stall_label)
	_stall_prompt.hide()
	$Root.add_child(_stall_prompt)


## Every frame from main.gd: the stall the local player can use (null = none).
## `take_soldiers` > 0: the player stands at the barracks pen gate — "Take N soldiers" instead of the shop.
func set_stall(stall: ShopStation, take_soldiers: int = 0) -> void:
	_stall_prompt.visible = stall != null and not _ended
	if not _stall_prompt.visible:
		return
	var key := "touch/tap" if Platform.touch_mode else "keyboard/e"
	var allowed := stall.can_access(_player)
	var text := stall.title_for(_player)
	var ready := _player.penned_soldiers().size() if allowed and stall.stall_id == ShopStation.BARRACKS else 0
	if allowed and take_soldiers > 0:
		text = "Take %d soldier%s" % [take_soldiers, "" if take_soldiers == 1 else "s"]
	elif ready > 0:
		text += "  (%d ready)" % ready
	if _stall_label.text != text or _stall_key.get_meta(&"key", "") != key:
		_stall_label.text = text
		_stall_key.set_meta(&"key", key)
		for child in _stall_key.get_children():
			child.queue_free()
		_stall_key.add_child(UiKit.prompt(key, HudStyle.KEY))
		# Button = content (key + gap + label) + the style's content margins, so the row fills the face exactly.
		var face := _stall_prompt.get_theme_stylebox(&"normal")
		var label_size := _stall_label.get_minimum_size()
		var content := Vector2(HudStyle.KEY + HudStyle.GAP + label_size.x, maxf(HudStyle.KEY, label_size.y))
		_stall_prompt.custom_minimum_size = content + Vector2(face.get_margin(SIDE_LEFT) + face.get_margin(SIDE_RIGHT),
				face.get_margin(SIDE_TOP) + face.get_margin(SIDE_BOTTOM))
		_stall_prompt.offset_left = -_stall_prompt.custom_minimum_size.x * 0.5
		_stall_prompt.offset_right = _stall_prompt.custom_minimum_size.x * 0.5
	_stall_prompt.offset_bottom = -(DOWNED_PANEL_TOUCH_LIFT if Platform.touch_mode else DOWNED_PANEL_MARGIN)
	_stall_prompt.offset_top = _stall_prompt.offset_bottom - _stall_prompt.custom_minimum_size.y


## "You're down" card (bottom center, clear of the player): skull badge, bleed-out bar with seconds,
## revive bar while a teammate helps, and a hint.
func _build_downed_panel() -> void:
	_downed_panel = PanelContainer.new()
	_downed_panel.theme_type_variation = &"PanelCompact"
	_downed_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_downed_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_downed_panel.offset_left = -DOWNED_PANEL_WIDTH * 0.5
	_downed_panel.offset_right = DOWNED_PANEL_WIDTH * 0.5
	_downed_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_downed_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	_downed_panel.add_child(row)
	row.add_child(UiKit.medal("skull", HudStyle.BADGE))
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	row.add_child(column)
	var title_row := HBoxContainer.new()
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title_row)
	_downed_title = _small_label("You're down!", HudStyle.FONT_TITLE)
	_downed_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_downed_title)
	_downed_seconds = _small_label("", HudStyle.FONT_TITLE)
	_downed_seconds.text_direction = Control.TEXT_DIRECTION_LTR
	title_row.add_child(_downed_seconds)
	_bleed_bar = _downed_bar(&"ProgressBar")
	column.add_child(_bleed_bar)
	_revive_progress_bar = _downed_bar(&"ProgressBarGreen")
	column.add_child(_revive_progress_bar)
	_downed_hint = _small_label("", HudStyle.FONT_SMALL)
	_downed_hint.modulate = Color(1, 1, 1, 0.8)
	column.add_child(_downed_hint)
	_downed_panel.hide()
	root.add_child(_downed_panel)


func _downed_bar(variation: StringName) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.theme_type_variation = variation
	bar.custom_minimum_size = Vector2(0, HudStyle.BAR_HEIGHT_SMALL)
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar


## End screen: the result on a wood ribbon, the subtitle, award cards, and the buttons (side by side
## on wide screens).
func _build_end_screen() -> void:
	var box := end_title.get_parent() as VBoxContainer
	box.add_theme_constant_override("separation", 16)
	var ribbon := PanelContainer.new()
	ribbon.theme_type_variation = &"PanelBrown"
	ribbon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(ribbon)
	box.move_child(ribbon, 0)
	end_title.reparent(ribbon)
	end_title.theme_type_variation = &"LabelLight"
	end_title.add_theme_font_size_override("font_size", 56)
	end_title.custom_minimum_size.x = 380.0
	end_subtitle.theme_type_variation = &"HeaderLabel"
	end_subtitle.add_theme_font_size_override("font_size", 28)

	_awards_header = Label.new()
	_awards_header.text = "Match awards"
	_awards_header.theme_type_variation = &"HintLabel"
	_awards_header.add_theme_font_size_override("font_size", 22)
	_awards_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_awards_header.hide()
	box.add_child(_awards_header)
	box.move_child(_awards_header, end_subtitle.get_index() + 1)
	_awards_box = GridContainer.new()
	_awards_box.add_theme_constant_override("h_separation", 10)
	_awards_box.add_theme_constant_override("v_separation", 10)
	box.add_child(_awards_box)
	box.move_child(_awards_box, _awards_header.get_index() + 1)

	_end_buttons = BoxContainer.new()
	_end_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_end_buttons.add_theme_constant_override("separation", 16)
	box.add_child(_end_buttons)
	restart_button.reparent(_end_buttons)
	menu_button.reparent(_end_buttons)
	restart_button.custom_minimum_size = Vector2(320, 90)
	menu_button.custom_minimum_size = Vector2(320, 90)


func _layout_end_screen() -> void:
	var view := get_viewport().get_visible_rect().size
	var wide := view.x > view.y
	var panel := end_title.get_parent().get_parent().get_parent() as Control
	panel.custom_minimum_size.x = 860.0 if wide else minf(640.0, view.x - 40.0)
	_awards_box.columns = 2 if wide and _awards_box.get_child_count() > 1 else 1
	_end_buttons.vertical = not wide


func _small_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"LabelLight"
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _on_army_order_changed(order: int) -> void:
	for i in _army_buttons.size():
		_army_buttons[i].set_pressed_no_signal(i == order or (i == Player.Order.KILL and _kill_picking))


## Mouse: the Kill button stays lit while the next click picks the target.
func set_kill_picking(on: bool) -> void:
	_kill_picking = on
	_on_army_order_changed(_player.army_order if _player else 0)


func _update_boss_bar() -> void:
	var boss: Unit = null
	for node in get_tree().get_nodes_in_group(&"bosses"):
		if not (node as Unit).is_dead and (node as Node3D).global_position.distance_to(_player.global_position) < BOSS_BAR_RANGE:
			boss = node
	_boss_panel.visible = boss != null
	if boss:
		_boss_bar.max_value = boss.max_health
		_boss_bar.value = boss.health


## "You're down" for us; "reviving…" / "stand close" when a downed teammate is near.
func _update_downed() -> void:
	_downed_panel.visible = _player.is_downed
	if _player.is_downed:
		var reviving := _player.revive_progress > 0.0
		_downed_panel.offset_bottom = -(DOWNED_PANEL_TOUCH_LIFT if Platform.touch_mode else DOWNED_PANEL_MARGIN)
		_downed_seconds.text = "%ds" % _player.bleed_seconds
		_bleed_bar.value = _player.bleed_seconds / Player.BLEED_TIME
		_revive_progress_bar.visible = reviving
		_revive_progress_bar.value = _player.revive_progress
		_downed_hint.text = "Being revived — stay still" if reviving else "Crawl to a teammate to get revived"
	var nearest: Player = null
	var nearest_dist := 6.0
	if not _player.is_downed and not _player.is_dead:
		for node in get_tree().get_nodes_in_group(&"players"):
			var other := node as Player
			if other != _player and other.is_downed and other.team_id == _player.team_id:
				var d := other.global_position.distance_to(_player.global_position)
				if d < nearest_dist:
					nearest_dist = d
					nearest = other
	_revive_label.visible = nearest != null
	if nearest:
		_revive_label.text = ("Reviving %s…" if nearest_dist < Player.REVIVE_RANGE else "Stand next to %s to revive them") % nearest.display_name


## End of match: one card per award — medal badge, award name, player (in their color), what they did.
func show_awards(awards: Array) -> void:
	for child in _awards_box.get_children():
		child.queue_free()
	for award in awards:
		_awards_box.add_child(_award_card(award))
	_awards_header.visible = not awards.is_empty()
	_layout_end_screen.call_deferred()


func _award_card(award: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"PanelLight"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	row.add_child(UiKit.medal(award.get("icon", "icon_circle_beige"), 64.0))
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)
	var title := Label.new()
	title.text = award.title
	title.theme_type_variation = &"HeaderLabel"
	title.add_theme_font_size_override("font_size", 26)
	text.add_child(title)
	var who := Label.new()
	who.text = award.name
	who.add_theme_font_size_override("font_size", 24)
	who.add_theme_color_override("font_color", Net.color_of(award.peer).darkened(0.35))
	text.add_child(who)
	var detail := Label.new()
	detail.text = award.detail
	detail.theme_type_variation = &"HintLabel"
	text.add_child(detail)
	return card


# --- Weapons ------------------------------------------------------------------------

## Touch: the stick of the weapon in hand sits in the big slot, a small button above it switches.
## Desktop: a weapon bar at the bottom right (both slots, the one in hand lit, Q to switch).
func _build_weapon_controls() -> void:
	# The glyph is tight (no padding like the 64 px RPG icons), so the touch stick gets a 44 px copy.
	var spear_image := SPEAR_ICON.get_image()
	spear_image.resize(44, 44, Image.INTERPOLATE_LANCZOS)
	_weapon_icons = {"sword": melee_button.icon, "bow": bow_stick.icon, "spear": ImageTexture.create_from_image(spear_image)}
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		melee_button.set_offset(side, bow_stick.get_offset(side))
	melee_button.drag_radius = bow_stick.drag_radius
	_switch_button = TouchButton.new()
	_switch_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_switch_button.offset_left = -158.0
	_switch_button.offset_top = -330.0
	_switch_button.offset_right = -64.0
	_switch_button.offset_bottom = -236.0
	_switch_button.color = bow_stick.color
	_switch_button.held_color = bow_stick.held_color
	_switch_button.ring_color = bow_stick.ring_color
	_switch_button.button_texture = TOUCH_BUTTON
	_switch_button.held_texture = TOUCH_BUTTON_HELD
	_switch_button.icon_scale = 0.9
	_switch_button.badge = "switch"
	_switch_button.pressed.connect(weapon_switch_requested.emit)
	root.add_child(_switch_button)

	_weapon_bar = PanelContainer.new()
	_weapon_bar.theme_type_variation = &"PanelCompact"
	_weapon_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weapon_bar.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_weapon_bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_weapon_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_weapon_bar.offset_right = -16.0
	_weapon_bar.offset_bottom = -16.0
	_weapon_slots = HBoxContainer.new()
	_weapon_slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weapon_slots.add_theme_constant_override("separation", 8)
	_weapon_bar.add_child(_weapon_slots)
	root.add_child(_weapon_bar)
	_update_weapon_controls()


func _update_weapon_controls() -> void:
	if _switch_button == null:
		return
	var touch := Platform.touch_mode and not _ended
	var melee := _player == null or _player.holds_melee()
	melee_button.visible = touch and melee
	bow_stick.visible = touch and not melee
	# The aim stick serves every ranged weapon: its icon, and the arrow count only for the bow.
	if _player:
		bow_stick.icon = _weapon_icons.get(_player.current_weapon(), bow_stick.icon)
		_on_arrows_changed(_player.arrows)
	var other := _player.other_weapon() if _player else ""
	_switch_button.visible = touch and other != ""
	_switch_button.icon = _weapon_icons.get(other)
	_weapon_bar.visible = not touch and not _ended and _player != null
	if _player == null:
		return
	for child in _weapon_slots.get_children():
		child.queue_free()
	for i in _player.weapons.size():
		var weapon := _player.weapons[i]
		var badge := UiKit.medal(Player.WEAPONS[weapon]["icon"], HudStyle.BADGE)
		badge.modulate = HudStyle.SLOT_ACTIVE if i == _player.weapon_index else HudStyle.SLOT_INACTIVE
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for part in badge.find_children("*", "Control", true, false):
			(part as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_weapon_slots.add_child(badge)
	if _player.weapons.size() > 1:
		var key := UiKit.prompt("keyboard/q", HudStyle.KEY)
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_weapon_slots.add_child(key)


# --- Design system -----------------------------------------------------------------

## Lays the HUD out from HudStyle tokens: left column (stats, then square buttons), right column
## (minimap, stats, army orders), one scale for icons, fonts and buttons.
func _apply_design() -> void:
	var left := _column(false)
	var top_left := $Root/TopLeft as Control
	top_left.reparent(left, false)
	top_left.custom_minimum_size = Vector2(HudStyle.LEFT_WIDTH, 0)
	var buttons := HBoxContainer.new()
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buttons.add_theme_constant_override("separation", int(HudStyle.GAP))
	left.add_child(buttons)
	for button: Button in [pause_button, _ping_button]:
		button.reparent(buttons, false)
		button.custom_minimum_size = Vector2(HudStyle.BUTTON, HudStyle.BUTTON)
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		button.add_theme_font_size_override("font_size", HudStyle.FONT_TITLE)
	health_bar.custom_minimum_size.y = HudStyle.BAR_HEIGHT
	for label: Label in [arrows_label, coins_label]:
		label.add_theme_font_size_override("font_size", HudStyle.FONT_TITLE)
	_size_icons(top_left, HudStyle.ICON)

	var right := _column(true)
	var map_frame := $Root/MinimapFrame as Control
	map_frame.reparent(right, false)
	map_frame.custom_minimum_size = Vector2(HudStyle.COLUMN_WIDTH, HudStyle.COLUMN_WIDTH)
	var stats := $Root/Stats as Control
	stats.reparent(right, false)
	stats.custom_minimum_size = Vector2(HudStyle.COLUMN_WIDTH, 0)
	for label: Label in [allies_label, camps_label]:
		label.add_theme_font_size_override("font_size", HudStyle.FONT_BODY)
	_size_icons(stats, HudStyle.ICON_SMALL)
	_army_row.reparent(right, false)
	_army_row.add_theme_constant_override("separation", int(HudStyle.GAP))
	for button in _army_buttons:
		button.custom_minimum_size = HudStyle.BUTTON_WIDE
		button.add_theme_font_size_override("font_size", HudStyle.FONT_BUTTON)
		button.add_theme_constant_override("icon_max_width", int(HudStyle.KEY))

	toast_label.add_theme_font_size_override("font_size", HudStyle.FONT_BODY)
	score_label.add_theme_font_size_override("font_size", HudStyle.FONT_BODY)
	respawn_label.add_theme_font_size_override("font_size", HudStyle.FONT_HEADLINE)
	_revive_label.add_theme_font_size_override("font_size", HudStyle.FONT_TITLE)
	_weapon_bar.offset_right = -HudStyle.MARGIN
	_weapon_bar.offset_bottom = -HudStyle.MARGIN
	_weapon_slots.add_theme_constant_override("separation", int(HudStyle.GAP))
	# Off-screen arrows slide under the HUD panels (minimap, stats) instead of over them.
	root.move_child(markers, 0)


## A top-left (or top-right) column at the HUD margin that stacks its children with the HUD gap.
func _column(right_side: bool) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", int(HudStyle.GAP))
	column.set_anchors_preset(Control.PRESET_TOP_RIGHT if right_side else Control.PRESET_TOP_LEFT)
	column.offset_top = HudStyle.MARGIN
	if right_side:
		column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		column.offset_right = -HudStyle.MARGIN
		column.offset_left = -HudStyle.MARGIN
	else:
		column.offset_left = HudStyle.MARGIN
	root.add_child(column)
	root.move_child(column, 1)
	return column


func _size_icons(parent: Node, icon_size: float) -> void:
	for icon in parent.find_children("*", "TextureRect", true, false):
		var picture := icon as TextureRect
		picture.custom_minimum_size = Vector2(icon_size, icon_size)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
