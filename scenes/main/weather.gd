class_name Weather
extends Node
## What the world events look like, on every peer (WorldEvents calls it from its RPCs; no gameplay here):
## - thunderstorm: the light dims and turns cold, rain falls around the camera, lightning bolts flash;
## - Blood Moon: a dark red night;
## - meteors falling from the sky and their impacts (scorch marks);
## - the supply crate drifting down under its parachute (tracked on the minimap while it falls).
## Light changes blend from the match's own sun / environment and back.

const SCORCH := preload("res://assets/vfx/particles/scorch_01.png")
const FIRE := preload("res://assets/vfx/particles/fire_01.png")
const GLOW := preload("res://assets/vfx/particles/light_01.png")
const CRATE := preload("res://assets/environment/dungeon/chest.glb")
const STORM_SKY := Color(0.32, 0.36, 0.42)
const STORM_SUN := Color(0.7, 0.78, 0.95)
const BLOOD_SKY := Color(0.22, 0.04, 0.06)
const BLOOD_SUN := Color(1.0, 0.35, 0.3)
const BLOOD_AMBIENT := Color(0.9, 0.35, 0.35)
## Rain drops around the camera (fewer on phones).
const RAIN_DESKTOP: int = 700
const RAIN_MOBILE: int = 260

var storm: bool = false
var blood_moon: bool = false

var _main: Node
var _sun: DirectionalLight3D
var _environment: Environment
var _base_sun_energy: float
var _base_sun_color: Color
var _base_ambient_energy: float
var _base_ambient_color: Color
var _base_sky: Color
var _light_tween: Tween
var _rain: CPUParticles3D


func setup(main: Node) -> void:
	name = "Weather"
	_main = main
	_sun = main.get_node_or_null("Sun") as DirectionalLight3D
	var world_environment := main.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_environment:
		_environment = world_environment.environment
	if _sun:
		_base_sun_energy = _sun.light_energy
		_base_sun_color = _sun.light_color
	if _environment:
		_base_ambient_energy = _environment.ambient_light_energy
		_base_ambient_color = _environment.ambient_light_color
		_base_sky = _environment.background_color


func _exit_tree() -> void:
	# The environment resource is shared with the scene file: put it back.
	if _environment:
		_environment.ambient_light_energy = _base_ambient_energy
		_environment.ambient_light_color = _base_ambient_color
		_environment.background_color = _base_sky


func _process(_delta: float) -> void:
	if _rain:
		var camera := HitFx.camera
		var center: Vector3 = camera.target.global_position if is_instance_valid(camera) and is_instance_valid(camera.target) \
				else Vector3.ZERO
		_rain.global_position = center + Vector3(0, 11.0, 0)


# --- Storm / Blood Moon -------------------------------------------------------------------------

func set_storm(on: bool) -> void:
	storm = on
	_blend_light(2.5)
	if on and _rain == null:
		_rain = _make_rain()
		_main.world.add_child(_rain)
	elif not on and _rain:
		_rain.emitting = false
		var rain := _rain
		_rain = null
		get_tree().create_timer(1.5).timeout.connect(rain.queue_free)


func set_blood_moon(on: bool) -> void:
	blood_moon = on
	_blend_light(3.0)


## Sun, ambient light and sky toward the current weather (`seconds` to get there).
func _blend_light(seconds: float) -> void:
	if _sun == null or _environment == null:
		return
	var sun_energy := _base_sun_energy
	var sun_color := _base_sun_color
	var ambient_energy := _base_ambient_energy
	var ambient_color := _base_ambient_color
	var sky := _base_sky
	if blood_moon:
		sun_energy = _base_sun_energy * 0.35
		sun_color = BLOOD_SUN
		ambient_energy = _base_ambient_energy * 0.75
		ambient_color = BLOOD_AMBIENT
		sky = BLOOD_SKY
	elif storm:
		sun_energy = _base_sun_energy * 0.45
		sun_color = STORM_SUN
		ambient_energy = _base_ambient_energy * 0.8
		sky = STORM_SKY
	if _light_tween:
		_light_tween.kill()
	_light_tween = create_tween().set_parallel(true)
	_light_tween.tween_property(_sun, "light_energy", sun_energy, seconds)
	_light_tween.tween_property(_sun, "light_color", sun_color, seconds)
	_light_tween.tween_property(_environment, "ambient_light_energy", ambient_energy, seconds)
	_light_tween.tween_property(_environment, "ambient_light_color", ambient_color, seconds)
	_light_tween.tween_property(_environment, "background_color", sky, seconds)


func _make_rain() -> CPUParticles3D:
	var rain := CPUParticles3D.new()
	rain.name = "Rain"
	rain.amount = RAIN_MOBILE if Platform.mobile_layout else RAIN_DESKTOP
	rain.lifetime = 0.75
	rain.local_coords = false
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(22.0, 0.5, 16.0)
	rain.direction = Vector3(0.15, -1.0, 0.1)
	rain.spread = 2.0
	rain.gravity = Vector3.ZERO
	rain.initial_velocity_min = 16.0
	rain.initial_velocity_max = 20.0
	var drop := QuadMesh.new()
	drop.size = Vector2(0.03, 0.55)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.75, 0.85, 1.0, 0.45)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	drop.material = material
	rain.mesh = drop
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return rain


## A bolt from the sky at `at`: a bright beam, a flash of light over everything, sparks and a jolt nearby.
func lightning(at: Vector3) -> void:
	var beam := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.22, 30.0, 0.22)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.85, 0.92, 1.0)
	box.material = material
	beam.mesh = box
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_main.world.add_child(beam)
	beam.global_position = at + Vector3(0, 15.0, 0)
	beam.rotation.z = randf_range(-0.06, 0.06)
	var fade := beam.create_tween()
	fade.tween_interval(0.08)
	fade.tween_property(beam, "scale", Vector3(0.1, 1.0, 0.1), 0.12)
	fade.tween_callback(beam.queue_free)
	HitFx.flash(at + Vector3(0, 0.5, 0), GLOW, Color(0.7, 0.85, 1.0, 1.0), 6.0, 0.35, Vector2(0.4, 1.3))
	HitFx.flash(at + Vector3(0, 0.2, 0), HitFx.COMBO_RING, Color(0.8, 0.9, 1.0, 0.9), 4.5, 0.3, Vector2(0.3, 1.2))
	HitFx.burst(at + Vector3(0, 0.3, 0), HitFx.Kind.METAL, 18)
	_scorch(at, 1.6)
	if _sun:
		var flash := create_tween()
		var energy := _sun.light_energy
		flash.tween_property(_sun, "light_energy", energy + 2.2, 0.05)
		flash.tween_property(_sun, "light_energy", energy, 0.25)
	_shake_near(at, 10.0, 0.2)


# --- Meteors ----------------------------------------------------------------------------------

## A burning rock falling onto `at` over `seconds`, trailing smoke.
func meteor_fall(at: Vector3, seconds: float) -> void:
	var rock := Node3D.new()
	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 10
	sphere.rings = 6
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.55, 0.15)
	sphere.material = material
	core.mesh = sphere
	rock.add_child(core)
	var glow := Sprite3D.new()
	glow.texture = FIRE
	glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	glow.pixel_size = 2.6 / FIRE.get_width()
	glow.modulate = Color(1.0, 0.6, 0.2, 0.9)
	glow.shaded = false
	rock.add_child(glow)
	_main.world.add_child(rock)
	var start := at + Vector3(-8.0, 26.0, -6.0)
	rock.global_position = start
	var tween := rock.create_tween()
	tween.tween_method(func(t: float) -> void:
		rock.global_position = start.lerp(at, t)
		if randf() < 0.35:
			HitFx.flash(rock.global_position, HitFx.DEATH_SMOKE, Color(0.35, 0.3, 0.28, 0.7), 1.4, 0.6, Vector2(0.6, 1.4), false),
			0.0, 1.0, seconds).set_ease(Tween.EASE_IN)
	tween.tween_callback(rock.queue_free)


func meteor_impact(at: Vector3, radius: float) -> void:
	HitFx.flash(at + Vector3(0, 0.6, 0), FIRE, Color(1.0, 0.55, 0.15, 1.0), radius * 2.2, 0.5, Vector2(0.4, 1.3))
	HitFx.flash(at + Vector3(0, 1.0, 0), HitFx.BIG_SMOKE, Color(0.3, 0.27, 0.25, 0.85), radius * 2.6, 1.2, Vector2(0.5, 1.5), false)
	HitFx.burst(at + Vector3(0, 0.3, 0), HitFx.Kind.DIRT, 26)
	HitFx.shockwave(at, radius)
	_scorch(at, radius * 1.1)


## A burnt mark on the ground that fades away.
func _scorch(at: Vector3, radius: float) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2.ONE * radius * 2.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = SCORCH
	material.albedo_color = Color(0.1, 0.08, 0.06, 0.8)
	mesh.material = material
	var mark := MeshInstance3D.new()
	mark.mesh = mesh
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mark.rotation.y = randf() * TAU
	_main.world.add_child(mark)
	mark.global_position = Vector3(at.x, 0.04, at.z)
	var fade := mark.create_tween()
	fade.tween_interval(7.0)
	fade.tween_property(material, "albedo_color:a", 0.0, 3.0)
	fade.tween_callback(mark.queue_free)


# --- Supply drop -----------------------------------------------------------------------------------

## The crate drifting down onto `at` under a parachute for `seconds`; a gold ring and a minimap badge show
## where it will land.
func supply_fall(at: Vector3, seconds: float, icon: Texture2D, color: Color) -> void:
	var marker := Node3D.new()
	marker.set_meta(&"marker_color", color)
	marker.set_meta(&"marker_label", "Supply drop")
	marker.set_meta(&"marker_icon", icon)
	_main.world.add_child(marker)
	marker.global_position = at
	marker.add_to_group(&"tracked")
	HitFx.ground_warning(at, 2.0, seconds, Color(color, 0.55))
	var drop := Node3D.new()
	var crate := CRATE.instantiate() as Node3D
	crate.scale = Vector3.ONE * 2.0
	drop.add_child(crate)
	var canopy := MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.radius = 1.5
	dome.height = 1.2
	dome.is_hemisphere = true
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.95, 0.3, 0.25)
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	dome.material = cloth
	canopy.mesh = dome
	canopy.position.y = 3.2
	drop.add_child(canopy)
	for corner in [Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, -1)]:
		var rope := MeshInstance3D.new()
		var line := BoxMesh.new()
		line.size = Vector3(0.04, 2.9, 0.04)
		rope.mesh = line
		var foot: Vector3 = corner * 0.45 + Vector3(0, 0.6, 0)
		var top: Vector3 = corner * 1.25 + Vector3(0, 3.25, 0)
		rope.basis = Basis(Quaternion(Vector3.UP, (top - foot).normalized()))
		rope.position = (foot + top) * 0.5
		drop.add_child(rope)
	_main.world.add_child(drop)
	drop.global_position = at + Vector3(0, 24.0, 0)
	var tween := drop.create_tween()
	tween.tween_property(drop, "global_position", at, seconds).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(drop, "rotation:y", randf_range(-1.5, 1.5), seconds)
	tween.tween_callback(drop.queue_free)
	tween.tween_callback(marker.queue_free)


func _shake_near(at: Vector3, distance: float, strength: float) -> void:
	var camera := HitFx.camera
	if is_instance_valid(camera) and camera.target and camera.target.global_position.distance_to(at) < distance:
		camera.shake(strength, 0.3)
