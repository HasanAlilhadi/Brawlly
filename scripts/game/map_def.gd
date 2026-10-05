class_name MapDef
extends Resource
## One playable map (resources/data/maps/, listed in map_catalog.tres; picked in the lobby, setting `map`).
## `layout` = null: the procedural Wildlands (WorldBuilder makes everything from the seed). Otherwise a
## designed layout scene (built by a tools/build_map_<id>.gd script, editable in the editor) whose `Markers`
## child holds spots the game fills in: `TeamBase_<n>`, `Band_<n>` (metas size / faction / territory),
## `Chest_<n>` (meta rarity), `Tree_<n>` (choppable trees), `Herd_<n>` (meta species).

@export var id: StringName
@export var display_name: String = "Map"
@export_multiline var description: String = ""
## Net.Mode values this map can be played in.
@export var modes: Array[int] = []
@export var layout: PackedScene
## Half the side of the playable square (designed maps; the Wildlands size comes from the band count).
@export var world_half: float = 52.0
## Team spawn areas (team modes), in team order: two teams use the first two.
@export var team_bases: PackedVector3Array = PackedVector3Array()
## Where invasion waves march in from (empty = the middle of each map edge).
@export var wave_entries: PackedVector3Array = PackedVector3Array()
## Ground color under the layout.
@export var ground_color: Color = Color(0.44, 0.69, 0.35)


func supports(match_mode: int) -> bool:
	return modes.is_empty() or modes.has(match_mode)
