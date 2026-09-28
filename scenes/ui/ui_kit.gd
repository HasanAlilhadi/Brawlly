class_name UiKit
## Small builders for recurring pieces of the RPG UI look (controls page, HUD, end screen):
## - `medal(icon)`: a round wooden medal (the kit's round button) with an icon on it.
## - `prompt(id)`: an input prompt (Kenney Input Prompts: "keyboard/w", "mouse/left", "xbox/rt", "touch/tap").

const MEDAL := preload("res://assets/ui/buttons/button_round_brown.png")
## Glyphs from the Game Icon Pack (white, drawn light on the medal) — preferred.
const GLYPHS := "res://assets/ui/icons/game/%s.svg"
## Older color icons (assets/ui/icons/): game icons have lots of empty border (shown bigger).
const ICONS := "res://assets/ui/icons/%s.png"
const PADDED_ICONS: PackedStringArray = ["sword", "bow", "soldier", "potion", "shield", "banner", "orc"]
const MEDIUM_ICONS: PackedStringArray = ["coin", "camp", "arrow"]
const GLYPH_COLOR := Color("fff4de")
const PROMPTS := "res://assets/ui/prompts/%s.png"
## Prompts are white; on parchment they are drawn in dark ink (colored gamepad buttons keep their colors).
const PROMPT_INK := Color("4a2a14")
const COLORED_PROMPTS: PackedStringArray = ["xbox/a", "xbox/b", "xbox/x", "xbox/y"]


## A round wooden medal with `icon` on it: a Game Icon Pack glyph name ("crown"), an old icon name
## from assets/ui/icons/ ("sword"), or a full res:// path.
static func medal(icon: String, size: float = 60.0) -> Control:
	var badge := TextureRect.new()
	badge.texture = MEDAL
	badge.custom_minimum_size = Vector2(size, size)
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var picture := TextureRect.new()
	var inset := 0.22
	if icon.begins_with("res://"):
		picture.texture = load(icon)
	elif ResourceLoader.exists(GLYPHS % icon):
		picture.texture = load(GLYPHS % icon)
		picture.self_modulate = GLYPH_COLOR
		inset = 0.26
	else:
		picture.texture = load(ICONS % icon)
		inset = -0.08 if icon in PADDED_ICONS else (0.04 if icon in MEDIUM_ICONS else 0.22)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The round button has a drop shadow at the bottom, so the icon sits a little high.
	picture.offset_left = size * inset
	picture.offset_right = -size * inset
	picture.offset_top = size * (inset - 0.03)
	picture.offset_bottom = -size * (inset + 0.05)
	badge.add_child(picture)
	return badge


## An input prompt image, `height` px tall ("keyboard/w", "mouse/left", "xbox/rt", "touch/tap").
static func prompt(id: String, height: float = 52.0) -> Control:
	var picture := TextureRect.new()
	picture.texture = load(PROMPTS % id)
	picture.custom_minimum_size = Vector2(height, height)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if id in COLORED_PROMPTS:
		return picture
	if id.begins_with("mouse/") or id.contains("dpad"):
		# The red highlight shows which button / direction: keep the colors, on dark wood.
		var chip := PanelContainer.new()
		chip.theme_type_variation = &"PromptChip"
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		picture.custom_minimum_size = Vector2(height, height) * 0.85
		chip.add_child(picture)
		return chip
	picture.self_modulate = PROMPT_INK
	return picture
