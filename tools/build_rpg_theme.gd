extends SceneTree
## Builds resources/themes/rpg_theme.tres from the Kenney "UI Pack: RPG Expansion" textures.
## Run from the project folder:
##   Godot --headless --path . -s res://tools/build_rpg_theme.gd
## (Tweak colors / margins here and re-run; the theme can also be edited in the Godot editor.)

const UI := "res://assets/ui/"
const OUT := "res://resources/themes/rpg_theme.tres"

const TEXT_LIGHT := Color("fff4de")
const TEXT_DARK := Color("4a2a14")
const OUTLINE_DARK := Color("2b1609")


func _init() -> void:
	var theme := Theme.new()
	theme.default_font_size = 30

	# Buttons: brown wood by default, beige variation.
	_button(theme, "Button", "button_long_brown", "button_long_grey", TEXT_LIGHT, OUTLINE_DARK)
	_button(theme, "ButtonBeige", "button_long_beige", "button_long_grey", TEXT_DARK, Color(1, 1, 1, 0))
	theme.set_type_variation("ButtonBeige", "Button")
	# Small square button (e.g. pause).
	_button(theme, "ButtonSquare", "button_square_brown", "button_square_grey", TEXT_LIGHT, OUTLINE_DARK, 10, 12)
	theme.set_type_variation("ButtonSquare", "Button")

	# Tabs: beige, the selected one (toggle_mode + button_pressed) turns to brown wood.
	_button(theme, "ButtonTab", "button_long_beige", "button_long_grey", TEXT_DARK, Color(1, 1, 1, 0))
	theme.set_type_variation("ButtonTab", "Button")
	var tab_on := _box("buttons/button_long_brown.png", 14, 0)
	tab_on.texture_margin_bottom = 14
	tab_on.content_margin_left = 28
	tab_on.content_margin_right = 28
	tab_on.content_margin_top = 12
	tab_on.content_margin_bottom = 18
	theme.set_stylebox("pressed", "ButtonTab", tab_on)
	theme.set_stylebox("hover_pressed", "ButtonTab", tab_on)
	theme.set_color("font_pressed_color", "ButtonTab", TEXT_LIGHT)
	theme.set_color("font_hover_pressed_color", "ButtonTab", TEXT_LIGHT)
	theme.set_font_size("font_size", "ButtonTab", 28)

	# Key caps for the controls page: a small beige square button with the key's name on it.
	theme.set_type_variation("KeyCap", "PanelContainer")
	var cap := _box("buttons/button_square_beige.png", 10, 0)
	cap.texture_margin_bottom = 14
	cap.content_margin_left = 14
	cap.content_margin_right = 14
	cap.content_margin_top = 6
	cap.content_margin_bottom = 12
	theme.set_stylebox("panel", "KeyCap", cap)
	# Dark wood chip behind input prompts that keep their own colors (mouse / D-pad highlights).
	theme.set_type_variation("PromptChip", "PanelContainer")
	theme.set_stylebox("panel", "PromptChip", _box("panels/panel_inset_brown.png", 10, 4))
	theme.set_type_variation("KeyCapLabel", "Label")
	theme.set_color("font_color", "KeyCapLabel", TEXT_DARK)
	theme.set_font_size("font_size", "KeyCapLabel", 22)

	# Dropdowns look like beige buttons; text fields and popups use the parchment inset.
	_button(theme, "OptionButton", "button_long_beige", "button_long_grey", TEXT_DARK, Color(1, 1, 1, 0))
	theme.set_constant("arrow_margin", "OptionButton", 20)
	var field := _box("panels/panel_inset_beige.png", 14, 14)
	field.content_margin_left = 20
	field.content_margin_right = 20
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_stylebox("focus", "LineEdit", field)
	theme.set_stylebox("read_only", "LineEdit", field)
	theme.set_color("font_color", "LineEdit", TEXT_DARK)
	theme.set_color("font_placeholder_color", "LineEdit", Color(TEXT_DARK, 0.45))
	theme.set_color("caret_color", "LineEdit", TEXT_DARK)
	theme.set_stylebox("panel", "PopupMenu", _box("panels/panel_beige.png", 16, 16))
	theme.set_color("font_color", "PopupMenu", TEXT_DARK)
	theme.set_color("font_hover_color", "PopupMenu", Color("8a4b1c"))
	theme.set_font_size("font_size", "PopupMenu", 30)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.55, 0.35, 0.18, 0.25)
	theme.set_stylebox("hover", "PopupMenu", hover)
	theme.set_stylebox("slider", "HSlider", _bar("back"))
	theme.set_stylebox("grabber_area", "HSlider", _bar("yellow"))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _bar("yellow"))
	theme.set_icon("grabber", "HSlider", _texture("icons/icon_circle_brown.png"))
	theme.set_icon("grabber_highlight", "HSlider", _texture("icons/icon_circle_beige.png"))

	# Panels: parchment by default, wood and inset variations.
	theme.set_stylebox("panel", "PanelContainer", _box("panels/panel_beige.png", 16, 24))
	theme.set_stylebox("panel", "Panel", _box("panels/panel_beige.png", 16, 24))
	theme.set_type_variation("PanelBrown", "PanelContainer")
	theme.set_stylebox("panel", "PanelBrown", _box("panels/panel_brown.png", 16, 20))
	theme.set_type_variation("PanelInset", "PanelContainer")
	theme.set_stylebox("panel", "PanelInset", _box("panels/panel_inset_beige.png", 14, 14))
	theme.set_type_variation("PanelInsetBrown", "PanelContainer")
	theme.set_stylebox("panel", "PanelInsetBrown", _box("panels/panel_inset_brown.png", 14, 10))
	theme.set_type_variation("PanelLight", "PanelContainer")
	theme.set_stylebox("panel", "PanelLight", _box("panels/panel_beige_light.png", 16, 16))
	# Compact variations for the in-game HUD (thin borders, tight padding).
	theme.set_type_variation("PanelCompact", "PanelContainer")
	theme.set_stylebox("panel", "PanelCompact", _box("panels/panel_brown.png", 10, 9))
	theme.set_type_variation("PanelInsetCompact", "PanelContainer")
	theme.set_stylebox("panel", "PanelInsetCompact", _box("panels/panel_inset_brown.png", 10, 6))

	# Labels: dark ink on parchment by default; light variations for HUD / titles.
	theme.set_color("font_color", "Label", TEXT_DARK)
	theme.set_type_variation("LabelLight", "Label")
	theme.set_color("font_color", "LabelLight", TEXT_LIGHT)
	theme.set_color("font_outline_color", "LabelLight", OUTLINE_DARK)
	theme.set_constant("outline_size", "LabelLight", 10)
	theme.set_type_variation("TitleLabel", "Label")
	theme.set_color("font_color", "TitleLabel", Color("ffd98a"))
	theme.set_color("font_outline_color", "TitleLabel", OUTLINE_DARK)
	theme.set_constant("outline_size", "TitleLabel", 22)
	theme.set_font_size("font_size", "TitleLabel", 80)
	# Section headers (brown ink) and small hints (faded ink).
	theme.set_type_variation("HeaderLabel", "Label")
	theme.set_color("font_color", "HeaderLabel", Color("7a3e12"))
	theme.set_font_size("font_size", "HeaderLabel", 34)
	theme.set_type_variation("HintLabel", "Label")
	theme.set_color("font_color", "HintLabel", Color(TEXT_DARK, 0.72))
	theme.set_font_size("font_size", "HintLabel", 20)

	# Progress bars: dark track + colored fill with rounded caps.
	theme.set_stylebox("background", "ProgressBar", _bar("back"))
	theme.set_stylebox("fill", "ProgressBar", _bar("red"))
	for color: String in ["Green", "Blue", "Yellow"]:
		var variation := "ProgressBar" + color
		theme.set_type_variation(variation, "ProgressBar")
		theme.set_stylebox("fill", variation, _bar(color.to_lower()))

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var err := ResourceSaver.save(theme, OUT)
	print("saved %s (error %d)" % [OUT, err])
	quit()


func _texture(path: String) -> Texture2D:
	return load(UI + path) as Texture2D


func _box(path: String, margin: float, content: float) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = _texture(path)
	box.set_texture_margin_all(margin)
	box.set_content_margin_all(content)
	return box


func _button(theme: Theme, type: String, base: String, disabled: String, text: Color,
		outline: Color, side: float = 14.0, content_side: float = 28.0) -> void:
	var normal := StyleBoxTexture.new()
	normal.texture = _texture("buttons/%s.png" % base)
	normal.texture_margin_left = side
	normal.texture_margin_right = side
	normal.texture_margin_top = 10
	normal.texture_margin_bottom = 14  # includes the drop shadow
	normal.content_margin_left = content_side
	normal.content_margin_right = content_side
	normal.content_margin_top = 12
	normal.content_margin_bottom = 18
	var hover := normal.duplicate() as StyleBoxTexture
	hover.modulate_color = Color(1.12, 1.12, 1.12)
	var pressed := normal.duplicate() as StyleBoxTexture
	var pressed_path := "buttons/%s_pressed.png" % base
	if ResourceLoader.exists(UI + pressed_path):
		pressed.texture = _texture(pressed_path)
		pressed.texture_margin_bottom = 10
	pressed.content_margin_top = 16
	pressed.content_margin_bottom = 14
	pressed.modulate_color = Color(0.92, 0.92, 0.92)
	var off := normal.duplicate() as StyleBoxTexture
	off.texture = _texture("buttons/%s.png" % disabled)
	theme.set_stylebox("normal", type, normal)
	theme.set_stylebox("hover", type, hover)
	theme.set_stylebox("pressed", type, pressed)
	theme.set_stylebox("hover_pressed", type, pressed)
	theme.set_stylebox("disabled", type, off)
	theme.set_stylebox("focus", type, _focus_ring())
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		theme.set_color(state, type, text)
	theme.set_color("font_disabled_color", type, Color(text, 0.6))
	theme.set_color("font_outline_color", type, outline)
	theme.set_constant("outline_size", type, 8 if outline.a > 0.0 else 0)
	theme.set_font_size("font_size", type, 36)


## Keyboard / gamepad focus: a gold outline around the button.
func _focus_ring() -> StyleBoxFlat:
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.border_color = Color("ffd98a")
	ring.set_border_width_all(4)
	ring.set_corner_radius_all(10)
	ring.set_expand_margin_all(4)
	return ring


func _bar(color: String) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = _texture("bars/bar_%s_horizontal.png" % color)
	box.texture_margin_left = 9
	box.texture_margin_right = 9
	box.texture_margin_top = 4
	box.texture_margin_bottom = 4
	return box
