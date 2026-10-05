class_name EnemyComponent
extends Node
## One piece of an enemy, built by composition: a child node of an `Enemy` scene that adds one behavior —
## how it moves (EnemyMovement), an attack or ability it uses on its target (EnemyAction) or a passive
## trait (life steal, reassembling, a death burst, enrage, boss…). The Enemy finds its components when it
## is ready and calls the hooks below. Gameplay hooks run on the server only; `show_fx` runs on every peer
## (sent with `enemy.fx(self, event, at, value)`), so effects look the same everywhere.

var enemy: Enemy


## Every peer, from the enemy's _ready (before the first frame).
func setup(owner_enemy: Enemy) -> void:
	enemy = owner_enemy


## Server: every physics frame while the enemy is awake.
func server_tick(_delta: float) -> void:
	pass


## Server: return true to ignore this hit completely (e.g. a ghost while it phases).
func blocks_hit(_amount: float, _attacker: Node3D) -> bool:
	return false


## Server: true while the enemy must not attack (e.g. phasing).
func blocks_attacks() -> bool:
	return false


## Server: the enemy took a hit (after the damage was applied).
func on_damaged(_attacker: Node3D, _amount: float) -> void:
	pass


## Server: one of the enemy's melee swings hit `victim` for `amount`.
func on_hit_dealt(_victim: Node3D, _amount: float) -> void:
	pass


## Server: the enemy is about to die; return true to keep it alive (e.g. a skeleton that falls apart and
## gets back up). Not asked when its band is routed.
func prevents_death() -> bool:
	return false


## Server: the enemy died (its loot is dropped by the Enemy).
func on_died() -> void:
	pass


## Every peer: the enemy fell (hide titles, auras…).
func on_death_visuals() -> void:
	pass


## Every peer: a visual event sent with `enemy.fx(self, event, at, value)`.
func show_fx(_event: int, _at: Vector3, _value: float) -> void:
	pass


## Stat multiplier of this enemy (difficulty × its warband's power): abilities scale their damage with it.
func power() -> float:
	if enemy == null:
		return 1.0
	return enemy.power * (GameConfig.BLOOD_MOON_DAMAGE if GameConfig.blood_moon else 1.0)
