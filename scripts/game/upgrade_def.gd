class_name UpgradeDef
extends Resource
## One item in the shop. Permanent upgrades have a max level; consumables (max_level 0) can be
## bought again and again. What it does is decided by `id` in Player._apply_upgrade().

@export var id: StringName
@export var title: String
@export_multiline var description: String
@export var icon: Texture2D
@export var base_cost: int = 30
## Each purchase multiplies the price by this.
@export var cost_growth: float = 1.5
## 0 = consumable (no limit).
@export var max_level: int = 5
## Effect strength per purchase (meaning depends on id: +health, +% damage, soldiers, …).
@export var amount: float = 0.0


func cost_at(level: int) -> int:
	return roundi(base_cost * pow(cost_growth, level))


func is_consumable() -> bool:
	return max_level <= 0
