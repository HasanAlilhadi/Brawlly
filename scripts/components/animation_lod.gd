class_name AnimationLod
extends Node
## Animation level of detail: characters far from what the camera follows play their animations less often (the
## AnimationPlayer in manual mode, advanced every SLOW_EVERY frames with the time since its last update). Big crowds
## then cost a lot less, and far away nobody sees the difference. Every peer runs its own (it's only the look).
## Add one to the scene, set `focus` (e.g. the camera's target); it looks at `group`'s members (Nodes with an
## `anim: AnimationPlayer` property) a slice per frame. Paused nodes (can_process() false) are left alone, so they
## cost nothing here either. Each frame only the slow players due that frame are touched (SLOW_EVERY buckets).

## Within this distance (m, flat) of the focus: every frame; farther: every SLOW_EVERY frames.
@export var near_range: float = 30.0
## While the game is overloaded (GameConfig.overloaded: a huge fight on the host) only this close is every frame.
@export var overloaded_range: float = 12.0
@export var group: StringName = &"units"
const SLOW_EVERY: int = 3
## Each member is looked at again about this often (s).
const RECHECK: float = 0.5

var focus: Node3D
var enabled: bool = true:
	set(value):
		enabled = value
		if not value:
			for player: AnimationPlayer in _bucket_of.keys():
				_make_fast(player)

var _queue: Array[Node] = []
var _per_frame: int = 1
## SLOW_EVERY lists of slow players; the one for this frame is advanced.
var _buckets: Array[Array] = []
## Slow AnimationPlayer -> its bucket index.
var _bucket_of: Dictionary = {}
var _last: Dictionary = {}  # slow player -> clock at its last update
var _clock: float = 0.0
var _frame: int = 0


func _ready() -> void:
	for i in SLOW_EVERY:
		_buckets.append([])


func _process(delta: float) -> void:
	_frame += 1
	_clock += delta
	_recheck_some()
	var bucket: Array = _buckets[_frame % SLOW_EVERY]
	var i := 0
	while i < bucket.size():
		var player: Variant = bucket[i]
		if not is_instance_valid(player) or not _bucket_of.has(player):
			bucket.remove_at(i)  # freed, or fast again
			_last.erase(player)
			continue
		var animation := player as AnimationPlayer
		if animation.can_process():
			animation.advance(_clock - float(_last[animation]))
		_last[animation] = _clock
		i += 1


func _recheck_some() -> void:
	if _queue.is_empty():
		_queue = get_tree().get_nodes_in_group(group)
		_per_frame = maxi(1, ceili(_queue.size() / (RECHECK * maxf(Engine.get_frames_per_second(), 30.0))))
	for i in mini(_per_frame, _queue.size()):
		var node: Variant = _queue.pop_back()
		if is_instance_valid(node):
			_decide(node)


func _decide(node: Node) -> void:
	var player := node.get("anim") as AnimationPlayer
	if player == null:
		return
	var slow := false
	if enabled and node.can_process() and is_instance_valid(focus) and node is Node3D:
		var at := (node as Node3D).global_position - focus.global_position
		slow = Vector2(at.x, at.z).length() >= (overloaded_range if GameConfig.overloaded else near_range)
	if slow and not _bucket_of.has(player):
		var index := randi() % SLOW_EVERY
		_bucket_of[player] = index
		_last[player] = _clock
		_buckets[index].append(player)
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	elif not slow and _bucket_of.has(player):
		_make_fast(player)


func _make_fast(player: AnimationPlayer) -> void:
	_bucket_of.erase(player)  # its bucket drops it on its next turn
	if is_instance_valid(player):
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
