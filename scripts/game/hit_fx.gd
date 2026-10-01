class_name HitFx
## Hit feedback: impact bursts, hit flashes, damage numbers, hit-stop and camera kick.
## - Bursts / flashes play on every peer (units trigger them when their replicated health drops).
## - Damage numbers are shown only to the player who landed the hit (`report_hit` on the server
##   sends them to that player's device).

enum Kind { FLESH, WOOD, LEAVES, DIRT, METAL }

const NUMBER_COLOR := Color(1.0, 0.96, 0.82)
const CRIT_COLOR := Color(1.0, 0.72, 0.15)
const HURT_COLOR := Color(1.0, 0.3, 0.25)
const COMBO_COLOR := Color(0.45, 0.9, 1.0)
const HIT_SPARK := preload("res://assets/vfx/particles/star_07.png")
const DEATH_SMOKE := preload("res://assets/vfx/particles/smoke_04.png")
const BIG_SMOKE := preload("res://assets/vfx/particles/smoke_10.png")
const COMBO_RING := preload("res://assets/vfx/particles/circle_03.png")
const REVIVE_SPARKLE := preload("res://assets/vfx/particles/magic_04.png")
const BLOCK_RING := preload("res://assets/vfx/particles/circle_02.png")

## Set by main.gd for the running match.
static var world: Node3D
static var main: Node
static var camera: FollowCamera3D

static var _burst_meshes: Dictionary = {}
static var _flash_materials: Dictionary = {}
static var _arc_material: StandardMaterial3D
static var _stop_until_ms: int = 0
static var _kick_frame: int = -1


## Server: a hit landed on `target` for `amount`. Numbers go to the attacking player's device.
static func report_hit(target: Node3D, amount: float, attacker: Node, crit: bool, is_melee: bool) -> void:
	if not is_instance_valid(target):
		return
	# Only hits by players themselves (not their soldiers) show numbers.
	var player := player_of(attacker)
	if player == null:
		return
	MatchStats.on_hit(player.peer_id, amount, is_melee)
	var at := target.global_position + Vector3(0, _number_height(target), 0)
	if player.is_local():
		show_number(at, amount, crit, is_melee)
	elif is_instance_valid(main):
		main.rpc_id(player.peer_id, "_net_hit_number", at, amount, crit, is_melee)


## The player behind a hit: the player itself or the shooter of their arrow (null for soldiers, orcs…).
static func player_of(attacker: Node) -> Player:
	if attacker == null or not is_instance_valid(attacker):
		return null
	if attacker is Player:
		return attacker
	var shooter: Variant = attacker.get("_shooter")
	if is_instance_valid(shooter) and shooter is Player:
		return shooter
	return null


## Server: a combo hit on `target` — "COMBO!" pops up over it on every device.
static func report_combo(target: Node3D) -> void:
	if is_instance_valid(target) and is_instance_valid(main):
		main.rpc("_net_combo", target.global_position + Vector3(0, _number_height(target) + 0.45, 0))


static func show_combo(at: Vector3) -> void:
	if is_instance_valid(world):
		FloatingText3D.spawn(world, at, "COMBO!", COMBO_COLOR, 104, true)
		flash(at - Vector3(0, 0.45, 0), COMBO_RING, COMBO_COLOR, 1.6, 0.35, Vector2(0.4, 1.4))


## The local player's own hit: number + (melee) hit-stop and camera kick.
static func show_number(at: Vector3, amount: float, crit: bool, is_melee: bool) -> void:
	if not is_instance_valid(world):
		return
	var text := ("%d!" % roundi(amount)) if crit else str(roundi(amount))
	FloatingText3D.spawn(world, at, text, CRIT_COLOR if crit else NUMBER_COLOR, 96 if crit else 64, crit)
	# One kick per swing: a cleave hitting several orcs in the same frame shakes / freezes once.
	if is_melee and Engine.get_process_frames() != _kick_frame:
		_kick_frame = Engine.get_process_frames()
		if is_instance_valid(camera):
			camera.shake(0.09 if crit else 0.05, 0.12)
		hit_stop(0.07 if crit else 0.045)


## A brief freeze that makes melee hits feel heavy. Solo only (online it would freeze everyone).
## Overlapping calls extend the running freeze instead of ending it early.
static func hit_stop(seconds: float) -> void:
	if not is_instance_valid(world) or Net.is_online():
		return
	var running := _stop_until_ms > Time.get_ticks_msec()
	_stop_until_ms = maxi(_stop_until_ms, Time.get_ticks_msec() + int(seconds * 1000.0))
	if running:
		return
	Engine.time_scale = 0.05
	var tree := world.get_tree()
	while Time.get_ticks_msec() < _stop_until_ms and is_instance_valid(world):
		await tree.process_frame
	_stop_until_ms = 0
	Engine.time_scale = 1.0


## One billboard sprite (additive glow, or `additive = false` for smoke) (Kenney Particle Pack) that pops from `grow.x` to `grow.y` times
## `size` metres and fades out over `lifetime`. Every peer plays its own.
static func flash(at: Vector3, texture: Texture2D, color: Color, size: float, lifetime: float = 0.25,
		grow: Vector2 = Vector2(0.6, 1.25), additive: bool = true) -> void:
	if not is_instance_valid(world) or texture == null:
		return
	var sprite := Sprite3D.new()
	sprite.texture = texture
	sprite.material_override = _flash_material(texture, additive)
	sprite.modulate = color
	sprite.pixel_size = size / float(texture.get_width())
	sprite.rotation.z = randf() * TAU
	world.add_child(sprite)
	sprite.global_position = at
	sprite.scale = Vector3.ONE * grow.x
	var tween := sprite.create_tween().set_parallel(true)
	tween.tween_property(sprite, "scale", Vector3.ONE * grow.y, lifetime).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(sprite, "modulate:a", 0.0, lifetime).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(sprite.queue_free)


## Sword swing trail: a curved ribbon around `parent` (a child of it, so it moves with it; flat, `height` up) that sweeps across
## `arc_degrees` in front of `yaw` (like `atan2(x, z)`), bright at the blade and fading behind it.
static func swing_arc(parent: Node3D, height: float, yaw: float, radius: float, color: Color, arc_degrees: float = 120.0,
		lifetime: float = 0.26) -> void:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	_ensure_trail_material()
	var mesh := ImmediateMesh.new()
	var ribbon := MeshInstance3D.new()
	ribbon.mesh = mesh
	ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ribbon)
	ribbon.position = Vector3(0, height, 0)
	var half := deg_to_rad(arc_degrees) * 0.5
	var tween := ribbon.create_tween()
	tween.tween_method(func(t: float) -> void: _draw_arc(mesh, yaw, half, radius, color, t), 0.0, 1.0, lifetime)
	tween.tween_callback(ribbon.queue_free)


## A reusable sword trail for continuous attacks. Unlike `swing_arc`, this creates one mesh and leaves its
## lifetime and movement to the caller. This avoids overlapping tweens and node churn during Whirlwind.
static func persistent_swing_arc(parent: Node3D, height: float, radius: float, color: Color,
		arc_degrees: float = 120.0) -> MeshInstance3D:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return null
	_ensure_trail_material()
	var mesh := ImmediateMesh.new()
	var ribbon := MeshInstance3D.new()
	ribbon.mesh = mesh
	ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ribbon)
	ribbon.position = Vector3(0.0, height, 0.0)
	_draw_persistent_arc(mesh, deg_to_rad(arc_degrees) * 0.5, radius, color)
	return ribbon


## Spear stab: a narrow streak that shoots straight out along `yaw` to `length` (the spear's lane), pointed at
## the far end like the spearhead, then fades; a spark pops at the tip.
static func stab(parent: Node3D, height: float, yaw: float, length: float, width: float, color: Color,
		lifetime: float = 0.22) -> void:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	_ensure_trail_material()
	var mesh := ImmediateMesh.new()
	var streak := MeshInstance3D.new()
	streak.mesh = mesh
	streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(streak)
	streak.position = Vector3(0, height, 0)
	streak.rotation.y = yaw
	var tween := streak.create_tween()
	tween.tween_method(func(t: float) -> void: _draw_stab(mesh, length, width, color, t), 0.0, 1.0, lifetime)
	tween.tween_callback(streak.queue_free)
	var tip := parent.global_position + Vector3(sin(yaw), 0.0, cos(yaw)) * length + Vector3(0, height, 0)
	parent.get_tree().create_timer(lifetime * 0.3).timeout.connect(func() -> void:
		flash(tip, HIT_SPARK, Color(color, 0.9), 0.55, 0.14, Vector2(0.4, 1.0)))


## Unshaded, vertex-colored, double-sided: shared by swing trails and stabs.
static func _ensure_trail_material() -> void:
	if _arc_material == null:
		_arc_material = StandardMaterial3D.new()
		_arc_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_arc_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_arc_material.vertex_color_use_as_albedo = true
		_arc_material.cull_mode = BaseMaterial3D.CULL_DISABLED


static func _draw_stab(mesh: ImmediateMesh, length: float, width: float, color: Color, t: float) -> void:
	mesh.clear_surfaces()
	# The tip races out in the first 40%; the tail follows to just behind it; everything fades at the end.
	var start := 0.35
	var tip := lerpf(start, length, 1.0 - pow(1.0 - minf(t / 0.4, 1.0), 3.0))
	var tail := lerpf(start, length * 0.55, clampf((t - 0.25) / 0.75, 0.0, 1.0))
	if tip - tail < 0.05:
		return
	var fade := clampf((1.0 - t) / 0.4, 0.0, 1.0)
	var head := maxf(tip - width * 0.9, tail)
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _arc_material)
	var back := Color(color, 0.0)
	var mid := Color(color, 0.55 * fade)
	var front := Color(color, 0.95 * fade)
	var half := width * 0.5
	for tri in [[Vector3(-half * 0.4, 0, tail), back, Vector3(half * 0.4, 0, tail), back, Vector3(half, 0, head), mid],
			[Vector3(-half * 0.4, 0, tail), back, Vector3(half, 0, head), mid, Vector3(-half, 0, head), mid],
			[Vector3(-half, 0, head), mid, Vector3(half, 0, head), mid, Vector3(0, 0, tip), front]]:
		for i in 3:
			mesh.surface_set_color(tri[i * 2 + 1])
			mesh.surface_add_vertex(tri[i * 2])
	mesh.surface_end()


static func _draw_arc(mesh: ImmediateMesh, yaw: float, half: float, radius: float, color: Color, t: float) -> void:
	mesh.clear_surfaces()
	# The blade sweeps from +half to -half (eased); the trail behind it is ~70% of the arc, and the
	# whole ribbon fades over the last part.
	var head := lerpf(half, -half, 1.0 - pow(1.0 - minf(t * 1.4, 1.0), 2.0))
	var tail := minf(head + half * 2.0 * 0.7, half)
	if tail - head < 0.02:
		return
	var fade := clampf((1.0 - t) / 0.35, 0.0, 1.0)
	var steps := 14
	var inner := radius * 0.4
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _arc_material)
	for i in steps + 1:
		var k := float(i) / steps  # 0 at the blade, 1 at the end of the trail
		var a := yaw + lerpf(head, tail, k)
		var dir := Vector3(sin(a), 0.0, cos(a))
		var alpha := pow(1.0 - k, 1.6) * fade
		var width := lerpf(1.0, 0.45, k)
		mesh.surface_set_color(Color(color, alpha * 0.3))
		mesh.surface_add_vertex(dir * lerpf(radius, inner, width))
		mesh.surface_set_color(Color(color, minf(alpha * 1.3, 1.0)))
		mesh.surface_add_vertex(dir * radius)
	mesh.surface_end()


static func _draw_persistent_arc(mesh: ImmediateMesh, half: float, radius: float, color: Color) -> void:
	mesh.clear_surfaces()
	var steps := 18
	var inner := radius * 0.4
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _arc_material)
	for i in steps + 1:
		var k := float(i) / steps  # 0 at the blade, 1 at the fading end of the trail
		var direction := Vector3(sin(lerpf(-half, half, k)), 0.0, cos(lerpf(-half, half, k)))
		var alpha := pow(1.0 - k, 1.6)
		var width := lerpf(1.0, 0.45, k)
		mesh.surface_set_color(Color(color, alpha * 0.3))
		mesh.surface_add_vertex(direction * lerpf(radius, inner, width))
		mesh.surface_set_color(Color(color, minf(alpha * 1.3, 1.0)))
		mesh.surface_add_vertex(direction * radius)
	mesh.surface_end()


static func _flash_material(texture: Texture2D, additive: bool) -> StandardMaterial3D:
	var key := [texture, additive]
	if _flash_materials.has(key):
		return _flash_materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	_flash_materials[key] = material
	return material


## A hit stopped by a shield at `at`: a quick ring shockwave, bright metal sparks flying out along `normal`
## (the shield's front) and a small "Blocked" (`broken`: wood chips, dust and "Shield broken!").
static func block_impact(at: Vector3, normal: Vector3, broken: bool) -> void:
	flash(at, BLOCK_RING, Color(0.75, 0.9, 1.0, 0.95), 0.9, 0.2, Vector2(0.35, 1.5))
	burst(at, Kind.METAL, 12, normal + Vector3(0, 0.6, 0))
	if broken:
		burst(at, Kind.WOOD, 14)
		flash(at, DEATH_SMOKE, Color(0.8, 0.78, 0.72, 0.8), 1.3, 0.55, Vector2(0.5, 1.4), false)
		FloatingText3D.spawn(world, at + Vector3(0, 1.3, 0), "Shield broken!", Color(1.0, 0.72, 0.35), 46, true)
	else:
		FloatingText3D.spawn(world, at + Vector3(0, 1.2, 0), "Blocked", Color(0.75, 0.9, 1.0), 34)


## Little burst of chips / sparks at `at` (flying out around `direction`).
static func burst(at: Vector3, kind: Kind, amount: int = 10, direction: Vector3 = Vector3.UP) -> void:
	if not is_instance_valid(world):
		return
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.emitting = false
	particles.amount = amount
	particles.lifetime = 0.45
	particles.explosiveness = 1.0
	particles.direction = direction.normalized()
	particles.spread = 75.0
	particles.initial_velocity_min = 2.2
	particles.initial_velocity_max = 4.2
	particles.gravity = Vector3(0, -12, 0)
	particles.scale_amount_min = 0.6
	particles.scale_amount_max = 1.3
	particles.mesh = _burst_mesh()
	var ramp := Gradient.new()
	match kind:
		Kind.FLESH:
			ramp.set_color(0, Color(1.0, 0.95, 0.6))
			ramp.set_color(1, Color(1.0, 0.45, 0.1, 0.0))
		Kind.WOOD:
			ramp.set_color(0, Color(0.72, 0.45, 0.25))
			ramp.set_color(1, Color(0.45, 0.28, 0.15, 0.0))
		Kind.LEAVES:
			ramp.set_color(0, Color(0.45, 0.8, 0.4))
			ramp.set_color(1, Color(0.3, 0.6, 0.25, 0.0))
		Kind.DIRT:
			ramp.set_color(0, Color(0.68, 0.46, 0.27))
			ramp.set_color(1, Color(0.32, 0.18, 0.1, 0.0))
		Kind.METAL:
			ramp.set_color(0, Color(1.0, 1.0, 0.9))
			ramp.set_color(1, Color(1.0, 0.7, 0.25, 0.0))
			particles.scale_amount_min = 0.35
			particles.scale_amount_max = 0.7
			particles.initial_velocity_min = 3.0
			particles.initial_velocity_max = 5.5
			particles.lifetime = 0.3
	particles.color_ramp = ramp
	world.add_child(particles)
	particles.global_position = at
	particles.emitting = true
	particles.finished.connect(particles.queue_free)


static func _burst_mesh() -> Mesh:
	if not _burst_meshes.has("chip"):
		var box := BoxMesh.new()
		box.size = Vector3.ONE * 0.07
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo = true
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		box.material = material
		_burst_meshes["chip"] = box
	return _burst_meshes["chip"]


static func _number_height(target: Node3D) -> float:
	var bar: Variant = target.get("health_bar_height")
	if bar is float:
		return bar + 0.2
	return 3.0 if target is Camp else 1.8
