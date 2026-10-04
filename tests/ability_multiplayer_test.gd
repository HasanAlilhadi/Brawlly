extends Node
## Real ENet host/client regression for all three abilities and their remote effects.
## Run two test_runner processes with --test=res://tests/ability_multiplayer_test.gd
## --role=host / --role=client and the same --port (omit --fixed-fps for network runs).

var role := "host"
var failures := 0
var client_ready := false
var finished := false
var casts: Array[Player] = []
var rounds := 0
var targets: Array[TrainingTarget] = []
var damage_impacts_seen := false


func _check(ok: bool, message: String) -> void:
	printerr(("PASS " if ok else "FAIL ") + role + ": " + message)
	if not ok:
		failures += 1


func _ready() -> void:
	name = "AbilityMultiplayerTest"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.substr(7)
	get_tree().create_timer(25.0).timeout.connect(func() -> void:
		if not finished:
			printerr("FAIL multiplayer ability test timed out")
			get_tree().quit(1))
	if role == "host":
		_check(Net.host() == OK, "ENet host starts")
		while Net.players.size() < 2:
			await get_tree().process_frame
		Net.settings.training = true
		Net.settings.events = false
		Net.start_game(false)
	else:
		_check(Net.join("127.0.0.1", Net.port) == OK, "ENet client connects")
	while get_tree().current_scene == null or get_tree().current_scene.name != "Main":
		await get_tree().process_frame
	var main := get_tree().current_scene
	while main.local_player == null:
		await get_tree().process_frame
	main.set_physics_process(false)
	if role == "client":
		_client_ready.rpc_id(1)
		return
	_check_spawn_effects(main.world)
	while not client_ready:
		await get_tree().process_frame
	var client_id: int = multiplayer.get_peers()[0]
	for owner_id in [1, client_id]:
		for class_id in [&"swordsman", &"spearman", &"bowman"]:
			var at := Vector3(-12 + casts.size() * 3, 0, -10)
			var player: Player = main._spawn_player(owner_id, class_id, at)
			player.face_now(Vector3.RIGHT)
			player.net_yaw = PI * 0.5
			# Exercise Bull Rush activation from the ranged weapon on every peer.
			if class_id == &"spearman":
				player.switch_weapon()
			casts.append(player)
	await get_tree().create_timer(0.4).timeout
	# Targets exist only on the server: clients must receive their authoritative impact effects.
	for player in casts:
		if player.class_def.ability == &"bow_rain":
			var target := preload("res://scenes/training/training_target.tscn").instantiate() as TrainingTarget
			main.world.add_child(target)
			target.global_position = Vector3(player.global_position.x, 0, -6)
			targets.append(target)
	for player in casts:
		if player.peer_id == 1:
			_start_cast(player)
	var paths: Array[NodePath] = []
	for player in casts:
		if player.peer_id == client_id:
			paths.append(player.get_path())
	_request_client_casts.rpc_id(client_id, paths)


func _start_cast(player: Player) -> void:
	if player.class_def.ability == &"bow_rain":
		player.request_bow_rain(Vector3(player.global_position.x, 0, -6))
	else:
		player.request_ability()


@rpc("any_peer", "call_remote", "reliable")
func _client_ready() -> void:
	if multiplayer.is_server():
		client_ready = true


@rpc("authority", "call_remote", "reliable")
func _request_client_casts(paths: Array) -> void:
	rounds += 1
	for path in paths:
		var player := get_node(path) as Player
		_start_cast(player)
	await get_tree().create_timer(0.8).timeout
	_check_active()
	await get_tree().create_timer(4.5).timeout
	_check_finished()
	_check(damage_impacts_seen, "client receives impact effects for server-only character colliders")
	if rounds == 1:
		_restart.rpc_id(1, paths)
		return
	_results.rpc_id(1, failures)
	finished = true
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(1 if failures else 0)


func _check_active() -> void:
	var counts := {&"whirlwind": 0, &"bull_rush": 0, &"bow_rain": 0}
	for player in get_tree().get_nodes_in_group(&"players"):
		if not player.ability_active:
			continue
		counts[player.class_def.ability] += 1
		match player.class_def.ability:
			&"whirlwind":
				_check(is_instance_valid(player._whirlwind_arc) and player._whirlwind_arc.visible,
						"Whirlwind arc visible for peer %d" % player.peer_id)
				var expected := wrapf(player.ability_start_yaw
						- deg_to_rad(Player.WHIRLWIND_SPIN) * player._ability_visual_elapsed, -PI, PI)
				_check(absf(angle_difference(player._spin_world_yaw, expected)) < 0.01,
						"Whirlwind follows replicated cast phase")
			&"bull_rush":
				_check(is_instance_valid(player._rush_wind) and player._rush_wind.is_visible_in_tree(),
						"Bull Rush spear effect visible for peer %d" % player.peer_id)
				_check(player.current_weapon() == "spear" and player._bull_rush_direction.x > 0.95,
						"Bull Rush weapon and direction replicate")
			&"bow_rain":
				_check(player._bow_rain_area.visible and player._bow_rain_area.global_position.distance_to(
						player.bow_rain_target + Vector3(0, 0.035, 0)) < 0.01,
						"Bow Rain marker visible at authoritative target for peer %d" % player.peer_id)
	_check(counts == {&"whirlwind": 2, &"bull_rush": 2, &"bow_rain": 2}, "host and client activate every class ability")
	var impacts := 0
	for node in get_tree().current_scene.world.get_children():
		if node is CPUParticles3D:
			impacts += 1
	_check(impacts > 0, "server-confirmed Bow Rain impact bursts arrive on client")
	if rounds == 2:
		_check(true, "all ability effects restart on the second cast")


func _check_finished() -> void:
	for player in get_tree().get_nodes_in_group(&"players"):
		_check(not player.ability_active, "ability ends for peer %d" % player.peer_id)
		if is_instance_valid(player._rush_wind):
			_check(not player._rush_wind.visible, "Bull Rush effect ends")
		if is_instance_valid(player._whirlwind_arc):
			_check(not player._whirlwind_arc.visible, "Whirlwind effect ends")
		_check(not player._bow_rain_area.visible, "Bow Rain marker ends")


@rpc("any_peer", "call_remote", "reliable")
func _results(client_failures: int) -> void:
	if not multiplayer.is_server():
		return
	failures += client_failures
	for target in targets:
		_check(target.total_damage() > 0, "Bow Rain still deals authoritative damage")
	_check_finished()
	printerr("DONE multiplayer failures=", failures)
	finished = true
	get_tree().quit(1 if failures else 0)


@rpc("any_peer", "call_remote", "reliable")
func _restart(paths: Array) -> void:
	if not multiplayer.is_server():
		return
	for player in casts:
		if player.peer_id == 1:
			_start_cast(player)
	_request_client_casts.rpc_id(multiplayer.get_remote_sender_id(), paths)


func _check_spawn_effects(world: Node3D) -> void:
	for class_id in [&"swordsman", &"spearman", &"bowman"]:
		var player := preload("res://scenes/characters/player.tscn").instantiate() as Player
		# Model a spawn snapshot whose properties are applied before _ready.
		player.get_node("Sync").free()
		player.set_class(class_id)
		player.ability_start_yaw = 0.7
		player.ability_elapsed = 0.8
		player._bull_rush_direction = Vector3.RIGHT
		player.bow_rain_target = Vector3(8, 0, -6)
		player.ability_active = true
		player.set_physics_process(false)
		world.add_child(player)
		match class_id:
			&"swordsman":
				_check(is_instance_valid(player._whirlwind_arc) and player._whirlwind_arc.visible,
						"active Whirlwind spawn restores its arc and phase")
			&"spearman":
				_check(is_instance_valid(player._rush_wind) and player._rush_wind.visible,
						"active Bull Rush spawn restores the spear effect")
			&"bowman":
				_check(player._bow_rain_area.visible and player._bow_rain_area.global_position.x == 8.0,
						"active Bow Rain spawn restores its target marker")
		if class_id != &"bowman":
			player._play_action_local("attack-melee-right", 0.4, Unit.ARM_RIGHT)
			_check(player._slash_tween == null, "delayed normal attack cannot interrupt the ability")
		player.free()


func _process(_delta: float) -> void:
	if role != "client" or get_tree().current_scene == null or get_tree().current_scene.name != "Main":
		return
	# Impact bursts are brief: observe the whole cast instead of sampling one arbitrary frame.
	for node in get_tree().current_scene.world.get_children():
		if node is CPUParticles3D and node.color_ramp.get_color(0).r > 0.95:
			damage_impacts_seen = true
