class_name UpgradesTab
extends Button
## The upgrades sheet's handle: a wooden tab attached to the bottom edge of the screen, center ("T  Upgrades",
## like a content drawer's button). Click / tap it or press T to open the sheet. A coin pulses on it while you can
## afford something. It tucks away below the edge while the sheet is open (`tuck`). Sizes from HudStyle.

const COIN_ICON := preload("res://assets/ui/icons/coin.png")
const MOVE_TIME: float = 0.2

var _player: Player
var _row: HBoxContainer
var _key: Control
var _label: Label
var _coin: TextureRect
var _tween: Tween
var _hover_tween: Tween
var _tucked: bool = false
var _pulse: float = 0.0
var _hidden: float = 0.0  # 0 up .. 1 below the edge
var _lift: float = 0.0  # 0 .. 1 hover lift


func _ready() -> void:
	name = "UpgradesTab"
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var wood := get_theme_stylebox(&"panel", &"PanelBrown")
	for state in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled", &"focus"]:
		add_theme_stylebox_override(state, wood)
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	custom_minimum_size = Vector2(0.0, HudStyle.UPGRADES_TAB_HEIGHT)
	var row := HBoxContainer.new()
	_row = row
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(HudStyle.GAP))
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_bottom = -HudStyle.UPGRADES_TAB_TUCK  # the part below the screen edge stays empty
	add_child(row)
	# The same key picture as the HUD's other shortcuts (X, E).
	_key = UiKit.prompt("keyboard/t", HudStyle.KEY)
	_key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_key)
	_label = Label.new()
	_label.text = "Upgrades"
	_label.theme_type_variation = &"LabelLight"
	_label.add_theme_font_size_override("font_size", HudStyle.FONT_TITLE)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_label)
	_coin = TextureRect.new()
	_coin.name = "AffordableCoin"
	_coin.texture = COIN_ICON
	_coin.custom_minimum_size = Vector2(HudStyle.ICON_SMALL, HudStyle.ICON_SMALL)
	_coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_coin.visible = false
	row.add_child(_coin)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for part in row.find_children("*", "Control", true, false):
		(part as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	mouse_entered.connect(_hover.bind(true))
	mouse_exited.connect(_hover.bind(false))
	Platform.touch_mode_changed.connect(func(_touch: bool) -> void: _update_key())
	_update_key()
	row.minimum_size_changed.connect(func() -> void: _place(_hidden))  # the coin shows / hides
	_place(0.0)


func set_player(player: Player) -> void:
	_player = player
	player.coins_changed.connect(func(_count: int) -> void: _refresh())
	player.upgrades_changed.connect(_refresh)
	_refresh()


## Slides below the screen edge (true) or back up (false).
func tuck(hidden: bool) -> void:
	if hidden == _tucked:
		return
	_tucked = hidden
	if hidden:
		_hover(false)
	if _tween:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN if hidden else Tween.EASE_OUT)
	_tween.tween_method(_place, _hidden, 1.0 if hidden else 0.0, MOVE_TIME)


func _process(delta: float) -> void:
	if _coin.visible:
		_pulse += delta * 4.0
		_coin.pivot_offset = _coin.size * 0.5
		_coin.scale = Vector2.ONE * (1.0 + 0.12 * sin(_pulse))


## Keyboard: the T key cap; touch: just the label (tap it).
func _update_key() -> void:
	_key.visible = not Platform.touch_mode


## The coin shows while any upgrade on the sheet (hero or army) can be bought right now (potions don't count:
## they would light it up after every hit).
func _refresh() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var affordable := false
	for def in _player.class_upgrades() + _player.sheet_items(&"hero") + _player.sheet_items(&"army"):
		if _player.can_buy(def) and not (def.is_consumable() and def.sheet == &"hero"):
			affordable = true
			break
	_coin.visible = affordable
	if not Platform.mobile_layout:
		tooltip_text = "Upgrades (T): something to buy" if affordable else "Upgrades (T)"


## `hidden` 0 = up (the tab shows above the edge), 1 = fully below it; the hover lift is added on top.
func _place(hidden: float) -> void:
	_hidden = hidden
	var height := HudStyle.UPGRADES_TAB_HEIGHT
	var shown_top := -height + HudStyle.UPGRADES_TAB_TUCK - HudStyle.UPGRADES_TAB_LIFT * _lift
	var top := lerpf(shown_top, HudStyle.UPGRADES_TAB_TUCK + HudStyle.MARGIN, hidden)
	# As wide as the key, the text (and the coin) plus a little room on each side.
	var width := _row.get_combined_minimum_size().x + HudStyle.UPGRADES_TAB_PAD * 2.0
	offset_left = -width * 0.5
	offset_right = width * 0.5
	offset_top = top
	offset_bottom = top + height


func _set_lift(value: float) -> void:
	_lift = value
	_place(_hidden)


## Mouse over: lifts a little and brightens, so it reads as a button.
func _hover(on: bool) -> void:
	var lit := on and not _tucked
	if _hover_tween:
		_hover_tween.kill()
	_hover_tween = create_tween().set_parallel(true)
	_hover_tween.tween_method(_set_lift, _lift, 1.0 if lit else 0.0, 0.12)
	_hover_tween.tween_property(self, "self_modulate", Color(1.15, 1.15, 1.15) if lit else Color.WHITE, 0.12)
