extends Node
## Both enemy weapons wait briefly before their first attack, then use normal cooldowns.

const THROWER_SCENE := preload("res://scenes/characters/enemy_thrower.tscn")
const MELEE_SCENE := preload("res://scenes/characters/enemy.tscn")


func _ready() -> void:
	var thrower := THROWER_SCENE.instantiate() as Enemy
	var fighter := MELEE_SCENE.instantiate() as Enemy
	get_tree().root.add_child.call_deferred(thrower)
	get_tree().root.add_child.call_deferred(fighter)
	_check_enemies.call_deferred(thrower, fighter)


func _check_enemies(thrower: Enemy, fighter: Enemy) -> void:
	thrower.set_physics_process(false)
	fighter.set_physics_process(false)
	var throw_action := thrower.action_token
	thrower._try_throw()
	var throw_delayed := is_equal_approx(thrower._first_attack_delay_left, Enemy.FIRST_ATTACK_DELAY) \
			and thrower.action_token == throw_action and is_zero_approx(thrower._throw_timer)
	thrower._try_throw()
	throw_delayed = throw_delayed and thrower.action_token == throw_action
	thrower._first_attack_delay_left = 0.0
	thrower._try_throw()
	var throw_started := thrower.action_token != throw_action \
			and thrower._throw_timer >= thrower.throw_cooldown * 0.85

	var melee_action := fighter.action_token
	var melee_delayed := not fighter.melee() \
			and is_equal_approx(fighter._first_attack_delay_left, Enemy.FIRST_ATTACK_DELAY) \
			and fighter.action_token == melee_action and is_zero_approx(fighter._melee_timer)
	melee_delayed = melee_delayed and not fighter.melee() and fighter.action_token == melee_action
	fighter._first_attack_delay_left = 0.0
	var melee_started := fighter.melee() and fighter.action_token != melee_action \
			and is_equal_approx(fighter._melee_timer, fighter.melee_cooldown)

	printerr(("PASS " if throw_delayed else "FAIL ") + "thrower waits 0.25 seconds before its first attack")
	printerr(("PASS " if throw_started else "FAIL ") + "thrower uses its normal cooldown afterward")
	printerr(("PASS " if melee_delayed else "FAIL ") + "melee orc waits 0.25 seconds before its first attack")
	printerr(("PASS " if melee_started else "FAIL ") + "melee orc uses its normal cooldown afterward")
	get_tree().quit(0 if throw_delayed and throw_started and melee_delayed and melee_started else 1)
