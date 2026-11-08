class_name MalakorModel
extends Node3D
## Malakor, the Six-Armed Sovereign (the King of the Demon's Lair in Conquest): his body built from simple pieces in
## code, ~3 m tall before the Lair's BOSS_SIZE (× 1.6 = 4.8 m), +Z = front, origin at his feet. Placeholder for a
## modelled one (swap the Model node of malakor.tscn for a GLB with the same clips).
## - Crowned skull (6 blood-iron spikes), burning red eyes, fanged jaw; obsidian armor, a bone ribcage around a
##   glowing Soul Core, a tattered crimson cape.
## - Six arms in three pairs, each a shoulder pivot + elbow pivot + hand: upper = Soul Cleaver greatsword (right) and
##   barbed cleaver (left); middle = the Spine Warbow (left) and the arrow being drawn (right); lower = the floating
##   Necrotic Grimoire with 5 orbiting runes (left) and the Blood Siphon Chalice (right).
## - Its own AnimationPlayer with the clips Unit / Enemy play: idle, walk, sprint, attack-melee-right / -left
##   (sword pair cleaves), holding-right-shoot / holding-both-shoot (bow pair draws and looses), interact-right
##   (chalice raised: totems), cast (grimoire), die (falls back).

const OBSIDIAN := Color(0.13, 0.11, 0.14)
const IRON := Color(0.42, 0.09, 0.07)
const BONE := Color(0.88, 0.84, 0.72)
const CAPE := Color(0.55, 0.05, 0.09)
const CORE := Color(0.3, 1.0, 0.5)
const EYES := Color(1.0, 0.15, 0.1)
const RUNES := Color(0.7, 0.3, 1.0)
const BOW_RUNES := Color(0.3, 0.95, 1.0)
const ARMS := ["UR", "UL", "MR", "ML", "LR", "LL"]
## Rest pose per arm: shoulder pivot, shoulder rotation, elbow rotation (x bends forward).
const POSE := {
	"UR": [Vector3(0.62, 1.32, 0.0), Vector3(-0.6, 0.0, 0.7), -0.9],
	"UL": [Vector3(-0.62, 1.32, 0.0), Vector3(-0.6, 0.0, -0.7), -0.9],
	"MR": [Vector3(0.6, 0.98, 0.06), Vector3(-1.25, 0.0, 0.25), -1.5],
	"ML": [Vector3(-0.6, 0.98, 0.06), Vector3(-1.35, 0.0, -0.15), -0.15],
	"LR": [Vector3(0.52, 0.62, 0.1), Vector3(-0.55, 0.0, 0.35), -1.1],
	"LL": [Vector3(-0.52, 0.62, 0.1), Vector3(-0.55, 0.0, -0.35), -1.1],
}

var anim: AnimationPlayer
var _materials: Dictionary = {}
var _runes: Node3D
var _core: MeshInstance3D
var _time: float = 0.0


func _init() -> void:
	_build()
	anim = AnimationPlayer.new()
	anim.name = "AnimationPlayer"
	add_child(anim)
	var library := AnimationLibrary.new()
	for clip in _clips():
		library.add_animation(clip[0], clip[1])
	anim.add_animation_library(&"", library)


func _process(delta: float) -> void:
	_time += delta
	if _runes:
		_runes.rotation.y = _time * 1.6
	if _core:
		var pulse := 0.5 + 0.5 * sin(_time * 3.2)
		(_core.material_override as StandardMaterial3D).emission_energy_multiplier = 1.5 + pulse * 2.0


# --- Body -----------------------------------------------------------------------------------

func _build() -> void:
	var body := _node(self, "Body", Vector3.ZERO)
	for side in [1.0, -1.0]:
		var leg := _node(body, "Leg" + ("R" if side > 0 else "L"), Vector3(0.3 * side, 1.2, 0.0))
		_box(leg, Vector3(0.34, 0.66, 0.36), Vector3(0, -0.33, 0), OBSIDIAN)
		_cone(leg, 0.07, 0.22, Vector3(0, -0.6, 0.2), Vector3(-PI * 0.5, 0, 0), IRON)  # knee spike
		var knee := _node(leg, "Knee", Vector3(0, -0.62, 0))
		_box(knee, Vector3(0.3, 0.52, 0.32), Vector3(0, -0.27, 0), OBSIDIAN.lightened(0.08))
		_box(knee, Vector3(0.36, 0.14, 0.54), Vector3(0, -0.52, 0.08), IRON)
	var torso := _node(body, "Torso", Vector3(0, 1.2, 0))
	_box(torso, Vector3(0.82, 0.3, 0.52), Vector3(0, 0.1, 0), IRON)  # pelvis / belt
	_box(torso, Vector3(0.66, 0.42, 0.44), Vector3(0, 0.45, 0), OBSIDIAN)
	_box(torso, Vector3(1.12, 0.72, 0.6), Vector3(0, 1.02, -0.03), OBSIDIAN.lightened(0.05))  # chest plate
	# The ribcage over an opening in the plate, the Soul Core glowing behind it.
	_box(torso, Vector3(0.5, 0.5, 0.06), Vector3(0, 0.98, 0.28), Color(0.05, 0.02, 0.03))
	_core = _sphere(torso, 0.15, Vector3(0, 0.98, 0.26), CORE, 3.0)
	for i in 4:
		_box(torso, Vector3(0.62 - i * 0.06, 0.05, 0.06), Vector3(0, 0.78 + i * 0.13, 0.34), BONE)
	_box(torso, Vector3(0.07, 0.56, 0.07), Vector3(0, 0.97, 0.36), BONE)  # sternum
	for side in [1.0, -1.0]:
		_box(torso, Vector3(0.36, 0.22, 0.5), Vector3(0.66 * side, 1.42, 0), IRON)  # pauldron
		_cone(torso, 0.07, 0.3, Vector3(0.74 * side, 1.62, 0), Vector3(0, 0, -0.5 * side), OBSIDIAN)
	var cape := _box(torso, Vector3(1.0, 1.45, 0.05), Vector3(0, 0.72, -0.4), CAPE)
	cape.rotation.x = 0.12
	# Head: crowned skull, burning eyes, fanged jaw.
	var head := _node(torso, "Head", Vector3(0, 1.42, 0.02))
	_box(head, Vector3(0.42, 0.42, 0.44), Vector3(0, 0.22, 0), BONE)
	for side in [1.0, -1.0]:
		_box(head, Vector3(0.12, 0.08, 0.04), Vector3(0.1 * side, 0.26, 0.21), Color(0.05, 0.02, 0.02))
		_sphere(head, 0.05, Vector3(0.1 * side, 0.25, 0.22), EYES, 4.0)
		_cone(head, 0.025, 0.09, Vector3(0.09 * side, -0.02, 0.2), Vector3(PI, 0, 0), BONE)  # upper fangs
	_box(head, Vector3(0.36, 0.1, 0.3), Vector3(0, 0.0, 0.06), BONE.darkened(0.25))  # jaw
	var crown := _cylinder(head, 0.24, 0.1, Vector3(0, 0.46, 0), IRON)
	crown.name = "Crown"
	for i in 6:
		var angle := TAU * i / 6.0
		_cone(head, 0.05, 0.3 if i % 2 == 0 else 0.22, Vector3(sin(angle) * 0.22, 0.62, cos(angle) * 0.22), Vector3.ZERO,
				IRON.darkened(0.2))
	# Six arms.
	for key: String in ARMS:
		_arm(torso, key)


func _arm(torso: Node3D, key: String) -> void:
	var pose: Array = POSE[key]
	var shoulder := _node(torso, "Arm" + key, pose[0])
	shoulder.rotation = pose[1]
	var thick := 0.2 if key.begins_with("U") else 0.17
	_box(shoulder, Vector3(thick, 0.55, thick), Vector3(0, -0.27, 0), OBSIDIAN.lightened(0.1))
	var elbow := _node(shoulder, "Elbow", Vector3(0, -0.54, 0))
	elbow.rotation.x = pose[2]
	_box(elbow, Vector3(thick * 0.9, 0.5, thick * 0.9), Vector3(0, -0.25, 0), OBSIDIAN.lightened(0.18))
	_box(elbow, Vector3(thick * 1.1, 0.16, thick * 1.1), Vector3(0, -0.12, 0), IRON)  # bracer
	var hand := _node(elbow, "Hand", Vector3(0, -0.52, 0))
	_box(hand, Vector3(0.16, 0.14, 0.16), Vector3.ZERO, BONE.darkened(0.1))
	match key:
		"UR":
			_greatsword(hand)
		"UL":
			_cleaver(hand)
		"ML":
			_bow(hand)
		"MR":
			_arrow(hand)
		"LL":
			_grimoire(hand)
		"LR":
			_chalice(hand)


## The Soul Cleaver: a long serrated obsidian blade with a red edge, pointing on from the fist.
func _greatsword(hand: Node3D) -> void:
	var grip := _node(hand, "Sword", Vector3.ZERO)
	grip.rotation.x = PI * 0.5  # the blade leaves the fist along the fist's front
	_box(grip, Vector3(0.07, 0.3, 0.07), Vector3(0, -0.12, 0), IRON.darkened(0.3))  # hilt
	_box(grip, Vector3(0.42, 0.07, 0.1), Vector3(0, 0.05, 0), IRON)  # guard
	_box(grip, Vector3(0.2, 1.5, 0.05), Vector3(0, 0.84, 0), OBSIDIAN)
	_box(grip, Vector3(0.04, 1.5, 0.06), Vector3(0.11, 0.84, 0), EYES, 1.6)  # burning edge
	for i in 5:
		_cone(grip, 0.04, 0.1, Vector3(-0.12, 0.3 + i * 0.28, 0), Vector3(0, 0, PI * 0.5), OBSIDIAN)  # serration


func _cleaver(hand: Node3D) -> void:
	var grip := _node(hand, "Cleaver", Vector3.ZERO)
	grip.rotation.x = PI * 0.5
	_box(grip, Vector3(0.06, 0.32, 0.06), Vector3(0, -0.05, 0), IRON.darkened(0.3))
	_box(grip, Vector3(0.38, 0.55, 0.05), Vector3(0.12, 0.38, 0), IRON.darkened(0.1))
	_box(grip, Vector3(0.05, 0.55, 0.06), Vector3(0.32, 0.38, 0), BONE)  # barbed edge
	for i in 3:
		_cone(grip, 0.035, 0.1, Vector3(0.36, 0.18 + i * 0.18, 0), Vector3(0, 0, -PI * 0.5), BONE)


## The Spine Warbow: drake vertebrae in an arc with cyan runes, held upright.
func _bow(hand: Node3D) -> void:
	var bow := _node(hand, "Bow", Vector3(0, -0.05, 0.04))
	bow.rotation.x = PI * 0.5  # upright while the arm reaches forward
	for i in 9:
		var t := (i - 4) / 4.0
		var at := Vector3(0, t * 0.75, -0.25 * (1.0 - t * t))
		var bone := _box(bow, Vector3(0.09, 0.17, 0.09), at, BONE if i % 2 == 0 else BONE.darkened(0.2))
		bone.rotation.x = -t * 0.6
		if i % 2 == 1:
			_box(bow, Vector3(0.1, 0.04, 0.1), at, BOW_RUNES, 2.5)
	_box(bow, Vector3(0.015, 1.5, 0.015), Vector3(0, 0, 0.02), BOW_RUNES, 2.0)  # the string


func _arrow(hand: Node3D) -> void:
	var arrow := _node(hand, "Arrow", Vector3(0, -0.02, 0.1))
	_box(arrow, Vector3(0.03, 0.03, 0.95), Vector3(0, 0, 0.42), BONE)
	_cone(arrow, 0.05, 0.14, Vector3(0, 0, 0.96), Vector3(PI * 0.5, 0, 0), BOW_RUNES, 3.0)


## The Necrotic Grimoire floats over the open claw, five runes orbiting it.
func _grimoire(hand: Node3D) -> void:
	var book := _node(hand, "Grimoire", Vector3(0, -0.1, 0.32))
	_box(book, Vector3(0.36, 0.08, 0.28), Vector3.ZERO, Color(0.28, 0.12, 0.2))
	_box(book, Vector3(0.32, 0.04, 0.24), Vector3(0, 0.05, 0), Color(0.85, 0.8, 0.65))  # pages
	_runes = _node(book, "Runes", Vector3(0, 0.12, 0))
	for i in 5:
		var angle := TAU * i / 5.0
		var rune := _box(_runes, Vector3(0.07, 0.07, 0.02), Vector3(sin(angle), 0.0, cos(angle)) * 0.32, RUNES, 3.0)
		rune.rotation.y = angle


func _chalice(hand: Node3D) -> void:
	var cup := _node(hand, "Chalice", Vector3(0, -0.12, 0.05))
	_cylinder(cup, 0.04, 0.16, Vector3(0, 0.0, 0), IRON.darkened(0.3))
	var bowl := _cylinder(cup, 0.14, 0.14, Vector3(0, 0.14, 0), IRON.darkened(0.2))
	(bowl.mesh as CylinderMesh).bottom_radius = 0.06
	_cylinder(cup, 0.12, 0.02, Vector3(0, 0.21, 0), CORE, 3.0)  # the blood-light inside


# --- Pieces -------------------------------------------------------------------------------------

func _node(parent: Node3D, node_name: String, at: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.position = at
	parent.add_child(node)
	return node


func _material(color: Color, glow: float) -> StandardMaterial3D:
	var key := "%s|%.2f" % [color.to_html(), glow]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.75
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	_materials[key] = material
	return material


func _piece(parent: Node3D, mesh: Mesh, at: Vector3, color: Color, glow: float) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	piece.mesh = mesh
	piece.position = at
	piece.material_override = _material(color, glow)  # shared: the core's pulse lights the chalice too
	parent.add_child(piece)
	return piece


func _box(parent: Node3D, size: Vector3, at: Vector3, color: Color, glow: float = 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _piece(parent, mesh, at, color, glow)


func _sphere(parent: Node3D, r: float, at: Vector3, color: Color, glow: float = 0.0) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	return _piece(parent, mesh, at, color, glow)


func _cylinder(parent: Node3D, r: float, height: float, at: Vector3, color: Color, glow: float = 0.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.height = height
	mesh.radial_segments = 12
	return _piece(parent, mesh, at, color, glow)


## A spike: a cone pointing along its local +Y, turned by `rot`.
func _cone(parent: Node3D, r: float, height: float, at: Vector3, rot: Vector3, color: Color, glow: float = 0.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = r
	mesh.height = height
	mesh.radial_segments = 8
	var piece := _piece(parent, mesh, at, color, glow)
	piece.rotation = rot
	return piece


# --- Clips --------------------------------------------------------------------------------------

func _clips() -> Array:
	return [
		["idle", _idle()], ["walk", _walk(1.0, 0.45)], ["sprint", _walk(0.7, 0.7)],
		["attack-melee-right", _cleave(1.0)], ["attack-melee-left", _cleave(-1.0)],
		["holding-right-shoot", _shoot(false)], ["holding-both-shoot", _shoot(true)],
		["interact-right", _raise("LR")], ["cast", _raise("LL")], ["die", _die()],
	]


func _rest(key: String) -> Vector3:
	return POSE[key][1]


## A value track on `path` (relative to this model) with `keys` = [[time, value], ...].
func _track(clip: Animation, path: String, keys: Array) -> void:
	var track := clip.add_track(Animation.TYPE_VALUE)
	clip.track_set_path(track, NodePath(path))
	for key: Array in keys:
		clip.track_insert_key(track, key[0], key[1])


func _arm_path(key: String) -> String:
	return "Body/Torso/Arm" + key + ":rotation"


func _elbow_path(key: String) -> String:
	return "Body/Torso/Arm" + key + "/Elbow:rotation"


func _idle() -> Animation:
	var clip := Animation.new()
	clip.length = 2.4
	_track(clip, "Body/Torso:position", [[0.0, Vector3(0, 1.2, 0)], [1.2, Vector3(0, 1.24, 0)], [2.4, Vector3(0, 1.2, 0)]])
	_track(clip, "Body/Torso/Head:rotation", [[0.0, Vector3(0.05, 0, 0)], [1.2, Vector3(-0.05, 0.08, 0)], [2.4, Vector3(0.05, 0, 0)]])
	for key: String in ARMS:
		var sway := Vector3(0.06, 0, 0.05 * (1.0 if key.ends_with("R") else -1.0))
		_track(clip, _arm_path(key), [[0.0, _rest(key)], [1.2, _rest(key) + sway], [2.4, _rest(key)]])
	_legs(clip, 2.4, 0.0)
	return clip


func _walk(length: float, swing: float) -> Animation:
	var clip := Animation.new()
	clip.length = length
	var h := length * 0.5
	var q := length * 0.25
	_legs(clip, length, swing)
	_track(clip, "Body/Torso:position", [[0.0, Vector3(0, 1.2, 0)], [q, Vector3(0, 1.26, 0)], [h, Vector3(0, 1.2, 0)],
			[h + q, Vector3(0, 1.26, 0)], [length, Vector3(0, 1.2, 0)]])
	_track(clip, "Body/Torso:rotation", [[0.0, Vector3(0.08, 0.1, 0)], [h, Vector3(0.08, -0.1, 0)], [length, Vector3(0.08, 0.1, 0)]])
	for key: String in ARMS:
		var side := 1.0 if key.ends_with("R") else -1.0
		var sway := Vector3(swing * 0.3 * side, 0, 0)
		_track(clip, _arm_path(key), [[0.0, _rest(key) + sway], [h, _rest(key) - sway], [length, _rest(key) + sway]])
	return clip


func _legs(clip: Animation, length: float, swing: float) -> void:
	var h := length * 0.5
	for side in [1.0, -1.0]:
		var leg := "Body/Leg" + ("R" if side > 0 else "L")
		var a := Vector3(swing * side, 0, 0)
		_track(clip, leg + ":rotation", [[0.0, a], [h, -a], [length, a]])
		_track(clip, leg + "/Knee:rotation", [[0.0, Vector3(maxf(swing * side, 0.0) * 0.9, 0, 0)],
				[h, Vector3(maxf(-swing * side, 0.0) * 0.9, 0, 0)], [length, Vector3(maxf(swing * side, 0.0) * 0.9, 0, 0)]])


## Both blades of the upper pair: raised, then a wide sweep across (`side` = which one leads).
func _cleave(side: float) -> Animation:
	var clip := Animation.new()
	clip.length = 0.9
	_track(clip, "Body/Torso:rotation", [[0.0, Vector3.ZERO], [0.3, Vector3(0, 0.45 * side, 0)], [0.5, Vector3(0.1, -0.55 * side, 0)],
			[0.9, Vector3.ZERO]])
	for key: String in ["UR", "UL"]:
		var s := 1.0 if key == "UR" else -1.0
		var up := Vector3(-2.5, 0, 0.9 * s)
		var across := Vector3(-1.2, 0, -0.5 * s)
		_track(clip, _arm_path(key), [[0.0, _rest(key)], [0.3, up], [0.5, across], [0.9, _rest(key)]])
		_track(clip, _elbow_path(key), [[0.0, Vector3(POSE[key][2], 0, 0)], [0.3, Vector3(-1.4, 0, 0)], [0.5, Vector3(-0.2, 0, 0)],
				[0.9, Vector3(POSE[key][2], 0, 0)]])
	return clip


## The bow pair draws further and looses (and the grimoire hand lifts for the magic volley).
func _shoot(both: bool) -> Animation:
	var clip := Animation.new()
	clip.length = 0.8
	_track(clip, _elbow_path("MR"), [[0.0, Vector3(POSE["MR"][2], 0, 0)], [0.4, Vector3(-2.0, 0, 0)], [0.5, Vector3(-0.6, 0, 0)],
			[0.8, Vector3(POSE["MR"][2], 0, 0)]])
	_track(clip, _arm_path("ML"), [[0.0, _rest("ML")], [0.4, _rest("ML") + Vector3(-0.15, 0, 0)], [0.8, _rest("ML")]])
	if both:
		_track(clip, _arm_path("LL"), [[0.0, _rest("LL")], [0.35, Vector3(-1.9, 0, -0.3)], [0.8, _rest("LL")]])
	return clip


func _raise(key: String) -> Animation:
	var clip := Animation.new()
	clip.length = 1.0
	var s := 1.0 if key.ends_with("R") else -1.0
	_track(clip, _arm_path(key), [[0.0, _rest(key)], [0.4, Vector3(-2.7, 0, 0.2 * s)], [0.75, Vector3(-2.7, 0, 0.2 * s)], [1.0, _rest(key)]])
	_track(clip, "Body/Torso/Head:rotation", [[0.0, Vector3.ZERO], [0.4, Vector3(-0.35, 0, 0)], [1.0, Vector3.ZERO]])
	return clip


func _die() -> Animation:
	var clip := Animation.new()
	clip.length = 1.6
	_track(clip, "Body:rotation", [[0.0, Vector3.ZERO], [0.3, Vector3(0.2, 0, 0)], [1.3, Vector3(-1.45, 0, 0)]])
	_track(clip, "Body:position", [[0.0, Vector3.ZERO], [1.3, Vector3(0, 0.25, -0.6)]])
	for key: String in ARMS:
		_track(clip, _arm_path(key), [[0.0, _rest(key)], [1.0, Vector3(0.3, 0, 0.9 * (1.0 if key.ends_with("R") else -1.0))]])
	return clip
