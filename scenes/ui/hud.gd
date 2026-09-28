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

const ARMY_ORDERS: PackedStringArray = ["Follow", "Charge", "Hold"]
const ARMY_KEYS: PackedStringArray = ["1", "2", "3"]
## The Warlord's bar shows while it is this close to you.
const BOSS_BAR_RANGE: float = 40.0
const DOWNED_PANEL_WIDTH: float = 380.0
const DOWNED_PANEL_MARGIN: float = 48.0
## Touch layouts lift the card above the sticks.
const DOWNED_PANEL_TOUCH_LIFT: float = 300.0

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
@onready var shop_button: Button = %ShopButton
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
var _ping_button: Button
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
	shop_button.pressed.connect(shop_requested.emit)
	_apply_safe_area()
	_build_hurt_overlay()
	if not Platform.mobile_layout:
		pause_button.tooltip_text = "Pause (Esc)"
		shop_button.tooltip_text = "Shop (B)"
	Platform.touch_mode_changed.connect(_show_touch_controls)
	_show_touch_controls(Platform.touch_mode)
	_build_extras()


func _show_touch_controls(enabled: bool) -> void:
	if _ended:
		return
	if not enabled:
		reset_touch_controls()
	joystick.visible = enabled
	melee_button.visible = enabled
	bow_stick.visible = enabled


func setup(player: Player, camps: Array[Camp]) -> void:
	_player = player
	player.health_changed.connect(_on_health_changed)
	player.arrows_changed.connect(_on_arrows_changed)
	player.coins_changed.connect(_on_coins_changed)
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
	pause_button.hide()
	shop_button.hide()
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


func _process(delta: float) -> void:
	_poll_timer -= delta
	if _poll_timer <= 0.0:
		_poll_timer = 0.25
		if not is_instance_valid(_player) or not _player.is_inside_tree():
			return  # the match is closing
		var followers := _player.followers().size()
		var reserve := _player.reserve_soldiers
		allies_label.text = str(followers) if reserve <= 0 else "%d +%d" % [followers, reserve]
		if not _ended:
			_army_row.visible = followers + reserve > 0
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


func _on_arrows_changed(count: int) -> void:
	arrows_label.text = str(count)
	bow_stick.badge = str(count)
	bow_stick.disabled = count <= 0


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
		button.custom_minimum_size = Vector2(110, 40)
		button.add_theme_font_size_override("font_size", 17)
		if not Platform.mobile_layout:
			button.tooltip_text = "%s (%s)" % [ARMY_ORDERS[order], ARMY_KEYS[order]]
		button.pressed.connect(func() -> void:
			_on_army_order_changed(_player.army_order if _player else 0)  # the server confirms the change
			army_command_requested.emit(order))
		_army_row.add_child(button)
		_army_buttons.append(button)
	_army_row.hide()
	root.add_child(_army_row)

	# Ping (online only): next to the shop button.
	_ping_button = Button.new()
	_ping_button.text = "!"
	_ping_button.theme_type_variation = &"ButtonSquare"
	_ping_button.focus_mode = Control.FOCUS_NONE
	_ping_button.add_theme_font_size_override("font_size", 28)
	_ping_button.position = Vector2(148, 104)
	_ping_button.size = Vector2(60, 60)
	_ping_button.custom_minimum_size = Vector2(60, 60)
	if not Platform.mobile_layout:
		_ping_button.tooltip_text = "Ping (Q / middle mouse) · Help (H)"
	_ping_button.pressed.connect(ping_requested.emit)
	_ping_button.visible = Net.is_online()
	root.add_child(_ping_button)

	_build_downed_panel()

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
	row.add_child(UiKit.medal("skull", 52.0))
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	row.add_child(column)
	var title_row := HBoxContainer.new()
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title_row)
	_downed_title = _small_label("You're down!", 22)
	_downed_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_downed_title)
	_downed_seconds = _small_label("", 22)
	_downed_seconds.text_direction = Control.TEXT_DIRECTION_LTR
	title_row.add_child(_downed_seconds)
	_bleed_bar = _downed_bar(&"ProgressBar")
	column.add_child(_bleed_bar)
	_revive_progress_bar = _downed_bar(&"ProgressBarGreen")
	column.add_child(_revive_progress_bar)
	_downed_hint = _small_label("", 15)
	_downed_hint.modulate = Color(1, 1, 1, 0.8)
	column.add_child(_downed_hint)
	_downed_panel.hide()
	root.add_child(_downed_panel)


func _downed_bar(variation: StringName) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.theme_type_variation = variation
	bar.custom_minimum_size = Vector2(0, 12)
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
		_army_buttons[i].set_pressed_no_signal(i == order)


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
