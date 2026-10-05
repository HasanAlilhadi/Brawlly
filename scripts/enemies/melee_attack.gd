class_name MeleeAttack
extends EnemyAction
## Swings at the target once it is in reach. Damage, reach, cooldown, clips and cleave come from the
## enemy's Unit exports (melee_*): this component only decides when to swing.


func can_start(target: Node3D) -> bool:
	if enemy._melee_timer > 0.0 or enemy._action_time > 0.0:
		return false
	if enemy.flat_distance_to(target) > enemy.melee_range + Unit.target_radius(target):
		return false
	return enemy.first_attack_ready()


func start(target: Node3D) -> void:
	enemy.face_now(dir_to(target))
	enemy.melee()
