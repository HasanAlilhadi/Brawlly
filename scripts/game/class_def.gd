class_name ClassDef
extends Resource
## A player class (resources/data/classes/*.tres, listed in resources/data/class_catalog.tres): the
## character model, the weapons it fights with (Player.WEAPONS ids, the first one in hand) and the weapon
## its soldiers carry (Ally.WEAPON_STATS). Picked in the multiplayer menu / lobby (Net profile "class").

const CATALOG_PATH := "res://resources/data/class_catalog.tres"

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var model: PackedScene
@export var weapons: PackedStringArray = PackedStringArray()
@export var ally_weapon: String = "sword"
## Game Icon Pack glyph (assets/ui/icons/game/<icon>.svg).
@export var icon: String = "sword"
## Where the fists sit relative to the standard rig's (arm bone space): the keeper's arms are a bit higher
## on their bones, so weapons in hand move with them.
@export var hand_offset: Vector3 = Vector3.ZERO
## Shield on the left arm (none: the class can't block), how much damage it soaks before it breaks, and
## the offset from the model's origin to its middle (shield space; front = +Z).
@export var shield: PackedScene
@export var shield_health: float = 0.0
@export var shield_center: Vector3 = Vector3.ZERO
@export_group("Player color")
## Palette hue of the model recolored to the player's color (see Unit.recolor_*).
@export_range(-1.0, 1.0) var recolor_key_hue: float = -1.0
@export var recolor_hue_range: float = 0.03
@export var recolor_min_saturation: float = 0.6
@export var recolor_reference_value: float = 0.95


static func all() -> Array[ClassDef]:
	return (load(CATALOG_PATH) as ClassCatalog).classes


## The class with `class_id`, or the first one (unknown ids, e.g. an old profile).
static func find(class_id: StringName) -> ClassDef:
	for def in all():
		if def.id == class_id:
			return def
	return all()[0]
