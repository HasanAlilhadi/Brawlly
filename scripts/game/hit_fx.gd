class_name HitFx
## Hit feedback: impact bursts, hit flashes, damage numbers, hit-stop and camera kick.
## - Bursts / flashes play on every peer (units trigger them when their replicated health drops).
## - Damage numbers are shown only to the player who landed the hit (`report_hit` on the server
##   sends them to that player's device).

enum Kind { FLESH, WOOD, LEAVES }

const NUMBER_COLOR := Color(1.0, 0.96, 0.82)
const CRIT_COLOR := Color(1.0, 0.72, 0.15)
const HURT_COLOR := Color(1.0, 0.3, 0.25)

## Set by main.gd for the running match.
static var world: Node3D
static var main: Node
static var camera: FollowCamera3D

static var _burst_meshes: Dictionary = {}
static var _stop_until_ms: int = 0
static var _kick_frame: int = -1


## Server: a hit landed on `target` for `amount`. Numbers go to the attacking player's device.
static func report_hit(target: Node3D, amount: float, attacker: Node, crit: bool, is_melee: bool) -> void:
	if not is_instance_valid(target) or attacker == null or not is_instance_valid(attacker):
		return
	# Only hits by players themselves (not their soldiers) show numbers.
	var player := attacker as Player
	if player == null:
		var shooter: Variant = attacker.get("_shooter")
		if is_instance_valid(shooter) and shooter is Player:
			player = shooter
	if player == null:
		return
	MatchStats.on_hit(player.peer_id, amount, is_melee)
	var at := target.global_position + Vector3(0, _number_height(target), 0)
	if player.is_local():
		show_number(at, amount, crit, is_melee)
	elif is_instance_valid(main):
		main.rpc_id(player.peer_id, "_net_hit_number", at, amount, crit, is_melee)


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


## Little burst of chips / sparks at `at`.
static func burst(at: Vector3, kind: Kind, amount: int = 10) -> void:
	if not is_instance_valid(world):
		return
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.emitting = false
	particles.amount = amount
	particles.lifetime = 0.45
	particles.explosiveness = 1.0
	particles.direction = Vector3.UP
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
