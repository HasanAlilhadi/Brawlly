class_name CaptureFlag
extends Node3D
## Capture the Flag: a team's flag at its base. An enemy player touching it picks it up; bringing it
## to their own base while their own flag is home scores a capture. A carrier who dies drops it; the
## owning team returns a dropped flag by touching it (or it returns by itself after a while).
## Server runs the rules; every peer shows the flag via `_net_state`.

enum State { HOME, CARRIED, DROPPED }

const FLAG_MODEL := preload("res://assets/environment/forest/flag.glb")
const TOUCH_RANGE: float = 1.4
const CAPTURE_RANGE: float = 2.6
const AUTO_RETURN: float = 20.0

var team_id: int = 0
var home: Vector3
var game_mode: GameMode
var state: State = State.HOME
var carrier_peer: int = 0

var _drop_timer: float = 0.0
var _model: Node3D


func _ready() -> void:
	position = home
	var color: Color = Net.TEAM_COLORS[team_id]
	# Base pad (stays at home).
	var pad := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = CAPTURE_RANGE
	disc.bottom_radius = CAPTURE_RANGE
	disc.height = 0.04
	var pad_material := StandardMaterial3D.new()
	pad_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pad_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pad_material.albedo_color = Color(color, 0.35)
	disc.material = pad_material
	pad.mesh = disc
	pad.top_level = true
	pad.position = home + Vector3(0, 0.03, 0)
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pad)
	# The flag itself (team tinted).
	_model = FLAG_MODEL.instantiate() as Node3D
	_model.scale = Vector3.ONE * 1.8
	var tint := StandardMaterial3D.new()
	tint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tint.albedo_color = Color(color, 0.55)
	for mesh in _model.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_overlay = tint
	add_child(_model)


func _physics_process(delta: float) -> void:
	if state == State.CARRIED:
		var carrier := _player(carrier_peer)
		if carrier:
			global_position = carrier.global_position + Vector3(0, 0.9, -0.3)
	_model.rotation.y += delta * (2.0 if state != State.HOME else 0.6)
	if not multiplayer.is_server() or game_mode.is_over:
		return
	match state:
		State.HOME, State.DROPPED:
			if state == State.DROPPED:
				_drop_timer -= delta
				if _drop_timer <= 0.0:
					_return_home()
					return
			for node in get_tree().get_nodes_in_group(&"players"):
				var player := node as Player
				if GameConfig.is_gone(player) or player.global_position.distance_to(global_position) > TOUCH_RANGE:
					continue
				if player.team_id != team_id:
					_set_state(State.CARRIED, player.peer_id, global_position)
					game_mode.announce("%s took the %s flag!" % [player.display_name, Net.TEAM_NAMES[team_id]])
					return
				elif state == State.DROPPED:
					_return_home()
					game_mode.announce("%s returned the %s flag" % [player.display_name, Net.TEAM_NAMES[team_id]])
					return
		State.CARRIED:
			var carrier := _player(carrier_peer)
			if carrier == null or GameConfig.is_gone(carrier):
				_drop(global_position)
				return
			var own_flag := _flag_of(carrier.team_id)
			if own_flag and own_flag.state == State.HOME and carrier.global_position.distance_to(own_flag.home) < CAPTURE_RANGE:
				game_mode.announce("%s captured the %s flag!" % [carrier.display_name, Net.TEAM_NAMES[team_id]])
				_return_home()
				game_mode.add_score(carrier.team_id, 1)


func on_carrier_died(player: Player) -> void:
	if state == State.CARRIED and player.peer_id == carrier_peer:
		_drop(player.global_position)


func _drop(at: Vector3) -> void:
	_drop_timer = AUTO_RETURN
	_set_state(State.DROPPED, 0, Vector3(at.x, 0.0, at.z))


func _return_home() -> void:
	_set_state(State.HOME, 0, home)


func _set_state(new_state: State, peer: int, at: Vector3) -> void:
	_net_state.rpc(new_state, peer, at)


@rpc("authority", "call_local", "reliable")
func _net_state(new_state: int, peer: int, at: Vector3) -> void:
	state = new_state as State
	carrier_peer = peer
	if state != State.CARRIED:
		global_position = at


func _player(peer: int) -> Player:
	for node in get_tree().get_nodes_in_group(&"players"):
		if (node as Player).peer_id == peer:
			return node
	return null


func _flag_of(team: int) -> CaptureFlag:
	for flag in game_mode.flags:
		if flag.team_id == team:
			return flag
	return null
