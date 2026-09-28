class_name RosterEntry
extends Resource
## One enemy type in an EnemyRoster: what share of a camp's squad it makes up, and limits.

@export var scene: PackedScene
## Fraction of the squad (0.25 = a quarter). Rounded; at least 1 once the camp is big enough.
@export_range(0.0, 1.0) var share: float = 0.2
## Only appears in camps with at least this many orcs.
@export var min_squad: int = 1
## Upper limit per camp (0 = no limit).
@export var max_count: int = 0
## Placed in the inner ring next to the house (e.g. giants guarding it).
@export var inner_ring: bool = false


func count_for(squad_size: int) -> int:
	if scene == null or squad_size < min_squad:
		return 0
	var count := maxi(1, roundi(squad_size * share))
	return mini(count, max_count) if max_count > 0 else count
