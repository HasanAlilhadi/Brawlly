extends Node
## Both kinds of enemy attack (a thrown spear, a melee swing) wait briefly before their first use, then use
## their normal cooldowns.

const THROWER_SCENE := preload("res://scenes/characters/enemies/orc_thrower.tscn")
const MELEE_SCENE := preload("res://scenes/characters/enemies/orc_grunt.tscn")


func _ready() -> void:
	var thrower := THROWER_SCENE.instantiate() as Enemy
	var fighter := MELEE_SCENE.instantiate() as Enemy
	var target := Node3D.new()
	target.position = Vector3(6, 0, 0)
	get_tree().root.add_child.call_deferred(thrower)
	get_tree().root.add_child.call_deferred(fighter)
	get_tree().root.add_child.call_deferred(target)
	_check_enemies.call_deferred(thrower, fighter, target)


func _check_enemies(thrower: Enemy, fighter: Enemy, target: Node3D) -> void:
	thrower.set_physics_process(false)
	fighter.set_physics_process(false)
	var throw := thrower.component(ProjectileAttack) as ProjectileAttack
	var throw_action := thrower.action_token
	var throw_delayed := not throw.can_start(target) \
			and is_equal_approx(thrower._first_attack_delay_left, Enemy.FIRST_ATTACK_DELAY) \
			and thrower.action_token == throw_action and is_zero_approx(throw._cooldown_left)
	throw_delayed = throw_delayed and not throw.can_start(target)
	thrower._first_attack_delay_left = 0.0
	var throw_started := throw.can_start(target)
	if throw_started:
		throw.start(target)
	throw_started = throw_started and thrower.action_token != throw_action \
			and throw._cooldown_left >= throw.cooldown * (1.0 - throw.cooldown_jitter)

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
