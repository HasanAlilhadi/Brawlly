extends Node
## Controls page (main menu → Controls). Tabs for keyboard & mouse, gamepad, touch and tips; each
## binding is a parchment card: icon, action, a short hint and the keys drawn as key caps
## (KeyCap theme variation). Opens on the tab for the device you're on. Esc / back returns.
## Update the tables below when bindings change.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
## Two columns of cards when the panel is at least this wide.
const TWO_COLUMNS_WIDTH: float = 1150.0

## Each row: [icon, action, hint, key groups]. Key groups are alternatives ("or" between them); the keys
## inside a group belong together (W A S D). A key with a "/" is an input prompt image
## ("keyboard/w", "mouse/left", "xbox/rt", "touch/tap", see assets/ui/prompts/); others are drawn as
## key caps with that text. Icons are Game Icon Pack glyphs (assets/ui/icons/game/).
const KEYBOARD: Array = [
	["cursor_move", "Move", "", [["keyboard/w", "keyboard/a", "keyboard/s", "keyboard/d"], ["keyboard/arrows"]]],
	["user_group", "Choose training hero", "Training Field: stand beside a displayed hero", [["F"]]],
	["spear", "Spear: thrust ⇄ throw", "Spearman only", [["keyboard/e"]]],
	["star_coin", "Special ability", "Charged by 10 XP from fallen enemies · Swordsman: Whirlwind", [["keyboard/x"]]],
	["rotate_right", "Rotate camera", "Turns the view 90° around you", [["keyboard/r"]]],
	["sword", "Sword / spear", "Swings or thrusts toward the cursor", [["mouse/left"]]],
	["bow", "Bow / spear throw", "Hold to aim at the cursor, release to shoot or throw", [["mouse/left"], ["mouse/right"]]],
	["arrow", "Quick attack", "Weapon in hand on the nearest enemy", [["keyboard/j"], ["keyboard/k"]]],
	["shield", "Shield", "Swordsman / Spearman: hold to block hits from the front (walks slower, can't attack)", [["mouse/right"]]],
	["user_group", "Soldiers: follow", "They walk with you in formation", [["keyboard/1"]]],
	["flag", "Soldiers: charge", "They run to the cursor and fight there", [["keyboard/2"]]],
	["shield", "Soldiers: hold", "They guard the spot under the cursor", [["keyboard/3"]]],
	["target", "Soldiers: kill", "They hunt the enemy under the cursor (none there: charge) · or click Kill, then the enemy", [["keyboard/4"]]],
	["location", "Ping", "Attack! · Loot! · Here! for your team", [["G"], ["mouse/scroll"]]],
	["heart", "Call for help", "", [["keyboard/h"]]],
	["shop", "Use a stall", "Shop at a trading post stall you stand at", [["keyboard/b"]]],
	["pause", "Pause", "", [["keyboard/escape"], ["keyboard/p"]]],
	["expand", "Fullscreen", "", [["keyboard/f11"], ["keyboard/alt", "keyboard/enter"]]],
]
const GAMEPAD: Array = [
	["cursor_move", "Move", "", [["xbox/stick_l"]]],
	["spear", "Spear: thrust ⇄ throw", "Spearman only", [["Y"]]],
	["star_coin", "Special ability", "Charged by 10 XP from fallen enemies", [["xbox/stick_r_press"]]],
	["bow", "Aim", "Bow / spear throw, then shoot with RT", [["xbox/stick_r"]]],
	["arrow", "Attack", "Weapon in hand · the nearest enemy when not aiming", [["xbox/rt"], ["xbox/a"], ["xbox/rb"], ["xbox/x"]]],
	["shield", "Shield", "Hold to block hits from the front (turns with the right stick)", [["LT"]]],
	["user_group", "Soldiers: follow", "", [["xbox/dpad_up"]]],
	["flag", "Soldiers: charge", "In front of you", [["xbox/dpad_right"]]],
	["shield", "Soldiers: hold", "In front of you", [["xbox/dpad_down"]]],
	["target", "Soldiers: kill", "The enemy in front of you (none: charge)", [["xbox/b"]]],
	["location", "Ping", "", [["xbox/dpad_left"]]],
	["shop", "Use a stall", "At a trading post stall", [["xbox/lb"], ["xbox/view"]]],
	["pause", "Pause", "", [["xbox/menu"]]],
]
const TOUCH: Array = [
	["cursor_move", "Move", "Drag anywhere on the left side", [["touch/swipe_move"]]],
	["spear", "Spear: thrust ⇄ throw", "Spearman: the small button above the weapon stick", [["touch/tap"]]],
	["sword", "Sword / spear", "Weapon stick: drag to swing that way · tap hits the nearest enemy", [["touch/swipe_move"], ["touch/tap"]]],
	["bow", "Bow / spear throw", "Aim stick: drag to aim, release to shoot · tap auto-aims", [["touch/swipe_move"], ["touch/tap"]]],
	["shield", "Shield", "Hold the shield button left of the weapon stick to block", [["touch/tap"]]],
	["star_coin", "Special ability", "The button above the shield button, lit once charged by 10 XP", [["touch/tap"]]],
	["user_group", "Soldier orders", "The buttons under your soldier count", [["Follow"], ["Charge"], ["Hold"], ["Kill"]]],
	["location", "Ping", "Online games", [["!"]]],
	["shop", "Use a stall", "Tap the stall button at the bottom", [["touch/tap"]]],
	["pause", "Pause", "", [["II"]]],
]
const TIPS: Array = [
	["shop", "Trading post", "Stalls around your spawn: Blacksmith, Bows & Spears, Healer, Barracks", []],
	["health", "Revive", "Stand next to a downed teammate for 3 seconds", []],
	["tent", "Destroy the camps", "A camp's surviving orcs fall with it and drop their loot", []],
	["flag", "Orders come first", "Soldiers drop any fight to follow, charge or hold the moment you say so", []],
	["user_group", "Barracks", "Buy soldiers (50 coins, 10 s each), then take them at the pen gate · army 10, Command raises it to 15", []],
	["star_coin", "Treasure goblin", "Every hit spills coins — catch it before it escapes", []],
	["boss", "Orc Warlord", "Bring it down and its warband is routed", []],
	["skull", "Revive or finish", "Orcs leave downed archers alone, enemy players don't", []],
]
const TABS: Array = [["Keyboard & mouse", KEYBOARD], ["Gamepad", GAMEPAD], ["Touch", TOUCH], ["Tips", TIPS]]

@onready var _panel: Control = $UI/Panel
@onready var _tabs: HBoxContainer = %Tabs
@onready var _grid: GridContainer = %Grid
@onready var _back_button: Button = %BackButton

var _current: int = 0
var _tab_buttons: Array[Button] = []


func _ready() -> void:
	var group := ButtonGroup.new()
	for i in TABS.size():
		var tab := Button.new()
		tab.text = TABS[i][0]
		tab.theme_type_variation = &"ButtonTab"
		tab.toggle_mode = true
		tab.button_group = group
		tab.custom_minimum_size = Vector2(0, 76)
		tab.pressed.connect(_show_tab.bind(i))
		_tabs.add_child(tab)
		_tab_buttons.append(tab)
	_back_button.pressed.connect(_back)
	get_viewport().size_changed.connect(_fit_columns)
	_show_tab(2 if Platform.mobile_layout else 0)
	if not OS.has_feature("mobile"):
		_tab_buttons[_current].grab_focus.call_deferred()


func _show_tab(index: int) -> void:
	_current = index
	for i in _tab_buttons.size():
		_tab_buttons[i].set_pressed_no_signal(i == index)
	for child in _grid.get_children():
		child.queue_free()
	for row in TABS[index][1]:
		_grid.add_child(_card(row[0], row[1], row[2], row[3]))
	_fit_columns()


func _fit_columns() -> void:
	_grid.columns = 2 if _panel.size.x >= TWO_COLUMNS_WIDTH else 1
	# Tabs: short labels on narrow screens so all four fit.
	for i in _tab_buttons.size():
		var label: String = TABS[i][0]
		_tab_buttons[i].text = label.get_slice(" ", 0) if _panel.size.x < 900.0 else label
		_tab_buttons[i].add_theme_font_size_override("font_size", 22 if _panel.size.x < 900.0 else 28)


## One binding: [icon] Action / hint ........ [key] or [key]
func _card(icon: String, action: String, hint: String, groups: Array) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"PanelInset"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)

	row.add_child(UiKit.medal(icon, 56.0))

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	var name_label := Label.new()
	name_label.text = action
	name_label.theme_type_variation = &"HeaderLabel"
	name_label.add_theme_font_size_override("font_size", 26)
	text.add_child(name_label)
	if hint != "":
		var hint_label := Label.new()
		hint_label.text = hint
		hint_label.theme_type_variation = &"HintLabel"
		hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(hint_label)

	if not groups.is_empty():
		var keys := HBoxContainer.new()
		keys.add_theme_constant_override("separation", 6)
		keys.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(keys)
		for i in groups.size():
			if i > 0:
				var alternative := Label.new()
				alternative.text = "or"
				alternative.theme_type_variation = &"HintLabel"
				keys.add_child(alternative)
			for key in groups[i]:
				keys.add_child(UiKit.prompt(key) if "/" in key else _key_cap(key))
	return card


func _key_cap(key: String) -> Control:
	var cap := PanelContainer.new()
	cap.theme_type_variation = &"KeyCap"
	cap.custom_minimum_size = Vector2(44, 0)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var label := Label.new()
	label.text = key
	label.theme_type_variation = &"KeyCapLabel"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_child(label)
	return cap


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()
	elif event.is_action_pressed("ui_page_down"):
		_show_tab((_current + 1) % TABS.size())
	elif event.is_action_pressed("ui_page_up"):
		_show_tab((_current + TABS.size() - 1) % TABS.size())


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()


func _back() -> void:
	if is_inside_tree():
		get_tree().change_scene_to_file(MENU_SCENE)
