class_name UpgradeSheet
extends PanelContainer
## Bottom sheet with your class's upgrades (UpgradeDef.classes), opened / closed with T, the gamepad View
## button or the HUD upgrades button (Hud.toggle_upgrades). Slides up from the bottom edge; the match keeps
## running. One card per upgrade: medal, name, what it does, level pips, the control that uses it, and a buy
## button (cost / Owned / Max / the other choice taken). Buying anywhere goes through Player.request_buy.
## Esc closes it before the pause menu opens. Sizes come from HudStyle.

signal toggled_open(open: bool)

const COIN_ICON := preload("res://assets/ui/icons/coin.png")
const KEY_PROMPTS := {"C": "keyboard/c", "E": "keyboard/e", "RMB": "mouse/right"}
const SLIDE_TIME: float = 0.18

var is_open: bool = false
var _player: Player
var _title: Label
var _coins: Label
var _grid: GridContainer
var _scroll: ScrollContainer
var _cards: Array[Dictionary] = []  # {def, root, level, button}
var _tween: Tween


func _ready() -> void:
	theme_type_variation = &"PanelBrown"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(HudStyle.GAP))
	add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", int(HudStyle.GAP) * 2)
	column.add_child(header)
	_title = Label.new()
	_title.theme_type_variation = &"LabelLight"
	_title.add_theme_font_size_override("font_size", HudStyle.FONT_TITLE)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var coin := TextureRect.new()
	coin.texture = COIN_ICON
	coin.custom_minimum_size = Vector2(HudStyle.ICON, HudStyle.ICON)
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(coin)
	_coins = Label.new()
	_coins.name = "SheetCoins"
	_coins.theme_type_variation = &"LabelLight"
	_coins.add_theme_font_size_override("font_size", HudStyle.FONT_TITLE)
	header.add_child(_coins)
	var close := Button.new()
	close.name = "CloseUpgrades"
	close.text = "Close" if Platform.mobile_layout else "Close (T)"
	close.theme_type_variation = &"ButtonBeige"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(0, HudStyle.BUTTON_WIDE.y)
	close.add_theme_font_size_override("font_size", HudStyle.FONT_BUTTON)
	close.pressed.connect(close_sheet)
	header.add_child(close)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.name = "UpgradeCards"
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", int(HudStyle.GAP))
	_grid.add_theme_constant_override("v_separation", int(HudStyle.GAP))
	_scroll.add_child(_grid)
	visible = false
	get_viewport().size_changed.connect(_layout)
	_grid.minimum_size_changed.connect(_layout)


func set_player(player: Player) -> void:
	_player = player
	player.coins_changed.connect(func(_count: int) -> void: _refresh())
	player.upgrades_changed.connect(_refresh)
	_title.text = "%s Upgrades" % player.class_def.display_name
	for child in _grid.get_children():
		child.queue_free()
	_cards.clear()
	for def in player.class_upgrades():
		_add_card(def)
	_layout()
	_refresh()


func toggle() -> void:
	if is_open:
		close_sheet()
	else:
		open_sheet()


func open_sheet() -> void:
	if is_open or _player == null:
		return
	is_open = true
	visible = true
	modulate.a = 0.0  # one frame to lay the cards out before measuring the sheet
	_refresh()
	_layout()
	toggled_open.emit(true)
	await get_tree().process_frame
	if not is_open:
		return
	_layout()
	modulate.a = 1.0
	_slide(0.0)


func close_sheet() -> void:
	if not is_open:
		return
	is_open = false
	_slide(1.0)
	toggled_open.emit(false)


## Esc / the pause button close the sheet first.
func _input(event: InputEvent) -> void:
	if is_open and (event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause")):
		close_sheet()
		get_viewport().set_input_as_handled()


func _add_card(def: UpgradeDef) -> void:
	var card := PanelContainer.new()
	card.name = "Card_%s" % def.id
	card.theme_type_variation = &"PanelLight"
	card.custom_minimum_size = HudStyle.UPGRADE_CARD
	_grid.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(HudStyle.GAP) / 2)
	card.add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", int(HudStyle.GAP))
	box.add_child(top)
	top.add_child(UiKit.medal(def.icon.resource_path, HudStyle.BADGE))
	var name_box := VBoxContainer.new()
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.alignment = BoxContainer.ALIGNMENT_CENTER
	name_box.add_theme_constant_override("separation", 0)
	top.add_child(name_box)
	var title := Label.new()
	title.text = def.title
	title.add_theme_font_size_override("font_size", HudStyle.FONT_BODY)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_box.add_child(title)
	var level := Label.new()
	level.theme_type_variation = &"HintLabel"
	level.add_theme_font_size_override("font_size", HudStyle.FONT_SMALL)
	name_box.add_child(level)
	var description := Label.new()
	description.text = def.description
	description.theme_type_variation = &"HintLabel"
	description.add_theme_font_size_override("font_size", HudStyle.FONT_SMALL)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(description)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", int(HudStyle.GAP))
	box.add_child(bottom)
	if def.key_hint != "" and not Platform.mobile_layout:
		var prompt := UiKit.prompt(KEY_PROMPTS.get(def.key_hint, "keyboard/" + def.key_hint.to_lower()), HudStyle.KEY * 0.8)
		prompt.tooltip_text = "Use with %s" % def.key_hint
		bottom.add_child(prompt)
	var buy := Button.new()
	buy.name = "Buy_%s" % def.id
	buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy.custom_minimum_size = Vector2(0, HudStyle.BUTTON_WIDE.y)
	buy.focus_mode = Control.FOCUS_NONE
	buy.expand_icon = false
	buy.add_theme_font_size_override("font_size", HudStyle.FONT_BUTTON)
	buy.add_theme_constant_override("icon_max_width", int(HudStyle.ICON_SMALL))
	buy.pressed.connect(_buy.bind(def))
	bottom.add_child(buy)
	_cards.append({"def": def, "root": card, "level": level, "button": buy})


func _buy(def: UpgradeDef) -> void:
	if _player and is_instance_valid(_player) and _player.can_buy(def):
		_player.request_buy(def)
		_refresh()


func _refresh() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_coins.text = str(_player.coins)
	for card in _cards:
		var def: UpgradeDef = card.def
		var level := _player.upgrade_level(def.id)
		var level_label: Label = card.level
		var button: Button = card.button
		level_label.text = ("Level %d / %d" % [level, def.max_level]) if def.max_level > 1 \
				else ("Owned" if level > 0 else ("Unlock · pick one" if not def.excludes.is_empty() else "Unlock"))
		var locked := _player.is_upgrade_locked(def)
		(card.root as Control).modulate.a = 0.5 if locked else 1.0
		button.icon = null
		if _player.is_upgrade_maxed(def):
			button.text = "Owned" if def.max_level == 1 else "Max"
			button.disabled = true
		elif locked:
			button.text = "Other choice taken"
			button.disabled = true
		else:
			var cost := _player.upgrade_cost(def)
			button.text = "Free" if cost == 0 else str(cost)
			button.icon = null if cost == 0 else COIN_ICON
			button.disabled = not _player.can_buy(def)


## Desktop: a wide sheet at the bottom center, cards in one or two rows. Phones: full width, two columns,
## scrolling, at most half the screen tall.
func _layout() -> void:
	var view := get_viewport().get_visible_rect().size
	var width := minf(HudStyle.UPGRADE_SHEET_WIDTH, view.x - HudStyle.MARGIN * 2.0)
	var card_width := HudStyle.UPGRADE_CARD.x + HudStyle.GAP
	var columns := clampi(int((width - HudStyle.GAP * 4.0) / card_width), 1, maxi(_cards.size(), 1))
	if Platform.mobile_layout and view.x < view.y:
		columns = 2
	_grid.columns = columns
	for card in _cards:
		(card.root as Control).custom_minimum_size.x = (width - HudStyle.GAP * (columns + 3)) / columns \
				if Platform.mobile_layout else HudStyle.UPGRADE_CARD.x
	# Cards grow with their wrapped text: fit the scroll area to the grid (it follows on minimum_size_changed).
	var rows := ceili(float(_cards.size()) / columns)
	var cards_height := maxf(rows * (HudStyle.UPGRADE_CARD.y + HudStyle.GAP), _grid.get_combined_minimum_size().y)
	_scroll.custom_minimum_size.y = minf(cards_height, view.y * 0.5)
	offset_left = -width * 0.5
	offset_right = width * 0.5
	if is_open and (_tween == null or not _tween.is_running()):
		offset_top = -get_combined_minimum_size().y - HudStyle.MARGIN
		offset_bottom = -HudStyle.MARGIN


## Slides to `hidden` (0 = shown at the bottom margin, 1 = below the screen edge).
func _slide(hidden: float) -> void:
	if _tween:
		_tween.kill()
	var height := get_combined_minimum_size().y
	var shown_top := -height - HudStyle.MARGIN
	var from := offset_top
	if hidden == 0.0 and offset_top > shown_top + height * 0.5:
		from = HudStyle.MARGIN
	var to := lerpf(shown_top, HudStyle.MARGIN, hidden)
	offset_top = from
	offset_bottom = from + height
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_method(func(top: float) -> void:
		offset_top = top
		offset_bottom = top + height, from, to, SLIDE_TIME)
	if hidden > 0.0:
		_tween.tween_callback(func() -> void: visible = false)
	else:
		_tween.tween_callback(_layout)  # settle to the final height
