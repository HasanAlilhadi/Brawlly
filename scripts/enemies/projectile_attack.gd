class_name ProjectileAttack
extends EnemyAction
## Throws or shoots at the target from range: a spear, an arrow, a magic bolt (NetSpawn.projectile kinds in
## main.gd). Aims a little ahead of a moving target (`lead`), so standing still is dangerous and moving
## dodges. `count` > 1 fans out a volley.

@export var projectile: StringName = &"spear"
@export var damage: float = 10.0
## Seconds from the start of the animation to the release (at anim_speed 1).
@export var windup: float = 0.24
@export var animation: String = "attack-melee-right"
@export_flags("Right:1", "Left:2") var arms: int = 1
## Seconds of the target's movement aimed ahead.
@export var lead: float = 0.3
@export var count: int = 1
@export var spread_degrees: float = 0.0
@export var release_height: float = 0.7
## Projectile speed (0 = the projectile scene's own).
@export var speed: float = 0.0
## Only shoot with nothing (trees, walls) in the way.
@export var needs_clear_line: bool = true
## The weapon in hand leaves with the throw and comes back a moment later.
@export var hide_hand_item: bool = false


func _wants(target: Node3D) -> bool:
	return enemy.first_attack_ready() and (not needs_clear_line or enemy.clear_line_to(target))


func _begin(target: Node3D) -> void:
	enemy.face_now(dir_to(target))
	enemy.play_action(animation, maxf(windup * 1.7, 0.4) / enemy.anim_speed, arms)
	get_tree().create_timer(windup / enemy.anim_speed).timeout.connect(_release.bind(target))


func _release(target: Node3D) -> void:
	if not is_instance_valid(enemy) or enemy.is_dead or enemy.is_downed or GameConfig.is_gone(target):
		return
	var from := enemy.global_position + Vector3(0, release_height, 0)
	var aim := target.global_position + Vector3(0, 0.5, 0)
	if target is CharacterBody3D:
		aim += (target as CharacterBody3D).velocity * lead
	var dir := aim - from
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.0001 else enemy.facing()
	for i in count:
		var angle := 0.0 if count <= 1 else deg_to_rad(spread_degrees) * (float(i) / (count - 1) - 0.5)
		var shot := dir.rotated(Vector3.UP, angle)
		NetSpawn.projectile(projectile, from + shot * 0.4, shot, damage * power(), enemy, false, true, speed)
	if hide_hand_item and enemy._right_item:
		enemy._right_item.visible = false
		get_tree().create_timer(0.8).timeout.connect(func() -> void:
			if is_instance_valid(enemy) and enemy._right_item:
				enemy._right_item.visible = true)
