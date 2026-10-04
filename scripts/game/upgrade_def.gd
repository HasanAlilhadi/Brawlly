class_name UpgradeDef
extends Resource
## One item for sale. Two kinds:
## - Stall items (`stalls`): sold at the trading post stalls (see ShopStation).
## - Class upgrades (`classes`): bought anywhere from the upgrades sheet (T, UpgradeSheet) by heroes of those
##   classes; their effects are recomputed from the levels on every peer (Player._apply_class_upgrades()).
## Permanent upgrades have a max level; consumables (max_level 0) can be bought again and again. What it does is
## decided by `id` in Player._apply_upgrade() / Player._apply_class_upgrades().

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
## Stalls that sell it (ShopStation.STALLS ids: blacksmith, armory, healer, barracks).
@export var stalls: Array[StringName] = []
## Also in the upgrades sheet's Army section, bought anywhere (soldiers: Recruit, Soldier Damage / Health).
@export var sheet: bool = false
## Class upgrade for these ClassDef ids (empty = a stall item).
@export var classes: Array[StringName] = []
## Owning any of these upgrades locks this one (a pick-one choice, e.g. Knock Back or Wave).
@export var excludes: Array[StringName] = []
## Control that uses it, shown on its card ("C", "E", "RMB").
@export var key_hint: String = ""


func cost_at(level: int) -> int:
	return roundi(base_cost * pow(cost_growth, level))


func is_consumable() -> bool:
	return max_level <= 0


func is_class_upgrade() -> bool:
	return not classes.is_empty()
