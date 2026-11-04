class_name ConquestPanel
extends VBoxContainer
## Conquest HUD, in the HUD's left column (Hud.left_column) under the hero's health and coins:
## - your hero: its weapon, level and the kills to the next one (Player.hero_level / LEVEL_KILLS); unarmed: how
##   to buy a weapon;
## - your faction's supplies: food, weapons, gold in the treasuries, people in the barracks — each with how much
##   comes in and goes out a minute (LogisticsManager "flow": the last minute). Hovering a row (a tap on touch)
##   opens a card beside the panel: where it comes from and where it goes (arming people in barracks, rations,
##   new weapons, gate repairs, soldiers leaving, lords taking gold…);
## - status lines: General, army cap bonus, next meal, and warnings (hungry soldiers, worn weapons, unguarded
##   places) in red.
## Made by main.gd in Conquest; reads the mode every REFRESH seconds. Sizes from HudStyle.

const REFRESH: float = 0.25
## [stock key, name, Game Icon Pack glyph, what the number is].
const ROWS: Array = [
	[&"food", "Food", "heart", "In your places' stores and caravans. Soldiers take a ration from the store they stand near."],
	[&"equipment", "Weapons", "sword", "In your places' stores and caravans. Arming people in the barracks, new weapons for worn ones and gate repairs use them."],
	[&"gold", "Gold", "coin", "In your places' treasuries. A place's lord takes it with F."],
	[&"people", "People", "user_group", "In your barracks, armed or not. The barracks arm them with weapons from the place's store."],
]
const STOCK_KEYS: Dictionary = {&"food": &"food", &"equipment": &"equipment", &"gold": &"gold", &"people": &"barracks"}
const UP := Color(0.6, 1.0, 0.55)
const DOWN := Color(1.0, 0.55, 0.45)
const ALERT := Color(1.0, 0.42, 0.36)
const DETAIL_WIDTH: float = 340.0

var _main: Node
var _mode: ConquestMode
var _hero_title: Label
var _hero_bar: ProgressBar
var _hero_hint: Label
## key -> {"row": PanelContainer, "total": Label, "flow": Label}
var _rows: Dictionary = {}
var _status: Label
var _alerts: Label
var _detail: PanelContainer
var _detail_title: Label
var _detail_hint: Label
var _detail_lines: GridContainer
var _detail_net: Label
var _hovered: StringName = &""
var _timer: float = 0.0


func setup(main: Node, mode: ConquestMode, detail_parent: Control) -> void:
	_main = main
	_mode = mode
	name = "ConquestPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", int(HudStyle.GAP))
	custom_minimum_size.x = HudStyle.LEFT_WIDTH
	_build_hero()
	_build_supplies()
	_build_detail(detail_parent)
	_refresh()


func _panel(box: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"PanelCompact"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	add_child(panel)
	return panel


func _label(font_size: int, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"LabelLight"
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if color != Color.WHITE:
		label.add_theme_color_override("font_color", color)
	return label


func _rows_box(separation: float) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", int(separation))
	return box


func _build_hero() -> void:
	var box := _rows_box(HudStyle.GAP * 0.5)
	_hero_title = _label(HudStyle.FONT_BODY)
	box.add_child(_hero_title)
	_hero_bar = ProgressBar.new()
	_hero_bar.show_percentage = false
	_hero_bar.custom_minimum_size.y = HudStyle.BAR_HEIGHT_SMALL
	_hero_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_hero_bar)
	_hero_hint = _label(HudStyle.FONT_SMALL)
	_hero_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_hero_hint)
	_panel(box)


func _build_supplies() -> void:
	var box := _rows_box(HudStyle.GAP * 0.5)
	for entry: Array in ROWS:
		var key: StringName = entry[0]
		var row := PanelContainer.new()
		row.theme_type_variation = &"PanelInsetCompact"
		row.mouse_filter = Control.MOUSE_FILTER_STOP  # hover / tap shows where it comes from and goes
		row.mouse_default_cursor_shape = Control.CURSOR_HELP
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_constant_override("separation", int(HudStyle.GAP))
		row.add_child(line)
		var icon := TextureRect.new()
		icon.texture = load(UiKit.GLYPHS % entry[2])
		icon.custom_minimum_size = Vector2(HudStyle.ICON_SMALL, HudStyle.ICON_SMALL)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(icon)
		var texts := _rows_box(0.0)
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(texts)
		var total := _label(HudStyle.FONT_BODY)
		texts.add_child(total)
		var flow := _label(HudStyle.FONT_SMALL)
		texts.add_child(flow)
		box.add_child(row)
		row.mouse_entered.connect(_hover.bind(key))
		row.mouse_exited.connect(func() -> void:
			if _hovered == key:
				_hover(&""))
		row.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
				_hover(&"" if _hovered == key else key))
		_rows[key] = {"row": row, "total": total, "flow": flow, "name": entry[1], "hint": entry[3]}
	_status = _label(HudStyle.FONT_SMALL)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	_alerts = _label(HudStyle.FONT_SMALL, ALERT)
	_alerts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_alerts)
	_panel(box)


func _build_detail(parent: Control) -> void:
	_detail = PanelContainer.new()
	_detail.name = "SupplyDetail"
	_detail.theme_type_variation = &"PanelCompact"
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.custom_minimum_size.x = DETAIL_WIDTH
	_detail.visible = false
	var box := _rows_box(HudStyle.GAP * 0.5)
	_detail.add_child(box)
	_detail_title = _label(HudStyle.FONT_BODY)
	box.add_child(_detail_title)
	_detail_hint = _label(HudStyle.FONT_SMALL)
	_detail_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_hint.custom_minimum_size.x = DETAIL_WIDTH - HudStyle.GAP * 3.0
	box.add_child(_detail_hint)
	_detail_lines = GridContainer.new()
	_detail_lines.columns = 2
	_detail_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_lines.add_theme_constant_override("h_separation", int(HudStyle.GAP * 2.0))
	box.add_child(_detail_lines)
	_detail_net = _label(HudStyle.FONT_BODY)
	box.add_child(_detail_net)
	parent.add_child(_detail)


func _hover(key: StringName) -> void:
	_hovered = key
	_detail.visible = key != &""
	_refresh()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = REFRESH
	_refresh()


## This device's faction totals (LogisticsManager.stock, sent to every peer every tick).
func _stock() -> Dictionary:
	if _mode == null or _mode.logistics == null:
		return {}
	return _mode.logistics.stock_of(Net.team_of(Net.my_id()))


## {"in": {reason: n}, "out": {reason: n}} a minute for `key` (empty sides when nothing moved).
func _flow(stock: Dictionary, key: StringName) -> Dictionary:
	var flow: Dictionary = stock.get(&"flow", {}).get(key, {})
	return {"in": flow.get("in", {}), "out": flow.get("out", {})}


static func _sum(side: Dictionary) -> int:
	var total := 0
	for reason in side:
		total += int(side[reason])
	return total


func _refresh() -> void:
	if _mode == null:
		return
	_refresh_hero()
	var stock := _stock()
	visible = not _mode.is_over
	for key: StringName in _rows:
		var parts: Dictionary = _rows[key]
		var flow := _flow(stock, key)
		var gain := _sum(flow["in"])
		var loss := _sum(flow["out"])
		(parts.total as Label).text = "%s  %d" % [parts.name, int(stock.get(STOCK_KEYS[key], 0))]
		var flow_label := parts.flow as Label
		flow_label.text = "+%d  −%d  a minute" % [gain, loss]
		flow_label.add_theme_color_override("font_color", UP if gain >= loss else DOWN)
	_refresh_status(stock)
	if _detail.visible:
		_refresh_detail(stock)
	if not visible:
		_detail.visible = false


func _refresh_hero() -> void:
	var hero: Player = _main.local_player if is_instance_valid(_main.get("local_player")) else null
	if hero == null or hero.class_def == null:
		return
	var level := hero.hero_level
	_hero_title.text = "%s · Level %d" % [hero.class_def.display_name, level]
	var next := hero.kills_for_next_level()
	var floor_kills: int = Player.LEVEL_KILLS[level]
	_hero_bar.visible = next > 0
	if next > 0:
		_hero_bar.max_value = next - floor_kills
		_hero_bar.value = hero.hero_kills - floor_kills
	var hint := "%d / %d kills to level %d (+%d%% health and damage each)" % [hero.hero_kills, next, level + 1,
			roundi(Player.LEVEL_BONUS * 100.0)] if next > 0 else "Top level"
	if hero.class_def.id == Player.START_CLASS:
		hint = "No weapon yet: T → Hero tab to buy one. " + hint
	_hero_hint.text = hint


func _refresh_status(stock: Dictionary) -> void:
	var lines := PackedStringArray()
	var alerts := PackedStringArray()
	if stock.is_empty():
		_status.text = ""
		_alerts.text = ""
		return
	if int(stock.get(&"general", 0)) == Net.my_id():
		lines.append("You are the General")
	if int(stock.get(&"cap_bonus", 0)) > 0:
		lines.append("Army cap +%d from your places" % stock[&"cap_bonus"])
	var meal := int(stock.get(&"meal_in", 0))
	if int(stock.get(&"soldiers", 0)) > 0 and meal > 0:
		lines.append("%d soldiers · next meal in %d:%02d" % [stock[&"soldiers"], meal / 60, meal % 60])
	if int(stock.get(&"starving", 0)) > 0:
		alerts.append("%d soldiers WITHOUT FOOD" % stock[&"starving"])
	if int(stock.get(&"worn", 0)) > 0:
		alerts.append("%d need new weapons (by a supply point)" % stock[&"worn"])
	var team := Net.team_of(Net.my_id())
	var alone := _mode.territories.filter(func(t: TerritoryNode) -> bool:
		return t.state == TerritoryNode.State.OWNED and t.owner_team == team and t.unguarded_left >= 0.0)
	if not alone.is_empty():
		alerts.append("%d UNGUARDED: demons take them (M)" % alone.size())
	_status.text = "\n".join(lines)
	_status.visible = not lines.is_empty()
	_alerts.text = "\n".join(alerts)
	_alerts.visible = not alerts.is_empty()


func _refresh_detail(stock: Dictionary) -> void:
	if not _rows.has(_hovered):
		_detail.visible = false
		return
	var parts: Dictionary = _rows[_hovered]
	var flow := _flow(stock, _hovered)
	_detail_title.text = "%s: %d" % [parts.name, int(stock.get(STOCK_KEYS[_hovered], 0))]
	_detail_hint.text = parts.hint
	for child in _detail_lines.get_children():
		child.queue_free()
	_detail_line("Comes in (a minute)", "", Color.WHITE, HudStyle.FONT_BODY)
	_detail_side(flow["in"], "+", UP)
	_detail_line("Goes out (a minute)", "", Color.WHITE, HudStyle.FONT_BODY)
	_detail_side(flow["out"], "−", DOWN)
	var net := _sum(flow["in"]) - _sum(flow["out"])
	_detail_net.text = "Net: %s%d a minute" % ["+" if net >= 0 else "−", absi(net)]
	_detail_net.add_theme_color_override("font_color", UP if net >= 0 else DOWN)
	# Beside the panel, level with the row, kept on screen.
	var row := parts.row as Control
	var at := Vector2(get_global_rect().end.x + HudStyle.GAP, row.global_position.y)
	var screen := get_viewport().get_visible_rect().size
	at.y = minf(at.y, screen.y - _detail.get_combined_minimum_size().y - HudStyle.MARGIN)
	_detail.global_position = at
	_detail.size = _detail.get_combined_minimum_size()


func _detail_side(side: Dictionary, sign_text: String, color: Color) -> void:
	if side.is_empty():
		_detail_line("   nothing", "", Color(1, 1, 1, 0.6), HudStyle.FONT_SMALL)
		return
	var reasons := side.keys()
	reasons.sort_custom(func(a: String, b: String) -> bool: return int(side[a]) > int(side[b]))
	for reason: String in reasons:
		_detail_line("   " + reason, "%s%d" % [sign_text, int(side[reason])], color, HudStyle.FONT_SMALL)


func _detail_line(left: String, right: String, color: Color, font_size: int) -> void:
	var name_label := _label(font_size)
	name_label.text = left
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_lines.add_child(name_label)
	var amount := _label(font_size, color)
	amount.text = right
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_detail_lines.add_child(amount)
