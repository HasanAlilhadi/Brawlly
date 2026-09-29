class_name BonePoseOverride3D
extends SkeletonModifier3D
## Holds some bones in a fixed pose taken from an animation, on top of whatever is playing.
## Typical use: keep a character's arm in a "holding" pose (weapon in front) while the legs walk.
## Blend it in/out with the built-in `influence` (0 = animation only, 1 = held pose).
## Add as a child of the Skeleton3D, then call `set_pose_from_animation()`.
## `start_live(animation)` instead plays those bones from another animation (advance `live_time`),
## e.g. swing only the arm while the legs keep running; `stop_live()` returns to the held pose.

## Time into the live animation (set by the owner every frame while live).
var live_time: float = 0.0
## Extra rotation on top of the held / live pose, in the parent bone's space (pivots at the joint), e.g.
## sweep a held arm around the shoulder for a procedural swing. Identity = the pose as sampled.
var pose_offset: Quaternion = Quaternion.IDENTITY

var _bone_indices: PackedInt32Array = PackedInt32Array()
var _positions: Array[Vector3] = []
var _rotations: Array[Quaternion] = []
var _live_animation: Animation
var _live_tracks: Array[Vector2i] = []  # per bone: (position track, rotation track), -1 = none


## Samples `bones` (matched by bone name) from `animation` at `time`.
func set_pose_from_animation(animation: Animation, time: float, bones: PackedStringArray) -> void:
	_bone_indices.clear()
	_positions.clear()
	_rotations.clear()
	var skeleton := get_skeleton()
	if skeleton == null or animation == null:
		return
	for bone in bones:
		var index := skeleton.find_bone(bone)
		if index == -1:
			continue
		var position := skeleton.get_bone_rest(index).origin
		var rotation := skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
		for track in animation.get_track_count():
			if animation.track_get_path(track).get_concatenated_subnames() != bone:
				continue
			match animation.track_get_type(track):
				Animation.TYPE_POSITION_3D:
					position = animation.position_track_interpolate(track, time)
				Animation.TYPE_ROTATION_3D:
					rotation = animation.rotation_track_interpolate(track, time)
		_bone_indices.append(index)
		_positions.append(position)
		_rotations.append(rotation)


## The held rotation of the `index`-th bone (parent bone space), without `pose_offset`.
func get_held_rotation(index: int = 0) -> Quaternion:
	return _rotations[index] if index < _rotations.size() else Quaternion.IDENTITY


func start_live(animation: Animation) -> void:
	_live_animation = animation
	live_time = 0.0
	_live_tracks.clear()
	var skeleton := get_skeleton()
	for index in _bone_indices:
		var bone := skeleton.get_bone_name(index)
		var tracks := Vector2i(-1, -1)
		for track in animation.get_track_count():
			if animation.track_get_path(track).get_concatenated_subnames() != bone:
				continue
			match animation.track_get_type(track):
				Animation.TYPE_POSITION_3D:
					tracks.x = track
				Animation.TYPE_ROTATION_3D:
					tracks.y = track
		_live_tracks.append(tracks)


func stop_live() -> void:
	_live_animation = null


func is_live() -> bool:
	return _live_animation != null


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	for i in _bone_indices.size():
		var position := _positions[i]
		var rotation := _rotations[i]
		if _live_animation:
			var tracks := _live_tracks[i]
			if tracks.x >= 0:
				position = _live_animation.position_track_interpolate(tracks.x, live_time)
			if tracks.y >= 0:
				rotation = _live_animation.rotation_track_interpolate(tracks.y, live_time)
		skeleton.set_bone_pose_position(_bone_indices[i], position)
		skeleton.set_bone_pose_rotation(_bone_indices[i], pose_offset * rotation)
