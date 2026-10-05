class_name MapDef
extends Resource
## One playable map (resources/data/maps/, listed in map_catalog.tres; picked in the lobby, setting `map`).
## `layout` = null: a procedural map (WorldBuilder makes everything from the seed, themed by the "Procedural"
## group: trees, border, decor, landmarks, how many graveyards). Otherwise a designed layout scene (built by a
## tools/build_map_<id>.gd script, editable in the editor) whose `Markers` child holds spots the game fills in:
## `TeamBase_<n>`, `Band_<n>` (metas size / faction / territory), `Chest_<n>` (meta rarity), `Tree_<n>`
## (choppable trees), `Herd_<n>` (meta species). Every map is playable in every mode (`modes` empty).

@export var id: StringName
@export var display_name: String = "Map"
@export_multiline var description: String = ""
## Net.Mode values this map can be played in (empty = every mode; keep it that way).
@export var modes: Array[int] = []
@export var layout: PackedScene
## Half the side of the playable square (designed maps; a procedural map's size comes from the band count).
@export var world_half: float = 52.0
## Team spawn areas (team modes), in team order: two teams use the first two. Co-op modes spawn at the first.
@export var team_bases: PackedVector3Array = PackedVector3Array()
## Where invasion waves march in from (empty = the middle of each map edge).
@export var wave_entries: PackedVector3Array = PackedVector3Array()
## Ground color under the layout.
@export var ground_color: Color = Color(0.44, 0.69, 0.35)

@export_group("Look")
@export var sky_color: Color = Color(0.58, 0.78, 0.92)
@export var ambient_color: Color = Color(0.85, 0.9, 1.0)
@export var ambient_energy: float = 0.55
@export var sun_color: Color = Color.WHITE
@export var sun_energy: float = 1.1
## Mist (0 = none).
@export var fog_color: Color = Color(0.46, 0.46, 0.6)
@export var fog_density: float = 0.0
@export var minimap_color: Color = Color(0.16, 0.3, 0.14, 0.85)

@export_group("Procedural")
## Choppable tree models (GLB paths; empty = the forest trees). Repeat one to make it more common.
@export var tree_models: PackedStringArray = PackedStringArray()
@export var tree_density: float = 1.0
@export var tree_scale: Vector2 = Vector2(1.0, 1.4)
@export var border_model: String = "res://assets/environment/forest/fence.glb"
@export var border_step: float = 1.05
## Moves the border model onto the edge line (Kenney edge pieces sit at the back of their tile).
@export var border_offset: float = 0.0
## Scattered decoration: [model path, count at the reference world size, min scale, max scale] (empty = the
## Wildlands meadow decor).
@export var decor: Array = []
## Extra landmarks WorldBuilder lays out: &"outcrops" (rock outcrops), &"ruins" (courtyards + colonnades), or none.
@export var landmarks: StringName = &""
## Graveyards (and the undead bands at their gates) × this.
@export var graveyard_share: float = 1.0
## The earth disc under a graveyard.
@export var graveyard_ground: Color = Color(0.36, 0.4, 0.29)
## Share of the warbands away from graveyards that are undead anyway.
@export var stray_undead: float = 0.2

@export_group("Objectives")
## Designed maps: the Last Stand circles in order (empty = planned from the seed; procedural maps).
@export var hold_circles: PackedVector3Array = PackedVector3Array()
## Designed maps: gold veins besides the one at every spawn (procedural maps spread their own).
@export var vein_spots: PackedVector3Array = PackedVector3Array()


func supports(match_mode: int) -> bool:
	return modes.is_empty() or modes.has(match_mode)
