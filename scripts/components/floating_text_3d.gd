class_name FloatingText3D
extends Label3D
## Short text that pops up in the 3D world, arcs away and fades out (damage numbers, "+5" coins…).
## Usage: FloatingText3D.spawn(parent, position, "54", Color.GOLD, 90, true)
## `emphasized` = bigger pop + shake (e.g. critical hits).
## Labels are pooled and animated in `_process` (no tweens / allocations per number). At most
## `MAX_ACTIVE` are on screen: when a burst of hits exceeds it, the oldest number is reused.

const MAX_ACTIVE := 24
## Every label renders at this font size and is scaled with `pixel_size`, so all numbers share one glyph cache.
const FONT_SIZE := 64
const PIXEL_SIZE := 0.006

@export var rise: float = 1.0
@export var duration: float = 0.8

var emphasis: bool = false

var _start: Vector3
var _drift: float = 0.0
var _age: float = 0.0
var _alpha: float = 1.0

static var _active: Array[FloatingText3D] = []
static var _idle: Array[FloatingText3D] = []
## Own RNG: gameplay code may rely on the seeded global one.
static var _rng := RandomNumberGenerator.new()


static func spawn(parent: Node3D, at: Vector3, message: String, color: Color = Color.WHITE,
		size: int = 72, emphasized: bool = false) -> FloatingText3D:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return null
	var label := _take(parent)
	label.text = message
	label.modulate = color
	label.pixel_size = PIXEL_SIZE * float(size) / FONT_SIZE
	label.outline_size = 16 if emphasized else 12
	label.emphasis = emphasized
	label.global_position = at
	label._play()
	return label


## A free pooled label under `parent`, the oldest active one when the cap is hit, or a new one.
static func _take(parent: Node3D) -> FloatingText3D:
	_prune(_active)
	_prune(_idle)
	for i in range(_idle.size() - 1, -1, -1):
		if _idle[i].get_parent() == parent:
			var reused: FloatingText3D = _idle[i]
			_idle.remove_at(i)
			return reused
	if _active.size() >= MAX_ACTIVE:
		var oldest: FloatingText3D = _active.pop_front()
		if oldest.get_parent() == parent:
			return oldest
	var label := FloatingText3D.new()
	parent.add_child(label)
	return label


## Drops labels freed with their parent (e.g. the world of a finished match).
static func _prune(labels: Array[FloatingText3D]) -> void:
	for i in range(labels.size() - 1, -1, -1):
		if not is_instance_valid(labels[i]):
			labels.remove_at(i)


func _init() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	render_priority = 10
	font_size = FONT_SIZE
	outline_modulate = Color(0.12, 0.04, 0.0, 0.95)
	visible = false
	set_process(false)


func _play() -> void:
	_active.erase(self)
	_active.append(self)
	_start = position
	# Arc sideways a little so numbers from rapid hits don't stack.
	_drift = _rng.randf_range(-0.55, 0.55)
	_age = 0.0
	_alpha = modulate.a
	scale = Vector3.ONE * (0.2 if emphasis else 0.35)
	visible = true
	set_process(true)


func _process(delta: float) -> void:
	_age += delta
	var t := _age / duration
	if t >= 1.0:
		_recycle()
		return
	# Path: ease out up to the peak, then ease in to the end.
	var peak := _start + Vector3(_drift * 0.5, rise * 0.75, 0.0)
	var pos: Vector3
	if t < 0.45:
		pos = _start.lerp(peak, ease(t / 0.45, 0.5))
	else:
		pos = peak.lerp(_start + Vector3(_drift, rise, 0.0), ease((t - 0.45) / 0.55, 2.0))
	if emphasis and _age < 0.3:
		pos.x += sin(_age * 60.0) * 0.05 * (1.0 - _age / 0.3)
	position = pos
	# Pop: overshoot quickly, then settle to full size.
	if _age < 0.1:
		var from := 0.2 if emphasis else 0.35
		var to := 1.45 if emphasis else 1.1
		scale = Vector3.ONE * lerpf(from, to, ease(_age / 0.1, 0.4))
	elif _age < 0.22:
		scale = Vector3.ONE * lerpf(1.45 if emphasis else 1.1, 1.0, (_age - 0.1) / 0.12)
	elif scale != Vector3.ONE:
		scale = Vector3.ONE
	if t > 0.6:
		modulate.a = _alpha * (1.0 - (t - 0.6) / 0.4)


func _recycle() -> void:
	visible = false
	set_process(false)
	_active.erase(self)
	_idle.append(self)
