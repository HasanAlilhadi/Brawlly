class_name ClassPicker
extends VBoxContainer
## Row of class tabs (one per ClassDef, with its icon) and the picked class's description below.
## Used in the multiplayer menu and the lobby; `picked` fires when the player clicks another class.

signal picked(class_id: StringName)

var _tabs: Dictionary = {}  # class id -> Button
var _hint: Label
var _selected: StringName


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	var group := ButtonGroup.new()
	for def in ClassDef.all():
		var tab := Button.new()
		tab.theme_type_variation = &"ButtonTab"
		tab.toggle_mode = true
		tab.button_group = group
		tab.text = def.display_name
		tab.icon = load(UiKit.GLYPHS % def.icon)
		tab.expand_icon = true
		tab.add_theme_constant_override("icon_max_width", 34)
		# White glyphs: dark ink on the light tab, light on the pressed (dark) one.
		for state in ["icon_normal_color", "icon_hover_color", "icon_focus_color", "icon_disabled_color"]:
			tab.add_theme_color_override(state, UiKit.PROMPT_INK)
		for state in ["icon_pressed_color", "icon_hover_pressed_color"]:
			tab.add_theme_color_override(state, UiKit.GLYPH_COLOR)
		tab.add_theme_font_size_override("font_size", 26)
		tab.custom_minimum_size = Vector2(0, 72)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(func() -> void:
			if def.id != _selected:
				select(def.id)
				picked.emit(def.id))
		row.add_child(tab)
		_tabs[def.id] = tab
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 22)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_hint)
	select(_selected if _selected != &"" else ClassDef.all()[0].id)


## Shows `class_id` as picked (no signal).
func select(class_id: StringName) -> void:
	var def := ClassDef.find(class_id)
	_selected = def.id
	if not is_node_ready():
		return
	for id in _tabs:
		(_tabs[id] as Button).set_pressed_no_signal(id == def.id)
	_hint.text = def.description
