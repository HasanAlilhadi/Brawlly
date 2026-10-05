class_name BossTrait
extends EnemyComponent
## Makes the enemy a boss: its name over its head, a health bar at the top of the screen while it is near
## (HUD, group `bosses`), and when it falls the rest of its warband is routed (they fall and drop their loot)
## and a pile of coins spills. Bosses of roaming bands stay hidden (their band's minimap badge pulses); the
## Warlord event calls `track()` for a minimap badge / off-screen arrow (group `tracked`).

@export var title: String = "Boss"
@export var marker_color: Color = Color(1.0, 0.3, 0.25)
@export var marker_icon: Texture2D
## The icon is a face (drawn round, filling the badge).
@export var portrait: bool = false
@export var title_color: Color = Color(1.0, 0.45, 0.35)
## Coins spilled around it when it falls (on top of its normal drop).
@export var bounty_coins: int = 100

var _title: Label3D


func setup(owner_enemy: Enemy) -> void:
	super(owner_enemy)
	enemy.add_to_group(&"bosses")
	enemy.set_meta(&"marker_color", marker_color)
	enemy.set_meta(&"marker_label", title)
	if marker_icon:
		enemy.set_meta(&"marker_icon", marker_icon)
		enemy.set_meta(&"marker_portrait", portrait)
	_title = Label3D.new()
	_title.text = title
	_title.font_size = 64
	_title.outline_size = 16
	_title.pixel_size = 0.006
	_title.modulate = title_color
	_title.outline_modulate = Color(0.15, 0.0, 0.0, 0.95)
	_title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_title.no_depth_test = true
	_title.position = Vector3(0, enemy.health_bar_height + 0.35, 0)
	enemy.add_child.call_deferred(_title)
	if enemy.tracked:
		track()


## Every peer: a minimap badge and an off-screen arrow while it lives (world events).
func track() -> void:
	enemy.add_to_group(&"tracked")


## Every peer: off the HUD / minimap.
func on_death_visuals() -> void:
	enemy.remove_from_group(&"tracked")
	enemy.remove_from_group(&"bosses")
	if _title:
		_title.hide()


## Server: the bounty spills and the band is routed.
func on_died() -> void:
	for i in 10:
		Pickup.drop(enemy.get_parent(), enemy.global_position + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5)),
				Pickup.Kind.COIN, roundi(bounty_coins * enemy.coin_multiplier / 10.0))
	if is_instance_valid(enemy.band):
		enemy.band.rout(enemy)
