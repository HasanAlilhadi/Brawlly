class_name UpgradeSheet
extends PanelContainer
## Bottom sheet with two tabs, opened / closed with T, the gamepad View button or the HUD upgrades button
## (Hud.toggle_upgrades). It slides up from the bottom edge (and back down); the match keeps running.
## - Hero: your class's upgrades (UpgradeDef.classes), then the hero items (UpgradeDef.sheet &"hero": Vitality,
##   Potion). One card each: medal, name, what it does, level, the control that uses it, and a buy button
##   (cost / Owned / Max / the other choice taken). Potion is a consumable: buyable again and again.
## - Army: the army items (UpgradeDef.sheet &"army"): a wide Recruit card (army size, the soldier in training with
##   its countdown, 50 coins, joins you 10 s later), Soldier Damage / Soldier Health (3 levels each) and Command.
## Everything in the game is bought here, anywhere, through Player.request_buy. Esc closes it before the pause
## menu opens. Sizes from HudStyle.

signal toggled_open(open: bool)

const COIN_ICON := preload("res://assets/ui/icons/coin.png")
const KEY_PROMPTS := {"C": "keyboard/c", "E": "keyboard/e", "RMB": "mouse/right"}
const SLIDE_TIME: float = 0.32
const RECRUIT := &"recruit"

var is_open: bool = false
var _player: Player
var _hero_tab: Button
var _army_tab: Button
var _coins: Label
var _hero_grid: GridContainer
var _army_grid: GridContainer
var _scroll: ScrollContainer
var _cards: Array[Dictionary] = []  # {def, root, level, button, grid} (+ recruit: bar, status)
var _tween: Tween
var _settled: bool = false  # fully open and not sliding: layout changes may move it directly


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
	header.add_theme_constant_override("separation", int(HudStyle.GAP))
	column.add_child(header)
	var tabs := ButtonGroup.new()
	_hero_tab = _tab("Hero", "HeroTab", tabs)
	_army_tab = _tab("Army", "ArmyTab", tabs)
	header.add_child(_hero_tab)
	header.add_child(_army_tab)
	_hero_tab.button_pressed = true
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
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
	_coins.custom_minimum_size.x = HudStyle.BADGE
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
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(pages)
	_hero_grid = _grid("UpgradeCards")
	_army_grid = _grid("ArmyCards")
	pages.add_child(_hero_grid)
	pages.add_child(_army_grid)
	_army_grid.visible = false
	tabs.pressed.connect(func(_button: BaseButton) -> void: _show_tab())
	visible = false
	get_viewport().size_changed.connect(_layout)


func _tab(text: String, node_name: String, group: ButtonGroup) -> Button:
	var tab := Button.new()
	tab.name = node_name
	tab.text = text
	tab.theme_type_variation = &"ButtonTab"
	tab.toggle_mode = true
	tab.button_group = group
	tab.focus_mode = Control.FOCUS_NONE
	tab.custom_minimum_size = Vector2(HudStyle.BUTTON_WIDE.x * 0.7, HudStyle.BUTTON_WIDE.y)
	tab.add_theme_font_size_override("font_size", HudStyle.FONT_BUTTON)
	return tab


func _grid(node_name: String) -> GridContainer:
	var grid := GridContainer.new()
	grid.name = node_name
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", int(HudStyle.GAP))
	grid.add_theme_constant_override("v_separation", int(HudStyle.GAP))
	grid.minimum_size_changed.connect(_layout)
	return grid


func set_player(player: Player) -> void:
	_player = player
	player.coins_changed.connect(func(_count: int) -> void: _refresh())
	player.upgrades_changed.connect(_refresh)
	player.health_changed.connect(func(_current: float, _maximum: float) -> void:
		if visible:
			_refresh())
	_hero_tab.text = player.class_def.display_name
	for card in _cards:
		(card.root as Node).queue_free()
	_cards.clear()
	for def in player.class_upgrades():
		_add_card(def, _hero_grid)
	for def in player.sheet_items(&"hero"):
		_add_card(def, _hero_grid)
	for def in player.sheet_items(&"army"):
		if def.id == RECRUIT:
			_add_recruit_card(def)
		else:
			_add_card(def, _army_grid)
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
	_settled = false
	var reversing := visible and _tween != null and _tween.is_running()
	visible = true
	if not reversing:
		_place(1.0)  # start below the bottom edge
		modulate.a = 0.0  # one frame to lay the cards out before measuring the sheet
	_refresh()
	_layout()
	toggled_open.emit(true)
	if not reversing:
		await get_tree().process_frame
		if not is_open:
			return
		_layout()
	_slide(true, reversing)


func close_sheet() -> void:
	if not is_open:
		return
	is_open = false
	_settled = false
	_slide(false, true)
	toggled_open.emit(false)


## Esc / the pause button close the sheet first.
func _input(event: InputEvent) -> void:
	if is_open and (event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause")):
		close_sheet()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if visible and _army_grid.visible:
		_refresh_recruit()


func _show_tab() -> void:
	_hero_grid.visible = _hero_tab.button_pressed
	_army_grid.visible = _army_tab.button_pressed
	_refresh()
	_layout()


# --- Cards ------------------------------------------------------------------------

## The card's medal: Game Icon Pack glyphs by path, the older RPG icons by name (UiKit sizes those).
func _medal(def: UpgradeDef) -> Control:
	var path := def.icon.resource_path
	var icon := path if path.contains("/icons/game/") else path.get_file().get_basename()
	return UiKit.medal(icon, HudStyle.BADGE)


## Card frame + top row (medal, title, level line). Returns {root, box, level}.
func _card_frame(def: UpgradeDef, grid: GridContainer, title_text: String) -> Dictionary:
	var card := PanelContainer.new()
	card.name = "Card_%s" % def.id
	card.theme_type_variation = &"PanelLight"
	card.custom_minimum_size = HudStyle.UPGRADE_CARD
	grid.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(HudStyle.GAP) / 2)
	card.add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", int(HudStyle.GAP))
	box.add_child(top)
	top.add_child(_medal(def))
	var name_box := VBoxContainer.new()
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.alignment = BoxContainer.ALIGNMENT_CENTER
	name_box.add_theme_constant_override("separation", 0)
	top.add_child(name_box)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", HudStyle.FONT_BODY)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_box.add_child(title)
	var level := Label.new()
	level.theme_type_variation = &"HintLabel"
	level.add_theme_font_size_override("font_size", HudStyle.FONT_SMALL)
	name_box.add_child(level)
	return {"root": card, "box": box, "level": level}


func _description(text: String) -> Label:
	var description := Label.new()
	description.text = text
	description.theme_type_variation = &"HintLabel"
	description.add_theme_font_size_override("font_size", HudStyle.FONT_SMALL)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return description


func _buy_button(def: UpgradeDef) -> Button:
	var buy := Button.new()
	buy.name = "Buy_%s" % def.id
	buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy.custom_minimum_size = Vector2(0, HudStyle.BUTTON_WIDE.y)
	buy.focus_mode = Control.FOCUS_NONE
	buy.expand_icon = false
	buy.add_theme_font_size_override("font_size", HudStyle.FONT_BUTTON)
	buy.add_theme_constant_override("icon_max_width", int(HudStyle.ICON_SMALL))
	buy.pressed.connect(_buy.bind(def))
	return buy


func _add_card(def: UpgradeDef, grid: GridContainer) -> void:
	var frame := _card_frame(def, grid, def.title)
	var box: VBoxContainer = frame.box
	box.add_child(_description(def.description))
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", int(HudStyle.GAP))
	box.add_child(bottom)
	if def.key_hint != "" and not Platform.mobile_layout:
		var prompt := UiKit.prompt(KEY_PROMPTS.get(def.key_hint, "keyboard/" + def.key_hint.to_lower()), HudStyle.KEY * 0.8)
		prompt.tooltip_text = "Use with %s" % def.key_hint
		bottom.add_child(prompt)
	var buy := _buy_button(def)
	bottom.add_child(buy)
	_cards.append({"def": def, "root": frame.root, "level": frame.level, "button": buy, "grid": grid})


## Recruit: a double-wide card with the army size, the soldier in training (bar + countdown) and the buy button.
func _add_recruit_card(def: UpgradeDef) -> void:
	var frame := _card_frame(def, _army_grid, "Recruit Soldier")
	var box: VBoxContainer = frame.box
	box.add_child(_description("Trains for %d s, then joins you right here." % int(GameConfig.SOLDIER_TRAIN_TIME)))
	var status := Label.new()
	status.name = "RecruitStatus"
	status.add_theme_font_size_override("font_size", HudStyle.FONT_SMALL)
	box.add_child(status)
	var bar := ProgressBar.new()
	bar.name = "RecruitProgress"
	bar.theme_type_variation = &"ProgressBarGreen"
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, HudStyle.BAR_HEIGHT_SMALL)
	bar.max_value = 1.0
	box.add_child(bar)
	var buy := _buy_button(def)
	box.add_child(buy)
	_cards.append({"def": def, "root": frame.root, "level": frame.level, "button": buy, "grid": _army_grid,
			"bar": bar, "status": status, "wide": true})


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
		if def.id == RECRUIT:
			level_label.text = "Army %d / %d" % [_player.army_size(), _player.follower_cap]
		elif def.is_consumable():
			level_label.text = "Health %d / %d" % [ceili(_player.health), ceili(_player.max_health)]
		elif def.max_level > 1:
			level_label.text = "Level %d / %d" % [level, def.max_level]
		else:
			level_label.text = "Owned" if level > 0 else ("Unlock · pick one" if not def.excludes.is_empty() else "Unlock")
		var locked := _player.is_upgrade_locked(def)
		(card.root as Control).modulate.a = 0.5 if locked else 1.0
		button.icon = null
		if _player.is_upgrade_maxed(def):
			button.text = "Owned" if def.max_level == 1 else "Max"
			button.disabled = true
		elif locked:
			button.text = "Other choice taken"
			button.disabled = true
		elif def.id == RECRUIT and not _player.is_upgrade_useful(def):
			button.text = "Army full"
			button.disabled = true
		elif def.is_consumable() and not _player.is_upgrade_useful(def):
			button.text = "Full health"
			button.disabled = true
		else:
			var cost := _player.upgrade_cost(def)
			button.text = "Free" if cost == 0 else str(cost)
			button.icon = null if cost == 0 else COIN_ICON
			button.disabled = not _player.can_buy(def)
	_refresh_recruit()


## The recruit card's live part: who is training and how long until the next one.
func _refresh_recruit() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	for card in _cards:
		if not card.has("bar"):
			continue
		var bar: ProgressBar = card.bar
		var status: Label = card.status
		var training := _player.soldiers_training
		var parts := PackedStringArray()
		if training > 0:
			var left := _player.next_soldier_in()
			bar.value = 1.0 - left / GameConfig.SOLDIER_TRAIN_TIME
			parts.append("Next soldier in %d s" % ceili(left))
			if training > 1:
				parts.append("%d more queued" % (training - 1))
		else:
			bar.value = 0.0
			parts.append("%d following" % _player.followers().size())
		status.text = "  ·  ".join(parts)
		bar.modulate.a = 1.0 if training > 0 else 0.35
		(card.level as Label).text = "Army %d / %d" % [_player.army_size(), _player.follower_cap]


# --- Layout / slide ------------------------------------------------------------------

## Desktop: a wide sheet at the bottom center, cards in one row (the recruit card is two cards wide). Phones: full
## width, two columns, scrolling, at most half the screen tall.
func _layout() -> void:
	var view := get_viewport().get_visible_rect().size
	var width := minf(HudStyle.UPGRADE_SHEET_WIDTH, view.x - HudStyle.MARGIN * 2.0)
	var card_width := HudStyle.UPGRADE_CARD.x + HudStyle.GAP
	var columns := clampi(int((width - HudStyle.GAP * 4.0) / card_width), 1, 8)
	if Platform.mobile_layout and view.x < view.y:
		columns = 2
	var phone_card := (width - HudStyle.GAP * (columns + 3)) / columns
	for grid in [_hero_grid, _army_grid]:
		(grid as GridContainer).columns = columns
	for card in _cards:
		var base := phone_card if Platform.mobile_layout else HudStyle.UPGRADE_CARD.x
		var wide: bool = card.get("wide", false) and columns > 2
		(card.root as Control).custom_minimum_size.x = base * 2.0 + HudStyle.GAP if wide else base
	# Cards grow with their wrapped text: fit the scroll area to the visible tab's grid.
	var grid: GridContainer = _hero_grid if _hero_grid.visible else _army_grid
	var count := grid.get_child_count()
	var rows := ceili(float(count) / columns)
	var cards_height := maxf(rows * (HudStyle.UPGRADE_CARD.y + HudStyle.GAP), grid.get_combined_minimum_size().y)
	_scroll.custom_minimum_size.y = minf(cards_height, view.y * 0.5)
	offset_left = -width * 0.5
	offset_right = width * 0.5
	if _settled:
		_place(0.0)


## Puts the sheet `hidden` of the way down (0 = shown at the bottom margin, 1 = fully below the screen edge).
func _place(hidden: float) -> void:
	var height := get_combined_minimum_size().y
	var top := lerpf(-height - HudStyle.MARGIN, HudStyle.MARGIN, hidden)
	offset_top = top
	offset_bottom = top + height


## Slides in (`opening`) or out. `from_here` continues from where the sheet is now (a slide reversed halfway),
## else it starts fully hidden. Eases out like a drawer, with a quick fade so it never pops.
func _slide(opening: bool, from_here: bool) -> void:
	if _tween:
		_tween.kill()
	var height := maxf(get_combined_minimum_size().y, 1.0)
	var shown_top := -height - HudStyle.MARGIN
	var hidden_top := HudStyle.MARGIN
	var start := clampf(inverse_lerp(shown_top, hidden_top, offset_top), 0.0, 1.0) if from_here else 1.0
	var finish := 0.0 if opening else 1.0
	_place(start)
	var time := SLIDE_TIME * absf(finish - start)
	_tween = create_tween().set_parallel(true)
	_tween.tween_method(_place, start, finish, maxf(time, 0.01)) \
			.set_trans(Tween.TRANS_QUART if opening else Tween.TRANS_CUBIC) \
			.set_ease(Tween.EASE_OUT if opening else Tween.EASE_IN)
	_tween.tween_property(self, "modulate:a", 1.0 if opening else 0.0, maxf(time * 0.6, 0.01))
	_tween.chain().tween_callback(func() -> void:
		if opening:
			_settled = true
			_layout()
		else:
			visible = false)
