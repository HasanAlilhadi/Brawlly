extends Node
## Last Stand (solo, offline): ten circles planned from the seed (apart, inside the bigger world, clear of camps /
## trees, a gold vein in each), one hero needed when alone, the clock only runs inside and keeps its progress
## outside, a held circle pays coins and makes orcs stronger, assault squads come while a hero is near, gold veins
## pay per hit / run dry / grow back, the last circle brings the Warlord and holding it wins. `--defeat`: the hero
## dies instead → no respawn, defeat. `--map=<index>` picks the map (MapCatalog.MAPS).
##   "$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/last_stand_test.gd
##   "$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/last_stand_test.gd --defeat

var t := 0.0
var phase := 0
var pt := 0.0
var failures := 0
var main: Node
var player: Player
var mode: GameMode
var defeat := false
var map_index := 0
var coins_before := 0
var strength_before := 0.0
var held_before := 0.0
var vein: GoldVein


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--defeat":
			defeat = true
		elif arg.begins_with("--map="):
			map_index = int(arg.substr(6))
	Net.open_offline_lobby()
	Net.settings.mode = Net.Mode.LAST_STAND
	Net.settings.map = map_index
	Net.settings.seed = 4242
	Net.settings.events = false
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")


func _log(msg: String) -> void:
	printerr("[%.1fs] %s" % [t, msg])


func _check(ok: bool, what: String) -> void:
	_log(("PASS " if ok else "FAIL ") + what)
	if not ok:
		failures += 1


func _next() -> void:
	phase += 1
	pt = 0.0


func _put(at: Vector3) -> void:
	player.global_position = at
	player.net_position = at


func _done() -> void:
	_log("done: %d failure(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _process(delta: float) -> void:
	t += delta
	pt += delta
	if t > 240.0:
		_check(false, "finished in time (phase %d)" % phase)
		_done()
		return
	main = get_tree().current_scene
	if main == null or main.name != "Main" or main.get("local_player") == null:
		return
	player = main.local_player
	mode = main.game_mode
	match phase:
		0:
			if pt < 0.5:
				return
			var circles := mode.circles
			_check(circles.size() == GameMode.CIRCLE_COUNT, "ten circles (%d)" % circles.size())
			var apart := true
			var inside := true
			for i in circles.size():
				inside = inside and absf(circles[i].x) < GameConfig.world_half - 10.0 and absf(circles[i].z) < GameConfig.world_half - 10.0
				for j in i:
					apart = apart and circles[i].distance_to(circles[j]) >= GameMode.CIRCLE_SPACING - 0.01
			_check(apart and inside, "circles apart and inside the world")
			_check(circles[0].length() < circles[9].length(), "the last circle is farther out than the first")
			var default_half := clampf(40.0 + sqrt(float(Net.settings.camp_count)) * 10.0, 60.0, 170.0)
			_check(GameConfig.world_half > default_half, "bigger world (%.0f > %.0f)" % [GameConfig.world_half, default_half])
			_check(mode.hold_circle != null and mode.hold_circle.position.distance_to(circles[0]) < 0.1, "the circle stands on circle 1")
			var blocked := 0
			for node in main.world.get_children():
				var body := node as Node3D
				if body is ChoppableTree or body is Camp or (body is StaticBody3D and str(body.name).begins_with("Solid_")):
					for c in circles:
						if Vector2(body.global_position.x - c.x, body.global_position.z - c.z).length() < HoldCircle.RADIUS + 0.5:
							blocked += 1
			_check(blocked == 0, "circles clear of trees, camps and landmarks (%d in the way)" % blocked)
			var veins := get_tree().get_nodes_in_group(&"gold_veins")
			var near_spawn := veins.filter(func(v: Node) -> bool: return (v as Node3D).global_position.length() < WorldBuilder.SPAWN_SAFE_RADIUS)
			_check(veins.size() >= 8 and near_spawn.size() == 1, "gold veins (%d, %d at the spawn)" % [veins.size(), near_spawn.size()])
			var per_circle := true
			for c in circles:
				per_circle = per_circle and veins.any(func(v: Node) -> bool: return (v as Node3D).global_position.distance_to(c) < HoldCircle.RADIUS)
			_check(per_circle, "a gold vein in every circle")
			var env := (main.get_node("WorldEnvironment") as WorldEnvironment).environment
			_check(env.background_color.is_equal_approx(MapCatalog.get_map(map_index).sky), "map light: %s" % MapCatalog.get_map(map_index).name)
			_check(not main.game_mode.uses_respawn(), "no respawns")
			_check(not main.world_events.waves_enabled, "border waves off")
			player.max_health = 1e6
			player.health = 1e6
			mode.circle_seconds = 3.0
			_next()
		1:
			if pt < 0.3:
				return
			_check(mode.circle_required == 1, "alone: one hero needed (%d)" % mode.circle_required)
			_check(main.hud.get("_objective_panel").visible, "objective card shown")
			coins_before = player.coins
			strength_before = GameConfig.orc_strength
			_put(mode.circles[0])
			_next()
		2:
			if mode.circle_index == 1:
				var reward := GameMode.CIRCLE_REWARD
				_check(player.coins - coins_before >= reward, "circle 1 held: +%d coins" % (player.coins - coins_before))
				_check(GameConfig.orc_strength > strength_before, "orcs stronger (%.2f → %.2f)" % [strength_before, GameConfig.orc_strength])
				_check(mode.hold_circle.position.distance_to(mode.circles[1]) < 0.1, "the circle moved on")
				mode.circle_seconds = 4.0
				_put(mode.circles[1] + Vector3(HoldCircle.RADIUS + 4.0, 0, 0))
				_next()
			elif pt > 8.0:
				_check(false, "circle 1 held in time (%.1f s)" % mode.circle_time)
				_next()
		3:
			# Outside (but near): no progress.
			if pt < 1.0:
				return
			_check(mode.circle_time < 0.05, "outside: the clock stops (%.2f)" % mode.circle_time)
			_put(mode.circles[1])
			_next()
		4:
			if pt < 1.5:
				return
			held_before = mode.circle_time
			_put(mode.circles[1] + Vector3(HoldCircle.RADIUS + 4.0, 0, 0))
			_next()
		5:
			if pt < 1.0:
				return
			_check(held_before > 1.0 and absf(mode.circle_time - held_before) < 0.1,
					"stepping out keeps the progress (%.2f → %.2f)" % [held_before, mode.circle_time])
			_next()
		6:
			# Assault squads come while a hero is near the circle (the first ASSAULT_FIRST s after arriving).
			var raiders := get_tree().get_nodes_in_group(&"wave_enemies")
			if raiders.is_empty() and pt < GameMode.ASSAULT_FIRST + 1.0:
				return
			_check(not raiders.is_empty(), "an assault squad marches on the circle (%d orcs)" % raiders.size())
			if not raiders.is_empty():
				var orc := raiders[0] as Enemy
				_check(orc.global_position.distance_to(mode.circles[1]) > 15.0, "it comes from out of sight")
				_check(orc.max_health > 80.0, "assault orcs are stronger than a plain spearman (%.0f hp)" % orc.max_health)
			for orc in raiders:
				(orc as Node).queue_free()
			_put(mode.circles[1])
			phase = 60
			pt = 0.0
		60:
			if mode.circle_index == 2:
				_check(true, "circle 2 held after coming back")
				vein = get_tree().get_nodes_in_group(&"gold_veins").filter(func(v: Node) -> bool:
					return (v as Node3D).global_position.distance_to(mode.circles[2]) < HoldCircle.RADIUS)[0]
				_put(vein.global_position + Vector3(1.6, 0, 0))
				mode.circle_seconds = 1000.0
				_next()
			elif pt > 10.0:
				_check(false, "circle 2 held in time (%.1f s)" % mode.circle_time)
				_next()
		61:
			# Mine the vein dry: COINS_PER_HIT a hit, ignoring hits closer than HIT_COOLDOWN.
			if pt < 0.3:
				return
			var before := vein.gold
			vein.take_damage(10.0, player)
			vein.take_damage(10.0, player)
			_check(vein.gold == before - GoldVein.COINS_PER_HIT, "a hit knocks loose %d gold (%d → %d)" % [GoldVein.COINS_PER_HIT, before, vein.gold])
			_next()
		62:
			if vein.gold > 0:
				vein.take_damage(10.0, player)
				return
			_check(not vein.get_node("Model/Crystals").visible, "an empty vein has no crystals")
			_next()
		63:
			if pt < GoldVein.REGROW_DELAY + GoldVein.REGROW_EVERY + 0.5:
				return
			_check(vein.gold == GoldVein.REGROW_STEP, "the vein grows back (%d gold)" % vein.gold)
			if defeat:
				_next()
				return
			mode.circle_seconds = 2.0
			mode._start_circle(GameMode.CIRCLE_COUNT - 1)
			phase = 20
			pt = 0.0
		64:
			# --defeat: the hero falls → no respawn, defeat.
			player.max_health = 100.0
			player.health = 100.0
			player.take_damage(1000.0)
			_next()
		65:
			if mode.is_over:
				_check(main.hud.end_title.text == "Defeat", "defeat (%s)" % main.hud.end_title.text)
				_check(player.is_dead, "the fallen hero stays dead")
				_done()
			elif pt > 5.0:
				_check(false, "defeat after the only hero fell")
				_done()
		20:
			if pt < 0.3:
				return
			_check(is_instance_valid(main.world_events.warlord), "the last circle brings the Warlord")
			_put(mode.circles[GameMode.CIRCLE_COUNT - 1])
			_next()
		21:
			if mode.is_over:
				_check(main.hud.end_title.text == "Victory!", "victory after the tenth circle (%s)" % main.hud.end_title.text)
				_done()
			elif pt > 8.0:
				_check(false, "victory in time")
				_done()
