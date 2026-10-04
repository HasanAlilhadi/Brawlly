class_name UpgradesTab
extends Button
## The upgrades sheet's handle: a drawer tab growing out of the bottom edge of the screen, center. Dark wood with a
## gold trim, rounded top corners only (flush with the edge), a gold up-chevron, "Upgrades" and a small T key chip
## (touch: no key). Click / tap it or press T to open the sheet. A coin badge pulses on its corner while you can
## afford something. It lifts on hover and tucks below the edge while the sheet is open (`tuck`). Sizes: HudStyle.

const COIN_ICON := preload("res://assets/ui/icons/coin.png")
const MOVE_TIME: float = 0.2
const WOOD := Color(0.30, 0.19, 0.11, 0.94)
const WOOD_HOVER := Color(0.40, 0.26, 0.15, 0.97)
const WOOD_PRESSED := Color(0.24, 0.15, 0.09, 0.97)
const TRIM := Color(0.88, 0.66, 0.25)
const TEXT := Color(1.0, 0.96, 0.87)

var _player: Player
var _key: PanelContainer
var _coin: TextureRect
var _chevron: Chevron
var _tween: Tween
var _hover_tween: Tween
var _tucked: bool = false
var _pulse: float = 0.0
var _hidden: float = 0.0  # 0 up .. 1 below the edge
var _lift: float = 0.0  # 0 .. 1 hover lift


## A small gold "^" drawn as a line (no font glyph needed); `bob` nudges it up on hover.
class Chevron extends Control:
	var color := Color.WHITE
	var bob: float = 0.0:
		set(value):
			bob = value
			queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var y := -bob * 3.0
		draw_polyline(PackedVector2Array([Vector2(w * 0.1, h * 0.72 + y), Vector2(w * 0.5, h * 0.3 + y),
				Vector2(w * 0.9, h * 0.72 + y)]), color, 3.0, true)


func _ready() -> void:
	name = "UpgradesTab"
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_stylebox_override(&"normal", _wood(WOOD, Color(TRIM, 0.85)))
	add_theme_stylebox_override(&"hover", _wood(WOOD_HOVER, TRIM))
	add_theme_stylebox_override(&"pressed", _wood(WOOD_PRESSED, TRIM))
	add_theme_stylebox_override(&"hover_pressed", _wood(WOOD_PRESSED, TRIM))
	add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	custom_minimum_size = HudStyle.UPGRADES_TAB
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(HudStyle.GAP * 1.25))
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_bottom = -HudStyle.UPGRADES_TAB_TUCK  # the part below the screen edge stays empty
	add_child(row)
	_chevron = Chevron.new()
	_chevron.color = TRIM
	_chevron.custom_minimum_size = Vector2(18, 18)
	_chevron.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_chevron)
	var label := Label.new()
	label.text = "Upgrades"
	label.add_theme_font_size_override("font_size", HudStyle.FONT_TITLE)
	label.add_theme_color_override("font_color", TEXT)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	label.add_theme_constant_override("outline_size", 4)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	_key = _key_chip("T")
	row.add_child(_key)
	_coin = TextureRect.new()
	_coin.name = "AffordableCoin"
	_coin.texture = COIN_ICON
	_coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_coin.size = Vector2(HudStyle.BADGE, HudStyle.BADGE) * 0.68
	_coin.position = Vector2(HudStyle.UPGRADES_TAB.x - _coin.size.x * 0.62, -_coin.size.y * 0.42)
	_coin.pivot_offset = _coin.size * 0.5
	_coin.visible = false
	add_child(_coin)
	for part in find_children("*", "Control", true, false):
		(part as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	mouse_entered.connect(_hover.bind(true))
	mouse_exited.connect(_hover.bind(false))
	Platform.touch_mode_changed.connect(func(_touch: bool) -> void: _update_key())
	_update_key()
	_place(0.0)


## Rounded top corners, gold trim on top and the sides, nothing along the screen edge; a soft shadow above.
func _wood(fill: Color, trim: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = trim
	box.border_width_top = 2
	box.border_width_left = 2
	box.border_width_right = 2
	box.border_width_bottom = 0
	box.corner_radius_top_left = 16
	box.corner_radius_top_right = 16
	box.corner_detail = 8
	box.shadow_color = Color(0, 0, 0, 0.3)
	box.shadow_size = 6
	box.anti_aliasing = true
	return box


## A small key cap: dark inset, cream outline, the letter.
func _key_chip(letter: String) -> PanelContainer:
	var chip := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0.3)
	box.border_color = Color(TEXT, 0.7)
	box.set_border_width_all(2)
	box.set_corner_radius_all(6)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 1
	box.content_margin_bottom = 1
	chip.add_theme_stylebox_override(&"panel", box)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var key := Label.new()
	key.text = letter
	key.add_theme_font_size_override("font_size", HudStyle.FONT_BODY)
	key.add_theme_color_override("font_color", TEXT)
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.add_child(key)
	return chip


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
		_coin.scale = Vector2.ONE * (1.0 + 0.12 * sin(_pulse))


## Keyboard: the T key chip; touch: just the label (tap it).
func _update_key() -> void:
	_key.visible = not Platform.touch_mode


## The coin badge shows while any upgrade on the sheet (hero or army) can be bought right now.
func _refresh() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var affordable := false
	for def in _player.class_upgrades() + _player.sheet_items():
		if _player.can_buy(def):
			affordable = true
			break
	_coin.visible = affordable
	if not Platform.mobile_layout:
		tooltip_text = "Upgrades (T): something to buy" if affordable else "Upgrades (T)"


## `hidden` 0 = up (the tab shows above the edge), 1 = fully below it; the hover lift is added on top.
func _place(hidden: float) -> void:
	_hidden = hidden
	var height := HudStyle.UPGRADES_TAB.y
	var shown_top := -height + HudStyle.UPGRADES_TAB_TUCK - HudStyle.UPGRADES_TAB_LIFT * _lift
	var top := lerpf(shown_top, HudStyle.UPGRADES_TAB_TUCK + HudStyle.MARGIN, hidden)
	offset_left = -HudStyle.UPGRADES_TAB.x * 0.5
	offset_right = HudStyle.UPGRADES_TAB.x * 0.5
	offset_top = top
	offset_bottom = top + height


func _set_lift(value: float) -> void:
	_lift = value
	_chevron.bob = value
	_place(_hidden)


## Mouse over: the tab rises a little and the chevron nudges up, so it reads as a drawer you can pull.
func _hover(on: bool) -> void:
	var lit := on and not _tucked
	if _hover_tween:
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.tween_method(_set_lift, _lift, 1.0 if lit else 0.0, 0.14).set_trans(Tween.TRANS_SINE)
