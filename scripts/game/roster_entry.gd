class_name RosterEntry
extends Resource
## One enemy type in an EnemyRoster: what share of a warband it makes up, from which band size, and limits.

@export var scene: PackedScene
## Fraction of the band (0.25 = a quarter). Rounded; at least 1 once the band is big enough.
@export_range(0.0, 1.0) var share: float = 0.2
## Only appears in bands with at least this many members.
@export var min_squad: int = 1
## Upper limit per band (0 = no limit).
@export var max_count: int = 0
## Leads the band: stands in the middle of the formation (bosses).
@export var leader: bool = false
## Fights from range: marches in the rows at the back.
@export var rear: bool = false


func count_for(squad_size: int) -> int:
	if scene == null or squad_size < min_squad:
		return 0
	var count := maxi(1, roundi(squad_size * share))
	return mini(count, max_count) if max_count > 0 else count
