class_name MenuKit
## Builders shared by the menu screens (server browser, host screen, lobby, main menu notices), all styled with
## the RPG theme's type variations:
## - `frame(ui, title)`: a full-screen page — title on the backdrop, a top-right tool row, the main body and a
##   bottom button row; `fit_frame()` keeps it at most `MAX_WIDTH` wide (and phone-sized on phones).
## - `dialog(ui, title)`: a modal window over the page (`close_dialog()` removes it).
## - `button()`, `label()`, `icon()`: the recurring small pieces.

const MAX_WIDTH: float = 1600.0
const MARGIN := Vector2(48, 36)  # desktop page margins (phones: 16 / 24)
const DIALOG_WIDTH: float = 720.0
const ACCENT := Color("8a4b1c")  # values on parchment (class names, setting values)
const GOOD := Color("2f7d32")
const BAD := Color("a3361f")
const ICON_LOCK := preload("res://assets/ui/touch/icons/lock.png")
const ICON_SEARCH := preload("res://assets/ui/touch/icons/search.png")
const ICON_REFRESH := preload("res://assets/ui/touch/icons/arrow_rotate.png")
const ICON_CROWN := preload("res://assets/ui/icons/game/crown.svg")


## A full-screen page under `ui` (a CanvasLayer): {"root", "top", "title", "tools", "body", "bottom"}.
## `top` holds the title (left) and `tools` (right); `body` expands; `bottom` is the button row.
static func frame(ui: Node, title_text: String) -> Dictionary:
	var root := MarginContainer.new()
	root.name = "Frame"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	root.add_child(column)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	column.add_child(top)
	var title := label(title_text, &"TitleLabel", 64)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(title)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 10)
	tools.alignment = BoxContainer.ALIGNMENT_END
	tools.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(tools)
	var body := VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	column.add_child(body)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 14)
	column.add_child(bottom)
	var parts := {"root": root, "top": top, "title": title, "tools": tools, "body": body, "bottom": bottom}
	root.resized.connect(fit_frame.bind(parts))  # full screen: follows the window size
	fit_frame(parts)
	return parts


## Centers the page at most MAX_WIDTH wide; phones get small margins and a smaller title.
static func fit_frame(parts: Dictionary) -> void:
	var root: MarginContainer = parts.root
	if not is_instance_valid(root) or not root.is_inside_tree():
		return
	var size := root.get_viewport().get_visible_rect().size
	var compact := is_compact(root)
	var side := 16.0 if compact else maxf(MARGIN.x, (size.x - MAX_WIDTH) * 0.5)
	root.add_theme_constant_override("margin_left", int(side))
	root.add_theme_constant_override("margin_right", int(side))
	root.add_theme_constant_override("margin_top", int(24.0 if compact else MARGIN.y))
	root.add_theme_constant_override("margin_bottom", int(24.0 if compact else MARGIN.y))
	(parts.title as Label).add_theme_font_size_override("font_size", 48 if compact else 64)


## Portrait / narrow screens (phones): pages stack their columns and drop secondary columns.
static func is_compact(node: Node) -> bool:
	var size := node.get_viewport().get_visible_rect().size
	return size.x < size.y or size.x < 1100.0


## A modal window over everything under `ui`: {"overlay", "panel", "body", "buttons"}.
static func dialog(ui: Node, title_text: String) -> Dictionary:
	var overlay := ColorRect.new()
	overlay.name = "Dialog"
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	var width := minf(DIALOG_WIDTH, overlay.get_viewport().get_visible_rect().size.x - 32.0)
	panel.custom_minimum_size = Vector2(width, 0)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	panel.add_child(column)
	column.add_child(label(title_text, &"HeaderLabel", 40))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	column.add_child(body)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 14)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(buttons)
	return {"overlay": overlay, "panel": panel, "body": body, "buttons": buttons}


static func close_dialog(parts: Dictionary) -> void:
	if not parts.is_empty() and is_instance_valid(parts.overlay):
		(parts.overlay as Node).queue_free()


## `primary` = the dark brown main action; otherwise the light beige one.
static func button(text: String, primary: bool = false, min_size: Vector2 = Vector2(200, 80)) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size = min_size
	if not primary:
		result.theme_type_variation = &"ButtonBeige"
	return result


static func label(text: String, variation: StringName = &"", font_size: int = 0) -> Label:
	var result := Label.new()
	result.text = text
	if variation != &"":
		result.theme_type_variation = variation
	if font_size > 0:
		result.add_theme_font_size_override("font_size", font_size)
	return result


static func icon(texture: Texture2D, size: float, tint: Color = Color.WHITE) -> TextureRect:
	var picture := TextureRect.new()
	picture.texture = texture
	picture.custom_minimum_size = Vector2(size, size)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	picture.self_modulate = tint
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return picture
