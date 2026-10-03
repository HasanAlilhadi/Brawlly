extends Node
## Bowman Bow Rain: placement is range-clamped, the marked area appears on an active cast,
## exactly 100 falling arrows are server-spawned inside the area: five aimed, 95 spread randomly.

const ARROW_SCENE := preload("res://scenes/combat/arrow_projectile.tscn")

var t := 0.0
var step := 0
var failures := 0
var main: Node
var player: Player
var target := Vector3.ZERO
var targets: Array[TrainingTarget] = []
var shot := ""
var landings: Array[Vector2] = []
var spawn_frames: Array[int] = []
var all_from_above := true
var all_arrows_scaled := true
var effect_sprites := 0
var effect_bursts := 0
var normal_arrows := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot = arg.substr(7)
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _check(ok: bool, what: String) -> void:
	printerr(("PASS " if ok else "FAIL ") + what)
	if not ok:
		failures += 1


func _on_item_spawned(node: Node) -> void:
	if node is ArrowProjectile and (node as ArrowProjectile).rain_arrow:
		var arrow := node as ArrowProjectile
		landings.append(Vector2(arrow.start.x, arrow.start.z))
		spawn_frames.append(Engine.get_physics_frames())
		all_from_above = all_from_above and is_equal_approx(arrow.start.y, target.y + Player.BOW_RAIN_HEIGHT) \
				and arrow.direction.is_equal_approx(Vector3.DOWN)
		all_arrows_scaled = all_arrows_scaled and is_equal_approx(arrow.get_node("Model").transform.basis.x.length(), 1.1)
	elif node is ArrowProjectile:
		normal_arrows += 1


func _on_world_child_spawned(node: Node) -> void:
	if node is Sprite3D:
		effect_sprites += 1
	elif node is CPUParticles3D:
		effect_bursts += 1


func _process(delta: float) -> void:
	t += delta
	if get_tree().current_scene == null:
		return
	match step:
		0:
			if t < 1.0:
				return
			var button := get_tree().current_scene.find_child("TrainingButton", true, false) as Button
			_check(button != null, "Training Field button exists")
			if button:
				button.pressed.emit()
			step = 1
			t = 0.0
		1:
			if t < 2.5 or get_tree().current_scene.name != "Main":
				return
			main = get_tree().current_scene
			player = main.get("local_player") as Player
			var field := main.get("training_field") as TrainingField
			_check(player != null and field != null, "training player spawned")
			player.global_position = Vector3(5.5, 0.0, -13.0)
			field.update_player(player)
			main.call("_switch_training_class")
			step = 2
			t = 0.0
		2:
			if t < 0.5:
				return
			player = main.get("local_player") as Player
			_check(player != null and player.class_def.ability == &"bow_rain", "Bowman has Bow Rain")
			_check(is_equal_approx(player.class_def.ability_duration, 5.0), "Bow Rain lasts 5 seconds")
			_check(is_equal_approx(Player.BOW_RAIN_RADIUS, 4.05), "Bow Rain circle radius is 4.05")
			player.global_position = Vector3(12.0, 0.0, -1.0)
			player.net_position = player.global_position
			(main.get_node("Camera") as FollowCamera3D).snap()
			for node in get_tree().get_nodes_in_group(&"breakable"):
				if node is TrainingTarget and node.global_position.z < 0.0:
					targets.append(node)
			_check(targets.size() == 3, "three range targets are available")
			(main.get_node("World/Items") as Node).child_entered_tree.connect(_on_item_spawned)
			(main.get_node("World") as Node).child_entered_tree.connect(_on_world_child_spawned)
			var requested := Vector3(14.0, 0.0, -5.0)
			target = requested
			player.set_bow_rain_preview(requested, true)
			_check(player._bow_rain_area.visible and player._bow_rain_area.global_position.distance_to(target) < 0.1,
					"target area follows the selected ground point")
			_check(is_zero_approx(float((player._bow_rain_area.material_override as ShaderMaterial)
					.get_shader_parameter(&"active"))), "placement preview remains steady")
			player.set_bow_rain_preview(requested, false)
			player.set_aim(Vector3.RIGHT)
			player.request_bow_rain(requested)
			_check(player.ability_active, "confirmed target starts Bow Rain")
			_check(player.is_aiming(), "Bow Rain keeps normal bow aim")
			player.face_now(Vector3.BACK)
			_check(player._spin_transform().is_equal_approx(Transform3D.IDENTITY),
					"Bow Rain does not apply Whirlwind rotation to the bow")
			player.shoot(Vector3.RIGHT)
			_check(normal_arrows == 1, "Bowman can shoot a normal arrow during Bow Rain")
			_check(player.bow_rain_target.is_equal_approx(target), "target is clamped to cast range")
			_check(player._bow_rain_area.visible, "large circular area is visible")
			_check(is_equal_approx(float((player._bow_rain_area.material_override as ShaderMaterial)
					.get_shader_parameter(&"active")), 1.0), "active Bow Rain animates the marker")
			step = 3
			t = 0.0
		3:
			if t < 0.35:
				return
			var items := main.get_node("World/Items")
			var arrows := items.get_children().filter(func(node: Node) -> bool: return node is ArrowProjectile)
			_check(arrows.size() >= 2, "Bow Rain continuously spawns falling arrows (%d visible)" % arrows.size())
			_check(landings.size() > 0, "server spawned rain arrows")
			if shot != "":
				get_viewport().get_texture().get_image().save_png(shot)
			step = 4
			t = 0.0
		4:
			if t < player.class_def.ability_duration + Player.BOW_RAIN_HEIGHT / Player.BOW_RAIN_ARROW_SPEED:
				return
			_check(not player.ability_active, "Bow Rain ends after %.0f seconds" % player.class_def.ability_duration)
			_check(not player._bow_rain_area.visible, "area marker hides after Bow Rain")
			_check(landings.size() == Player.BOW_RAIN_TOTAL_ARROWS,
					"Bow Rain spawned exactly %d arrows (got %d)" % [Player.BOW_RAIN_TOTAL_ARROWS, landings.size()])
			_check(effect_sprites >= landings.size() * 2, "each arrow has a spawn and impact flash")
			_check(effect_bursts >= landings.size(), "each arrow impact creates a particle burst")
			_check(all_from_above and Player.BOW_RAIN_HEIGHT >= 6.0, "every arrow falls from well above the target area")
			_check(all_arrows_scaled, "arrow model scale is 1.1")
			var inside := true
			var quadrants := {}
			var max_radius := Player.BOW_RAIN_RADIUS - Player.BOW_RAIN_EDGE_MARGIN
			var aimed_counts := [0, 0, 0]
			for landing in landings:
				var offset := landing - Vector2(target.x, target.z)
				inside = inside and offset.length() <= max_radius + 0.001
				quadrants[Vector2i(1 if offset.x >= 0.0 else -1, 1 if offset.y >= 0.0 else -1)] = true
			_check(inside, "every arrow lands inside the circle")
			_check(quadrants.size() == 4, "random arrows spread across the circle")
			for index in range(landings.size()):
				if index % (Player.BOW_RAIN_TOTAL_ARROWS / Player.BOW_RAIN_TARGETED_ARROWS) \
						!= Player.BOW_RAIN_TOTAL_ARROWS / Player.BOW_RAIN_TARGETED_ARROWS / 2:
					continue
				for target_index in targets.size():
					var training_target := targets[target_index]
					if landings[index].distance_to(Vector2(training_target.global_position.x,
							training_target.global_position.z)) <= Player.BOW_RAIN_EDGE_MARGIN + 0.01:
						aimed_counts[target_index] += 1
			_check(aimed_counts.reduce(func(sum: int, count: int) -> int: return sum + count, 0) \
					== Player.BOW_RAIN_TARGETED_ARROWS and aimed_counts.min() >= 1 \
					and aimed_counts.max() - aimed_counts.min() <= 1,
					"five aimed arrows are shared across all targets inside the circle")
			_check(targets.all(func(training_target: TrainingTarget) -> bool:
				return training_target.total_damage() > 0.0),
				"each practice target is actually hit during Bow Rain")
			var separate_frames := true
			for index in range(1, spawn_frames.size()):
				separate_frames = separate_frames and spawn_frames[index] > spawn_frames[index - 1]
			_check(separate_frames, "arrows spawn one by one, never in a volley")
			var every_block_covers_circle := true
			for block_start in range(0, player._bow_rain_offsets.size(), Player.BOW_RAIN_COVERAGE_BLOCK):
				var block_quadrants := {}
				var radial_bands := {}
				for index in range(block_start, block_start + Player.BOW_RAIN_COVERAGE_BLOCK):
					var offset := player._bow_rain_offsets[index]
					block_quadrants[Vector2i(1 if offset.x >= 0.0 else -1, 1 if offset.y >= 0.0 else -1)] = true
					var band := mini(int(offset.length_squared() / (max_radius * max_radius) \
							* Player.BOW_RAIN_COVERAGE_BLOCK), Player.BOW_RAIN_COVERAGE_BLOCK - 1)
					radial_bands[band] = true
				every_block_covers_circle = every_block_covers_circle and block_quadrants.size() == 4 \
						and radial_bands.size() == Player.BOW_RAIN_COVERAGE_BLOCK
			_check(every_block_covers_circle, "random landing plan covers all directions and radial bands")
			var middle := targets[1]
			var near_miss_from := middle.global_position + Vector3(0.45, 2.0, 0.0)
			var near_miss_to := near_miss_from + Vector3.DOWN * 2.0
			var items := main.get_node("World/Items") as Node
			var ordinary := ARROW_SCENE.instantiate() as ArrowProjectile
			ordinary.start = near_miss_from
			ordinary.direction = Vector3.DOWN
			ordinary.damage = 10.0
			ordinary.team_id = player.team_id
			items.add_child(ordinary)
			var before_graze := middle.total_damage()
			ordinary._hit_something(near_miss_from, near_miss_to)
			_check(is_equal_approx(middle.total_damage(), before_graze),
					"ordinary arrow does not gain the Bow Rain collision size")
			var rain_probe := ARROW_SCENE.instantiate() as ArrowProjectile
			rain_probe.start = near_miss_from
			rain_probe.direction = Vector3.DOWN
			rain_probe.damage = 10.0
			rain_probe.team_id = player.team_id
			rain_probe.rain_arrow = true
			items.add_child(rain_probe)
			rain_probe._hit_something(near_miss_from, near_miss_to)
			_check(is_equal_approx(ArrowProjectile.RAIN_HIT_RADIUS, 0.5)
					and middle.total_damage() > before_graze,
					"Bow Rain's 0.5-radius collision catches a near miss")
			printerr("DONE failures=%d" % failures)
			get_tree().quit()
