class_name ConquestLook
## Conquest's own look on its pages (the Conquest hub, Find / Host a Conquest game, its lobby): a dark theme of
## iron and blood laid over the RPG theme (`theme()`, set on the window while a Conquest page shows), the demon
## backdrop (`ConquestBackdrop` instead of the classic camp) and MenuKit's value colors in gold.
## `apply(page)` in a page's _ready: on in the Conquest section (`Net.conquest_section`), back to the classic look
## outside it. main.gd sets the classic look again when a match starts (the HUD keeps the RPG theme).

const INK := Color("f1e6d6")  # text on the dark panels
const INK_FADED := Color(0.94, 0.88, 0.82, 0.68)
const GOLD := Color("f0c069")  # headers, values
const EMBER := Color("ff6a3d")  # titles' glow
const BLOOD := Color("8c1c1c")
const BLOOD_LIGHT := Color("b32a24")
const BLOOD_DARK := Color("3f0c0d")
const IRON := Color(0.075, 0.065, 0.08, 0.93)
const IRON_LIGHT := Color("29232b")
const STONE := Color("3b3439")
const STONE_LIGHT := Color("4d454b")
const EDGE := Color("7a2626")
const GOOD := Color("7ed37a")
const BAD := Color("ff7a66")
const RPG_THEME := preload("res://resources/themes/rpg_theme.tres")

static var _theme: Theme


## Puts the page in Conquest's look (`on`) or the classic one.
static func apply(page: Node, on: bool = Net.conquest_section) -> void:
	var look: Theme = theme() if on else null
	page.get_tree().root.theme = look
	MenuKit.page_theme = look
	for layer in page.find_children("*", "CanvasLayer", false, false):
		for child in layer.get_children():
			if child is Control:
				(child as Control).theme = look  # pages built before (a client's lobby learning the mode)
	MenuKit.accent_color = GOLD if on else MenuKit.ACCENT
	MenuKit.good_color = GOOD if on else MenuKit.GOOD
	MenuKit.bad_color = BAD if on else MenuKit.BAD
	if not on:
		return
	var old := page.get_node_or_null("Backdrop")
	if old and not old is ConquestBackdrop:
		var backdrop := ConquestBackdrop.new()
		backdrop.name = "Backdrop"
		old.name = "ClassicBackdrop"
		old.add_sibling(backdrop)
		page.move_child(backdrop, old.get_index())
		old.free()


## The classic look again (leaving the section, or a match starts).
static func reset(node: Node) -> void:
	node.get_tree().root.theme = null
	MenuKit.page_theme = null
	MenuKit.accent_color = MenuKit.ACCENT
	MenuKit.good_color = MenuKit.GOOD
	MenuKit.bad_color = MenuKit.BAD


static func theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


static func _build() -> Theme:
	var theme := RPG_THEME.duplicate() as Theme
	# Panels: dark iron with a blood-red rim; insets darker, light cards a little lighter.
	var panel := _flat(IRON, EDGE, 2, 12, 26)
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel)
	theme.set_stylebox("panel", "PanelBrown", _flat(BLOOD_DARK, BLOOD, 2, 10, 20))
	theme.set_stylebox("panel", "PanelInset", _flat(Color(0, 0, 0, 0.38), Color(STONE, 0.9), 1, 8, 14))
	theme.set_stylebox("panel", "PanelInsetBrown", _flat(Color(0, 0, 0, 0.5), BLOOD_DARK, 1, 8, 10))
	theme.set_stylebox("panel", "PanelLight", _flat(IRON_LIGHT, Color(GOLD, 0.35), 1, 10, 16))
	theme.set_stylebox("panel", "TooltipPanel", _flat(Color(0.05, 0.04, 0.05, 0.96), EDGE, 1, 6, 10))
	theme.set_color("font_color", "TooltipLabel", INK)

	# Buttons: blood-red main actions, stone for the rest; tabs turn red when picked.
	_button(theme, "Button", BLOOD, BLOOD_LIGHT, Color("6b1414"), Color(GOLD, 0.55))
	_button(theme, "ButtonBeige", STONE, STONE_LIGHT, Color("2e282d"), Color(0.62, 0.55, 0.58, 0.6))
	_button(theme, "ButtonTab", STONE, STONE_LIGHT, BLOOD, Color(0.62, 0.55, 0.58, 0.6))
	var picked := _button_box(BLOOD, Color(GOLD, 0.7))
	theme.set_stylebox("pressed", "ButtonTab", picked)
	theme.set_stylebox("hover_pressed", "ButtonTab", picked)
	theme.set_font_size("font_size", "ButtonTab", 28)
	_button(theme, "ButtonSquare", BLOOD, BLOOD_LIGHT, Color("6b1414"), Color(GOLD, 0.55))
	_button(theme, "OptionButton", STONE, STONE_LIGHT, Color("2e282d"), Color(0.62, 0.55, 0.58, 0.6))
	theme.set_font_size("font_size", "Button", 34)
	theme.set_font_size("font_size", "ButtonBeige", 32)

	# Text fields and dropdown lists.
	var field := _flat(Color(0, 0, 0, 0.5), STONE_LIGHT, 2, 8, 14)
	field.content_margin_left = 20
	field.content_margin_right = 20
	theme.set_stylebox("normal", "LineEdit", field)
	var focused := field.duplicate() as StyleBoxFlat
	focused.border_color = GOLD
	theme.set_stylebox("focus", "LineEdit", focused)
	theme.set_stylebox("read_only", "LineEdit", field)
	theme.set_color("font_color", "LineEdit", INK)
	theme.set_color("font_placeholder_color", "LineEdit", Color(INK, 0.4))
	theme.set_color("caret_color", "LineEdit", GOLD)
	theme.set_stylebox("panel", "PopupMenu", _flat(Color(0.07, 0.06, 0.07, 0.98), EDGE, 2, 8, 14))
	theme.set_color("font_color", "PopupMenu", INK)
	theme.set_color("font_hover_color", "PopupMenu", GOLD)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(BLOOD, 0.55)
	hover.set_corner_radius_all(6)
	theme.set_stylebox("hover", "PopupMenu", hover)

	# Labels: light ink, gold headers, a glowing title.
	theme.set_color("font_color", "Label", INK)
	theme.set_color("font_color", "LabelLight", INK)
	theme.set_color("font_outline_color", "LabelLight", Color(0, 0, 0, 0.9))
	theme.set_color("font_color", "TitleLabel", Color("ffd27a"))
	theme.set_color("font_outline_color", "TitleLabel", Color("400808"))
	theme.set_color("font_color", "HeaderLabel", GOLD)
	theme.set_color("font_color", "HintLabel", INK_FADED)
	theme.set_color("font_color", "KeyCapLabel", INK)
	return theme


static func _flat(fill: Color, border: Color, border_width: int, radius: int, content: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(content)
	box.anti_aliasing = true
	return box


static func _button_box(fill: Color, border: Color) -> StyleBoxFlat:
	var box := _flat(fill, border, 2, 8, 0)
	box.content_margin_left = 28
	box.content_margin_right = 28
	box.content_margin_top = 12
	box.content_margin_bottom = 14
	box.border_width_bottom = 4  # a darker lip, like a pressed-in slab
	box.shadow_color = Color(0, 0, 0, 0.45)
	box.shadow_size = 4
	box.shadow_offset = Vector2(0, 3)
	return box


static func _button(theme: Theme, type: String, fill: Color, lit: Color, down: Color, border: Color) -> void:
	var normal := _button_box(fill, border)
	var hover := _button_box(lit, Color(GOLD, 0.8))
	var pressed := _button_box(down, border)
	pressed.content_margin_top = 15
	pressed.content_margin_bottom = 11
	pressed.shadow_size = 1
	var off := _button_box(Color(STONE, 0.45), Color(STONE_LIGHT, 0.4))
	theme.set_stylebox("normal", type, normal)
	theme.set_stylebox("hover", type, hover)
	theme.set_stylebox("pressed", type, pressed)
	theme.set_stylebox("hover_pressed", type, pressed)
	theme.set_stylebox("disabled", type, off)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		theme.set_color(state, type, INK)
	theme.set_color("font_disabled_color", type, Color(INK, 0.45))
	theme.set_color("font_outline_color", type, Color(0, 0, 0, 0.75))
	theme.set_constant("outline_size", type, 6)
