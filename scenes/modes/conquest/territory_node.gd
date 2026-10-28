class_name TerritoryNode
extends Node3D
## Conquest: one place on the map a faction can hold — a Village, Outpost, City or a faction's Citadel.
## Built on every peer by ConquestMode from the match seed (deterministic name `Territory_<n>`); the server runs
## the rules and sends the state with `_net_state`.
## States: INFESTED (monsters guard it: kill the guards to liberate it), NEUTRAL (liberated, nobody holds it:
## stand in the ring to raise your banner), OWNED (a faction's: enemies must first break the gate, if it has one,
## then stand in the ring with no defenders inside). Owned territories feed their faction's stockpile every
## logistics tick (`income()`) and are supply points: soldiers near them are repaired and resupplied.

enum Kind { VILLAGE, OUTPOST, CITY, CITADEL }
enum State { INFESTED, NEUTRAL, OWNED }

## Per kind: ring radius, guard count and the WorldEvents.WAVE_TYPES rows they come from, seconds to capture,
## gate health (0 = no gate), points per logistics tick, income per tick and the supply range.
const INFO: Dictionary = {
	Kind.VILLAGE: {"name": "Village", "radius": 6.0, "guards": 3, "rows": 1, "capture": 8.0, "gate": 0.0,
			"points": 1, "food": 6, "equipment": 0, "ammo": 1, "supply": 16.0},
	Kind.OUTPOST: {"name": "Outpost", "radius": 7.0, "guards": 5, "rows": 2, "capture": 10.0, "gate": 0.0,
			"points": 2, "food": 1, "equipment": 3, "ammo": 4, "supply": 20.0},
	Kind.CITY: {"name": "City", "radius": 9.0, "guards": 8, "rows": 4, "capture": 15.0, "gate": 1200.0,
			"points": 4, "food": 4, "equipment": 4, "ammo": 4, "supply": 26.0},
	# A faction's home: minimal baseline income, so a bigger army needs conquered production.
	Kind.CITADEL: {"name": "Citadel", "radius": 10.0, "guards": 0, "rows": 0, "capture": 20.0, "gate": 2000.0,
			"points": 3, "food": 4, "equipment": 2, "ammo": 3, "supply": 30.0},
}
## Capture progress drains this much faster than it builds when nobody is taking the place.
const DECAY: float = 0.5
## A captured gate comes back at this share of its health.
const GATE_RESTORE: float = 0.5
const MONSTER_COLOR := Color(0.55, 0.12, 0.12)
const NEUTRAL_COLOR := Color(0.9, 0.9, 0.9)
## The gatehouse stands off the middle: heroes spawn / respawn in the middle of a Citadel.
const GATE_OFFSET := Vector3(0.0, 0.0, -5.0)

var kind: Kind = Kind.VILLAGE
var state: State = State.INFESTED
## Faction holding it (-1 = nobody).
var owner_team: int = -1
var display_name: String = ""
## The faction taking it right now (-1 = nobody) and how far (0..1).
var capturer: int = -1
var progress: float = 0.0
var mode: ConquestMode
var gate: TerritoryGate

var _guards: Array[Node] = []
var _guards_spawned: bool = false
var _sync_timer: float = 0.0
var _material: StandardMaterial3D
var _flag_material: StandardMaterial3D
var _label: Label3D


func info() -> Dictionary:
	return INFO[kind]


func radius() -> float:
	return info().radius


## Supply points (territories now; caravans later) share this interface: team_id + supply_range().
var team_id: int:
	get:
		return owner_team


func supply_range() -> float:
	return info().supply if state == State.OWNED else 0.0


func _ready() -> void:
	add_to_group(&"territories")
	add_to_group(&"conquest_supply")
	if kind == Kind.CITY or kind == Kind.CITADEL:
		add_to_group(&"tracked")  # big places get a screen-edge arrow + a minimap diamond
		set_meta(&"marker_label", display_name)
	_build_visuals()
	if info().gate > 0.0:
		gate = TerritoryGate.new()
		gate.name = "Gate"
		gate.territory = self
		gate.max_health = info().gate
		gate.health = gate.max_health
		gate.position = GATE_OFFSET
		add_child(gate)
	_apply_look()


## Every peer, before the tree: a citadel starts as its faction's, everything else infested.
func start_owned(team: int) -> void:
	owner_team = team
	state = State.OWNED


# --- Server rules ------------------------------------------------------------------

func _process(delta: float) -> void:
	if _label:
		_label.text = _label_text()
	if not multiplayer.is_server() or mode == null or mode.is_over:
		return
	var changed := false
	match state:
		State.INFESTED:
			changed = _update_infested()
		State.NEUTRAL, State.OWNED:
			changed = _update_capture(delta)
	_sync_timer -= delta
	if changed or (capturer >= 0 and _sync_timer <= 0.0):
		_sync_timer = 0.5
		_send_state()


## Monsters hold it until every guard is dead.
func _update_infested() -> bool:
	if not _guards_spawned:
		if mode.living_players().is_empty():
			return false  # the heroes haven't spawned yet (clients must have the world first)
		_spawn_guards()
		return false
	for guard in _guards:
		if not GameConfig.is_gone(guard):
			return false
	_guards.clear()
	state = State.NEUTRAL
	mode.announce("%s is free of monsters! Raise your banner there." % display_name)
	return true


## Exactly one faction (not the owner) in the ring, nobody of the owner's, the gate down: the banner rises.
func _update_capture(delta: float) -> bool:
	var inside := _teams_inside()
	var taker := -1
	if inside.size() == 1 and not inside.has(owner_team) and (gate == null or gate.is_broken()):
		taker = inside.keys()[0]
	var before := progress
	var before_capturer := capturer
	if taker >= 0:
		if taker != capturer:
			capturer = taker
			progress = 0.0
		progress = minf(progress + delta / float(info().capture), 1.0)
		if progress >= 1.0:
			_captured_by(taker)
			return true
	else:
		progress = maxf(progress - delta * DECAY / float(info().capture), 0.0)
		if progress <= 0.0:
			capturer = -1
	return capturer != before_capturer or (progress == 0.0) != (before == 0.0)


## Factions with a standing hero or soldier inside the ring (team -> count).
func _teams_inside() -> Dictionary:
	var teams := {}
	var r := radius()
	for node in get_tree().get_nodes_in_group(&"player_units"):
		var unit := node as Unit
		if GameConfig.is_gone(unit) or unit.team_id < 0:
			continue
		var offset := unit.global_position - global_position
		offset.y = 0.0
		if offset.length() < r:
			teams[unit.team_id] = teams.get(unit.team_id, 0) + 1
	return teams


func _captured_by(team: int) -> void:
	var previous := owner_team
	owner_team = team
	state = State.OWNED
	capturer = -1
	progress = 0.0
	if gate:
		gate.restore(GATE_RESTORE)
	if previous >= 0:
		mode.announce("{team:%d} took %s from {team:%d}!" % [team, display_name, previous])
	else:
		mode.announce("{team:%d} raised their banner over %s." % [team, display_name])
	mode.on_territory_captured(self, previous)


## Server: the monsters that hold the place, from the wave rows (bigger places bring tougher rows).
func _spawn_guards() -> void:
	_guards_spawned = true
	var rows := mini(int(info().rows), WorldEvents.WAVE_TYPES.size())
	var count: int = info().guards
	for i in count:
		var row := randi() % maxi(rows, 1)
		var types: Array = WorldEvents.WAVE_TYPES[row]
		var scene := WorldEvents.ENEMIES + str(types[randi() % types.size()]) + ".tscn"
		var angle := TAU * i / count
		var at := GameConfig.clamp_to_world(global_position + Vector3(cos(angle), 0.0, sin(angle)) * radius() * 0.6)
		var guard := NetSpawn.unit(&"enemy", at, {"scene": scene, "strength": GameConfig.orc_strength, "coins": 1.0})
		if guard:
			guard.add_to_group(&"active_enemies")  # no warband wakes them: heroes and soldiers target them as is
			_guards.append(guard)


func _send_state() -> void:
	_net_state.rpc(state, owner_team, capturer, progress)


@rpc("authority", "call_local", "reliable")
func _net_state(new_state: int, new_owner: int, new_capturer: int, new_progress: float) -> void:
	state = new_state as State
	owner_team = new_owner
	capturer = new_capturer
	progress = new_progress
	_apply_look()


# --- Display (every peer) ---------------------------------------------------------

func color() -> Color:
	match state:
		State.INFESTED:
			return MONSTER_COLOR
		State.OWNED:
			return Net.team_color(owner_team)
	return NEUTRAL_COLOR


func _label_text() -> String:
	var text := "%s\n%s" % [display_name, info().name]
	if capturer >= 0 and progress > 0.0:
		text += "  %d%%" % roundi(progress * 100.0)
	elif gate and state == State.OWNED and not gate.is_broken():
		text += "  gate %d%%" % roundi(gate.health / gate.max_health * 100.0)
	return text


func _build_visuals() -> void:
	var r := radius()
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var torus := TorusMesh.new()
	torus.inner_radius = r - 0.25
	torus.outer_radius = r
	torus.rings = 64
	torus.material = _material
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.scale = Vector3(1, 0.3, 1)
	ring.position.y = 0.05
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	# Banner: a pole with a flag in the holder's color, beside the gate (if any).
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.06
	pole_mesh.bottom_radius = 0.08
	pole_mesh.height = 4.0
	var pole := MeshInstance3D.new()
	pole.mesh = pole_mesh
	pole.position = Vector3(2.2, 2.0, 0.0)
	add_child(pole)
	_flag_material = StandardMaterial3D.new()
	var flag_mesh := BoxMesh.new()
	flag_mesh.size = Vector3(1.2, 0.7, 0.04)
	flag_mesh.material = _flag_material
	var flag := MeshInstance3D.new()
	flag.mesh = flag_mesh
	flag.position = Vector3(2.85, 3.55, 0.0)
	add_child(flag)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.012
	_label.outline_size = 10
	_label.position = Vector3(0.0, 4.6, 0.0)
	_label.no_depth_test = true
	add_child(_label)


func _apply_look() -> void:
	if _material == null:
		return
	var c := color()
	_material.albedo_color = Color(c, 0.55)
	_flag_material.albedo_color = c
	if is_in_group(&"tracked"):
		set_meta(&"marker_color", c)
