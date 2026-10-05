extends Node
## Maps + world events (offline, King of the Hill on Crown Ruins):
## - the map: layout built, team bases from the map, the hill in the middle, 4 shrine bands (undead), shrine /
##   grove / starter chests, grove trees; walls stop shots; the hero walks from the base to the hill (side exit,
##   main lane);
## - the events setting: a list of ids (old true / false still read), each event switched on its own;
## - meteor shower (ring, impact hurts, shards), thunderstorm (rain, dark, lightning hurts), Blood Moon
##   (enemies faster / harder, ends), supply drop (Legendary chest lands, tracked).
##   "$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/map_events_test.gd
##   (with a window and --shot=<png>: a zoomed-out look at the map)

var failures := 0
var main: Node
var player: Player
var shot := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot = arg.substr(7)
	Net.open_offline_lobby()
	Net.settings.seed = 777
	Net.settings.mode = Net.Mode.KING_OF_THE_HILL
	Net.settings.map = "crown_ruins"
	Net.settings.events = ["supply_drop"]  # only the supply drop runs on its own (the others are started below)
	Net.settings.time_limit = 30
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	printerr(("PASS " if ok else "FAIL ") + what)
	if not ok:
		failures += 1


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, true).timeout


func _run() -> void:
	while get_tree().get_nodes_in_group(&"players").is_empty():
		await get_tree().process_frame
	await _wait(0.5)
	main = get_tree().current_scene
	player = get_tree().get_nodes_in_group(&"players")[0]
	player.max_health = 1e6
	player.health = 1e6
	player.regen_per_second = 0.0
	if shot != "":
		await _overview()
	_map_checks()
	await _walk_to_hill()
	_setting_checks()
	await _event_checks()
	printerr("DONE failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _overview() -> void:
	main.camera.offset *= 4.6
	player.global_position = Vector3(0, 0, 10)
	await _wait(1.5)
	get_viewport().get_texture().get_image().save_png(shot)
	main.camera.offset /= 4.6
	player.global_position = main.game_mode.spawn_point_for(1)


func _map_checks() -> void:
	var world: Node3D = main.get_node("World")
	_check(main.map.id == &"crown_ruins" and world.has_node("Layout"), "Crown Ruins layout built")
	_check(is_equal_approx(GameConfig.world_half, 52.0), "map size from the map (%.0f)" % GameConfig.world_half)
	_check(main.game_mode.team_bases.size() == 2 and main.game_mode.team_bases[0] == Vector3(0, 0, 44)
			and main.game_mode.team_bases[1] == Vector3(0, 0, -44), "team bases from the map: %s" % [main.game_mode.team_bases])
	_check(player.global_position.distance_to(Vector3(0, 0, 44)) < 4.0, "hero spawns in the south base")
	var hill := get_tree().get_first_node_in_group(&"hill") as Node3D
	_check(hill != null and hill.global_position.length() < 0.1, "the hill is in the middle")
	var bands := get_tree().get_nodes_in_group(&"warbands")
	_check(bands.size() == 4 and bands.all(func(b: Warband) -> bool: return b.faction == &"undead" and b.size == 6),
			"4 shrine bands of 6 undead (%d bands)" % bands.size())
	var rares := 0
	var commons := 0
	for child in world.get_children():
		if child is Chest:
			if (child as Chest).rarity == Chest.Rarity.RARE:
				rares += 1
			elif (child as Chest).rarity == Chest.Rarity.COMMON:
				commons += 1
	_check(rares == 4 and commons == 8, "shrine chests %d (Rare), grove chests %d (Common)" % [rares, commons])
	var herds := get_tree().get_nodes_in_group(&"herds")
	_check(herds.size() == 4, "a herd in each meadow: %s" % [herds.map(func(h: AnimalHerd) -> String: return h.species)])
	_check(get_tree().get_nodes_in_group(&"choppable").size() == 48, "grove trees: %d" % get_tree().get_nodes_in_group(&"choppable").size())
	# The ring walls stop a shot across them; the main lane entry is open.
	var space := world.get_world_3d().direct_space_state
	var blocked := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 0.6, 0) + Vector3(sin(0.5), 0, cos(0.5)) * 12.0,
			Vector3(0, 0.6, 0) + Vector3(sin(0.5), 0, cos(0.5)) * 20.0, GameConfig.LAYER_WORLD))
	_check(not blocked.is_empty(), "ring walls stop shots")
	var lane := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 0.6, 12), Vector3(0, 0.6, 20), GameConfig.LAYER_WORLD))
	_check(lane.is_empty(), "the main lane entry is open")


## Out the side exit, down the lane, around the halfway cover, onto the hill.
func _walk_to_hill() -> void:
	var route: Array[Vector3] = [Vector3(6.5, 0, 40), Vector3(6.5, 0, 33), Vector3(3.3, 0, 30), Vector3(3.3, 0, 22), Vector3(0, 0, 12), Vector3(0, 0, 4)]
	var time := 0.0
	for point in route:
		while time < 30.0:
			var to := point - player.global_position
			to.y = 0.0
			if to.length() < 0.8:
				break
			main.hud.joystick.output = Vector2(to.x, to.z).normalized()
			await get_tree().physics_frame
			time += 1.0 / 60.0
	main.hud.joystick.output = Vector2.ZERO
	_check(player.global_position.length() < 7.0, "the hero walks from the base to the hill in %.1f s" % time)
	await _wait(2.5)
	_check(main.game_mode.scores.get(0, 0) > 0, "holding the hill scores (%d)" % main.game_mode.scores.get(0, 0))


func _setting_checks() -> void:
	_check(WorldEvents.EVENTS.size() == 7, "7 world events")
	_check(WorldEvents.ids_from_setting(true).size() == 7 and WorldEvents.ids_from_setting(false).is_empty(),
			"old on / off settings still read")
	var events: WorldEvents = main.world_events
	_check(events.is_on("supply_drop") and not events.is_on("meteors") and not events.is_on("goblin"),
			"each event is switched on its own")


func _event_checks() -> void:
	var events: WorldEvents = main.world_events
	player.global_position = Vector3(20, 0, 10)
	await _wait(0.3)
	# Meteor shower: a meteor on the hero hurts.
	events.start_meteor_shower(0.5)
	var health := player.health
	events.drop_meteor(player.global_position)
	await _wait(events.meteor_warning + 0.3)
	_check(player.health < health, "a meteor hurts what it lands on (%.0f)" % (health - player.health))
	# Thunderstorm: rain + darkness, lightning hurts.
	events.start_storm(3.0)
	await _wait(0.5)
	var sun: DirectionalLight3D = main.get_node("Sun")
	_check(events.weather.storm and events.weather._rain != null, "the storm brings rain")
	await _wait(2.0)
	_check(sun.light_energy < 0.9, "and darkness (sun %.2f)" % sun.light_energy)
	health = player.health
	events.strike_lightning(player.global_position)
	await _wait(events.lightning_warning + 0.3)
	_check(player.health < health, "lightning hurts (%.0f)" % (health - player.health))
	await _wait(1.0)
	_check(not events.weather.storm, "the storm passes")
	# Blood Moon: enemies rage, then it sets.
	var orc := NetSpawn.unit(&"enemy", player.global_position + Vector3(8, 0, 0), {
			"scene": "res://scenes/characters/enemies/orc_grunt.tscn", "strength": 1.0, "coins": 1.0}) as Enemy
	orc.add_to_group(&"active_enemies")
	orc.provoke(player)
	events.start_blood_moon(2.0)
	await _wait(0.5)
	_check(GameConfig.blood_moon and orc.move_speed > orc._base_speed * orc.provoked_speed_multiplier * 1.1,
			"Blood Moon: enemies run faster (%.2f)" % orc.move_speed)
	await _wait(2.0)
	_check(not GameConfig.blood_moon, "the Blood Moon sets")
	orc.queue_free()
	# Supply drop: a Legendary chest lands where marked, tracked on the minimap.
	events.drop_supplies(player.global_position + Vector3(4, 0, 0), 1.0)
	await _wait(1.4)
	var crate := main.get_node("World").get_node_or_null("SupplyDrop_%d" % events.supply_drops) as Chest
	_check(crate != null and crate.rarity == Chest.Rarity.LEGENDARY and crate.is_in_group(&"tracked"),
			"the supply crate lands: a tracked Legendary chest")
