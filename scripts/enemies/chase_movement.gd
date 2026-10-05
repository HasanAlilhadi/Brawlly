class_name ChaseMovement
extends EnemyMovement
## Runs straight at its target and spreads out around it with the others (Unit.engage). Heavy creatures
## (`shoulders_through`) don't step around smaller units in their way — they shove through them.

@export var shoulders_through: bool = false


func setup(owner_enemy: Enemy) -> void:
	super(owner_enemy)
	if shoulders_through:
		enemy.separation_strength = 0.2
