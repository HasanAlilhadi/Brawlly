extends Node
## Conquest frame cost by the Lair (offline): the hero walks from zone 2 to the Lair's gate (its garrison and Malakor
## rise, the lieutenants' armies are near), and the host's frame time is sampled on the way and then while standing
## at the gate; it must stay within BUDGET_MS.
##   "$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/conquest_perf_test.gd
## Then the hero stands in the middle of a horde (HORDE monsters attacking him and his SOLDIERS soldiers, out in
## the open): the frame must stay within HORDE_BUDGET_MS and no frame over HITCH_BUDGET_MS.
## --probe: then (in the horde) switch every kind of node's processing off in turn (by script, or engine class) and print what
## each costs (A/B against the frames right before and after).
## Without --headless (a window) it also prints what the renderer draws.

## The host's frame (scripts + physics) at the gate, headless: 13.9 ms before the AI level of detail, ~8.5 after.
const BUDGET_MS := 13.0
## No single frame on the way in may take longer (a garrison rising all at once took 60+ ms).
const HITCH_BUDGET_MS := 45.0
const HORDE := 100
const SOLDIERS := 30
## The host's frame in the middle of the horde fight, headless: 37.5 ms before the soldier-AI fixes and the
## adaptive level of detail (GameConfig.overloaded), ~20 after.
const HORDE_BUDGET_MS := 26.0
const HORDE_HITCH_MS := 100.0
const HORDE_TYPES: Array[String] = ["orc_grunt", "skeleton_warrior", "zombie", "orc_thrower", "skeleton_archer", "orc_brute",
		"vampire", "ghost"]
const PROBE_WINDOW := 1.2
const HITCH_MS := 40.0

var t := 0.0
var pt := 0.0
var phase := 0
var failures := 0
var main: Node
var mode: ConquestMode
var hero: Player
var frames: Array[float] = []
var last_us := 0
var probe := false
var buckets: Array = []  # [name, nodes]
var probe_index := 0
var probe_step := 0
var before_ms := 0.0
var off_ms := 0.0
var results: Array = []
var hitches := 0
## --soldiers=N: the hero's army in the horde (SOLDIERS by default).
var soldiers := SOLDIERS
## --kinds=a,b: probe only these kinds; --window=s: seconds per probe window.
var probe_kinds: PackedStringArray = []
var probe_window := PROBE_WINDOW
var last_nodes := 0
var worst_hitch := 0.0
var mon_proc := 0.0
var mon_phys := 0.0
var mon_n := 0


func _ready() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	probe = "--probe" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--soldiers="):
			soldiers = int(arg.substr(11))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--kinds="):
			probe = true
			probe_kinds = arg.substr(8).split(",")
		elif arg.begins_with("--window="):
			probe_window = float(arg.substr(9))
	Net.open_offline_lobby()
	Net.settings.mode = Net.Mode.CONQUEST
	Net.settings.seed = 77
	TerritoryNode.unguarded_falls = false
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")


func _log(msg: String) -> void:
	printerr("[%.1fs] %s" % [t, msg])


func _check(ok: bool, what: String) -> void:
	_log(("PASS " if ok else "FAIL ") + what)
	if not ok:
		failures += 1


func _done() -> void:
	_log("done: %d failure(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _next(to: int) -> void:
	phase = to
	pt = 0.0
	frames.clear()


func _sample() -> void:
	var now := Time.get_ticks_usec()
	if last_us > 0:
		var ms := (now - last_us) / 1000.0
		frames.append(ms)
		if phase == 1 and pt > 0.5:
			worst_hitch = maxf(worst_hitch, ms)
		if ms > HITCH_MS and phase > 0:
			hitches += 1
			if hitches <= 12:
				var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
				_log("  hitch %.0f ms (logistics tick in %.1f s, %+d nodes, %d active)" % [ms,
						mode.logistics.time_to_tick() if mode else -1.0, nodes - last_nodes,
						get_tree().get_nodes_in_group(&"active_enemies").size()])
	last_us = now
	last_nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))


func _stats() -> Dictionary:
	if frames.is_empty():
		return {"avg": 0.0, "p95": 0.0, "max": 0.0}
	var sorted := frames.duplicate()
	sorted.sort()
	var total := 0.0
	for f in sorted:
		total += f
	return {"avg": total / sorted.size(), "p95": sorted[int(sorted.size() * 0.95)], "max": sorted[-1]}


func _counts() -> String:
	var tree := get_tree()
	var awake := 0
	for band in tree.get_nodes_in_group(&"warbands"):
		if band.get("_active"):
			awake += 1
	return "units %d, enemies %d, active %d, bands awake %d/%d, nodes %d" % [
		tree.get_nodes_in_group(&"units").size(), tree.get_nodes_in_group(&"enemies").size(),
		tree.get_nodes_in_group(&"active_enemies").size(), awake, tree.get_nodes_in_group(&"warbands").size(),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT)]


func _report(label: String) -> Dictionary:
	var s := _stats()
	_log("%s: avg %.2f ms, p95 %.2f, max %.2f | %s" % [label, s.avg, s.p95, s.max, _counts()])
	_log("  process %.2f ms, physics %.2f ms, navigation %.2f ms, physics objects %d, pairs %d" % [
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)])
	if DisplayServer.get_name() != "headless":
		var vp := get_viewport().get_viewport_rid()
		_log("  render cpu %.2f ms, gpu %.2f ms" % [RenderingServer.viewport_get_measured_render_time_cpu(vp),
				RenderingServer.viewport_get_measured_render_time_gpu(vp)])
		_log("  render: %d objects, %d draw calls, %d primitives, fps %d" % [
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			Performance.get_monitor(Performance.TIME_FPS)])
	return s


func _process(delta: float) -> void:
	t += delta
	pt += delta
	_sample()
	mon_proc += Performance.get_monitor(Performance.TIME_PROCESS)
	mon_phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	mon_n += 1
	if hero:
		hero.health = hero.max_health
	match phase:
		0:
			main = get_tree().current_scene
			if main == null or main.name != "Main" or main.get("local_player") == null or pt < 1.0:
				return
			mode = main.game_mode as ConquestMode
			hero = main.local_player
			if "--no-anim-lod" in OS.get_cmdline_user_args():
				main.animation_lod.enabled = false
				main.animation_lod.process_mode = Node.PROCESS_MODE_DISABLED
			hero.max_health = 1000000.0
			var lair := mode.throne()
			# Start in zone 2, on the way in from the hero's Citadel.
			var home := mode.territories[hero.team_id].position
			var dir := (home - lair.position).normalized()
			hero.global_position = lair.position + dir * 110.0
			_next(1)
		1:
			# Walk in toward the gate.
			var lair := mode.throne()
			var to := lair.position - hero.global_position
			to.y = 0.0
			if to.length() > lair.radius() + 6.0:
				hero.global_position += to.normalized() * 6.0 * delta
			if pt >= 10.0:
				_report("walking in (zone %d)" % ConquestMode.zone_of(hero.global_position))
				frames.clear()
				pt = 0.0
				if to.length() <= lair.radius() + 6.5:
					_next(2)
		2:
			if pt < 15.0:
				return
			var s := _report("at the Lair's gate")
			var t0 := Time.get_ticks_usec()
			mode.logistics.tick()
			_log("  one logistics tick: %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
			_check(worst_hitch < HITCH_BUDGET_MS, "no hitch on the way in (worst %.0f ms < %.0f)" % [worst_hitch, HITCH_BUDGET_MS])
			_check(s.avg < BUDGET_MS, "the host keeps its frame budget at the gate (avg %.2f ms < %.1f)" % [s.avg, BUDGET_MS])
			_start_horde()
			_next(5)
		5:
			if pt < 3.0:
				mon_proc = 0.0
				mon_phys = 0.0
				mon_n = 0
				frames.clear()  # the horde closes in
				worst_hitch = 0.0
				return
			if pt < 13.0:
				worst_hitch = maxf(worst_hitch, frames[-1] if not frames.is_empty() else 0.0)
				return
			var s := _report("in the middle of the horde")
			var n := maxf(frames.size(), 1)
			_log("  avg process %.2f ms, avg physics %.2f ms" % [mon_proc / mon_n * 1000.0, mon_phys / mon_n * 1000.0])
			_check(worst_hitch < HORDE_HITCH_MS, "no big hitch in the fight (worst %.0f ms < %.0f)" % [worst_hitch, HORDE_HITCH_MS])
			_check(s.avg < HORDE_BUDGET_MS, "the host keeps its frame budget in the horde (avg %.2f ms < %.1f)" % [s.avg, HORDE_BUDGET_MS])
			if not probe:
				_done()
				return
			buckets = _buckets()
			_next(3)
		3:
			_run_probe()


## Out in the open (halfway between the hero's Citadel and the Lair): his soldiers around him, a horde coming at
## them from every side (they never die: the fight goes on).
func _start_horde() -> void:
	var home := mode.territories[hero.team_id].position
	var spot := home.lerp(mode.throne().position, 0.45)
	for place in mode.territories:
		if Vector2(place.position.x - spot.x, place.position.z - spot.z).length() < place.radius() + 25.0:
			spot += (spot - place.position).normalized() * 30.0
	hero.global_position = spot
	for i in soldiers:
		var at := spot + Vector3(cos(i * 2.4), 0.0, sin(i * 2.4)) * (1.5 + 0.4 * sqrt(i))
		var ally := NetSpawn.unit(&"ally", at, {"owner": hero.peer_id, "team": hero.team_id,
				"weapon": ["sword", "sword", "bow", "wizard", "healer"][i % 5]}) as Ally
		if ally:
			ally.max_health = 1e6
			ally.health = 1e6
	for i in HORDE:
		var angle := TAU * i / HORDE
		var at := spot + Vector3(cos(angle), 0.0, sin(angle)) * (9.0 + (i % 4) * 1.5)
		var enemy := NetSpawn.unit(&"enemy", at, {"scene": WorldEvents.ENEMIES + HORDE_TYPES[i % HORDE_TYPES.size()] + ".tscn",
				"strength": 1.0, "coins": 1.0}) as Enemy
		if enemy:
			enemy.add_to_group(&"active_enemies")
			enemy.max_health = 1e6
			enemy.health = 1e6
			enemy.provoke(hero, true)


## Every processing node by kind: its script's file, else its engine class.
func _buckets() -> Array:
	var by_kind := {}
	for node in _all(get_tree().root):
		if node == self or not (node.is_processing() or node.is_physics_processing() or node.is_processing_internal()
				or node.is_physics_processing_internal()):
			continue
		var script := node.get_script() as Script
		var kind: String = script.resource_path.get_file() if script else node.get_class()
		if not by_kind.has(kind):
			by_kind[kind] = []
		by_kind[kind].append(node)
	var list := []
	for kind in by_kind:
		if not probe_kinds.is_empty() and not probe_kinds.has(kind):
			continue
		if (by_kind[kind] as Array).size() > 0:
			list.append([kind, by_kind[kind]])
	return list


func _all(node: Node) -> Array[Node]:
	var found: Array[Node] = [node]
	for child in node.get_children():
		found.append_array(_all(child))
	return found


## A/B/A: frames with the kind on, off, on again; the cost is off against the average of the two on windows.
func _run_probe() -> void:
	if probe_index >= buckets.size():
		results.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
		_log("costs (ms a frame, kind x count):")
		for row in results:
			_log("  %6.2f  %s x%d" % [row[1], row[0], row[2]])
		_done()
		return
	if pt < probe_window:
		return
	var avg: float = _stats().avg
	var bucket: Array = buckets[probe_index]
	match probe_step:
		0:
			before_ms = avg
			_switch(bucket[1], false)
		1:
			off_ms = avg
			_switch(bucket[1], true)
		2:
			results.append([bucket[0], (before_ms + avg) * 0.5 - off_ms, (bucket[1] as Array).size()])
			probe_index += 1
	probe_step = (probe_step + 1) % 3
	frames.clear()
	pt = 0.0


func _switch(nodes: Array, on: bool) -> void:
	for node in nodes:
		if not is_instance_valid(node):
			continue
		var n := node as Node
		if not on:
			n.set_meta(&"probe_state", [n.is_processing(), n.is_physics_processing(), n.is_processing_internal(),
					n.is_physics_processing_internal()])
			n.set_process(false)
			n.set_physics_process(false)
			n.set_process_internal(false)
			n.set_physics_process_internal(false)
		elif n.has_meta(&"probe_state"):
			var state: Array = n.get_meta(&"probe_state")
			n.set_process(state[0])
			n.set_physics_process(state[1])
			n.set_process_internal(state[2])
			n.set_physics_process_internal(state[3])
			n.remove_meta(&"probe_state")
