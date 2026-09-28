class_name EnemyRoster
extends Resource
## Which enemy types a camp's squad is made of. Add a RosterEntry to introduce a new enemy type;
## `filler` makes up the rest of the squad.

@export var filler: PackedScene
@export var entries: Array[RosterEntry] = []


## One scene per squad slot. Inner-ring types come first (they take the slots next to the house).
func compose(squad_size: int) -> Array[PackedScene]:
	var inner: Array[PackedScene] = []
	var outer: Array[PackedScene] = []
	for entry in entries:
		for i in entry.count_for(squad_size):
			(inner if entry.inner_ring else outer).append(entry.scene)
	while inner.size() + outer.size() < squad_size:
		outer.append(filler)
	outer.shuffle()
	var slots: Array[PackedScene] = inner
	slots.append_array(outer)
	slots.resize(squad_size)
	return slots
