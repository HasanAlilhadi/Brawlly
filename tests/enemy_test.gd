extends Node
## Warbands and enemy types (offline, events off):
## - world: warbands instead of camps (sizes 3..25, bigger far away, none near the spawn), graveyards with
##   undead bands, both factions, 7+ enemy types in the field, far bands paused;
## - bands march (paused ones too), members keep to their formation, one alert sends the whole band;
## - every type does its thing: grunt melee, thrower spears from range, brute charge + stomp, skeleton flanks
##   and reassembles (a hit on the pile finishes it), archer shoots from range, zombie lunges and bursts on
##   death, ghost floats / phases through hits / ignores walls, vampire blinks behind and steals life,
##   necromancer summons skeletons and casts bolts, bosses lead bands and their fall routs the band.
##   "$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/enemy_test.gd
const ENEMIES := "res://scenes/characters/enemies/"

var failures := 0
var main: Node
var player: Player


func _ready() -> void:
	Net.open_offline_lobby()
	Net.settings.seed = 4242
	Net.settings.events = false
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
	_make_tough()
	await _world_checks()
	await _march_checks()
	_clear_around(Vector3.ZERO, 40.0)
	await _type_checks()
	await _surround_check()
	await _boss_checks()
	printerr("DONE failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _make_tough() -> void:
	player.max_health = 1e7
	player.health = 1e7
	player.regen_per_second = 0.0


func _bands() -> Array[Warband]:
	var list: Array[Warband] = []
	for node in get_tree().get_nodes_in_group(&"warbands"):
		list.append(node as Warband)
	return list


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- World --------------------------------------------------------------------------------

func _world_checks() -> void:
	var bands := _bands()
	_check(get_tree().get_nodes_in_group(&"camps").is_empty(), "no camps left in the world")
	_check(bands.size() >= 20, "warbands placed: %d (asked for %d)" % [bands.size(), Net.settings.band_count])
	var yards := main.get_node("World").get_children().filter(func(n: Node) -> bool: return n.name.begins_with("Graveyard_"))
	_check(not yards.is_empty(), "graveyards built: %d" % yards.size())
	var undead := bands.filter(func(b: Warband) -> bool: return b.faction == &"undead").size()
	_check(undead > 0 and undead < bands.size(), "both factions roam: %d undead, %d orc bands" % [undead, bands.size() - undead])
	var nearest := INF
	var near_sizes := 0.0
	var far_sizes := 0.0
	var near_count := 0
	var far_count := 0
	var sizes_ok := true
	var bosses := 0
	for band in bands:
		var d := _flat(band.global_position, Vector3.ZERO)
		nearest = minf(nearest, d)
		sizes_ok = sizes_ok and band.size >= 3 and band.size <= 25
		if band.has_boss:
			bosses += 1
		if d < GameConfig.world_half * 0.6:
			near_sizes += band.size
			near_count += 1
		else:
			far_sizes += band.size
			far_count += 1
	_check(nearest >= 24.0, "no warband near the spawn (nearest %.1f m)" % nearest)
	_check(sizes_ok, "band sizes within 3..25")
	var near_avg := near_sizes / maxf(near_count, 1.0)
	var far_avg := far_sizes / maxf(far_count, 1.0)
	_check(far_avg > near_avg, "bands grow away from the spawn (near %.1f, far %.1f members)" % [near_avg, far_avg])
	printerr("INFO %d boss-led bands, %d large (>= %d) on the minimap" % [bosses, bands.filter(
			func(b: Warband) -> bool: return b.alive >= Warband.LARGE_SIZE).size(), Warband.LARGE_SIZE])
	var names := {}
	var paused := 0
	var awake_far := 0
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		names[enemy.enemy_name] = true
		if is_instance_valid(enemy.band) and _flat(enemy.band.global_position, player.global_position) > 60.0:
			if enemy.process_mode == Node.PROCESS_MODE_DISABLED:
				paused += 1
			else:
				awake_far += 1
	_check(names.size() >= 7, "%d enemy types in the field: %s" % [names.size(), ", ".join(PackedStringArray(names.keys()))])
	_check(paused > 0 and awake_far == 0, "far bands are paused (%d paused, %d awake)" % [paused, awake_far])
	# Undead bands near graveyards; leaders: bosses in the middle.
	for band in bands:
		if band.has_boss and band.leader:
			_check(band.leader.component(BossTrait) != null, "boss-led band (%d) has its boss as leader: %s" % [band.size, band.leader.enemy_name])
			break


# --- Marching -------------------------------------------------------------------------------

func _march_checks() -> void:
	var start := {}
	for band in _bands():
		start[band] = band.global_position
	await _wait(14.0)
	var moved := 0
	for band in _bands():
		if _flat(band.global_position, start[band]) > 3.0:
			moved += 1
	_check(moved >= _bands().size() / 3, "bands march: %d of %d moved over 3 m in 14 s" % [moved, _bands().size()])
	# Walk up to a small band (not too close): it wakes up and keeps formation.
	var band: Warband = null
	for candidate in _bands():
		if candidate.size <= 6 and not candidate.is_dead and (band == null or _flat(candidate.global_position, Vector3.ZERO) < _flat(band.global_position, Vector3.ZERO)):
			band = candidate
	if band == null:
		_check(false, "a small band to watch")
		return
	var away := (Vector3.ZERO - band.global_position)
	away.y = 0.0
	player.global_position = band.global_position + away.normalized() * 26.0
	await _wait(6.0)
	var awake := band.members().all(func(e: Enemy) -> bool: return e.process_mode != Node.PROCESS_MODE_DISABLED)
	_check(awake, "a band wakes up when a hero comes within %.0f m" % band.activation_range)
	var spread := 0.0
	for enemy in band.members():
		spread = maxf(spread, _flat(enemy.global_position, band.global_position))
	_check(spread < 6.0, "members march in formation (farthest %.1f m from the band)" % spread)
	band.alert(player)
	var all_provoked := band.members().all(func(e: Enemy) -> bool: return e.is_provoked() and e.target == player)
	_check(all_provoked, "one alert sends the whole band (%d members) after the hero" % band.members().size())
	_clear_around(band.global_position, 20.0)
	player.global_position = Vector3.ZERO
	await _wait(1.0)


func _clear_around(at: Vector3, radius: float) -> void:
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if _flat(enemy.global_position, at) < radius:
			enemy.queue_free()


# --- Enemy types ---------------------------------------------------------------------------------

func _spawn(type: String, offset: Vector3) -> Enemy:
	var enemy := NetSpawn.unit(&"enemy", player.global_position + offset, {"scene": ENEMIES + type + ".tscn",
			"strength": 1.0, "coins": 1.0}) as Enemy
	enemy.add_to_group(&"active_enemies")
	enemy.health_drop_chance = 0.0  # no potions healing the hero between checks
	return enemy


## Runs `seconds`, noting which of `enemy`'s actions were active at some point.
func _watch(enemy: Enemy, seconds: float) -> Dictionary:
	var used := {}
	var left := seconds
	while left > 0.0 and is_instance_valid(enemy) and not enemy.is_dead:
		for child in enemy.get_children():
			if child is EnemyAction and ((child as EnemyAction).is_active() or (child as EnemyAction)._cooldown_left > 0.05):
				used[String(child.name)] = true
		await get_tree().physics_frame
		left -= 1.0 / 60.0
	return used


func _type_checks() -> void:
	player.global_position = Vector3.ZERO
	# Grunt: walks up and swings.
	var health := player.health
	var grunt := _spawn("orc_grunt", Vector3(3, 0, 0))
	await _wait(0.4)
	_check(is_equal_approx(grunt.model.scale.x, 1.25), "spawning is not a hit: the grunt keeps its size (%.2f)" % grunt.model.scale.x)
	grunt.provoke(player)
	await _wait(4.0)
	_check(player.health < health, "orc grunt melees (%.0f damage)" % (health - player.health))
	grunt.queue_free()

	# Thrower: keeps its distance and throws spears.
	health = player.health
	var thrower := _spawn("orc_thrower", Vector3(7, 0, 0))
	thrower.provoke(player)
	var closest := INF
	for i in 360:
		await get_tree().physics_frame
		closest = minf(closest, thrower.flat_distance_to(player))
	_check(player.health < health, "orc thrower hits with spears (%.0f damage)" % (health - player.health))
	_check(closest > 3.0, "orc thrower keeps its distance (closest %.1f m)" % closest)
	thrower.queue_free()

	# Brute: charges from range, stomps up close.
	var brute := _spawn("orc_brute", Vector3(9, 0, 0))
	brute.provoke(player)
	var used := await _watch(brute, 9.0)
	_check(used.has("Charge"), "orc brute charges")
	_check(used.has("Stomp"), "orc brute stomps")
	brute.take_damage(brute.max_health * 0.7, player)
	await _wait(0.3)
	_check(brute.rage_speed > 1.0, "orc brute enrages when hurt")
	brute.queue_free()

	# Skeleton warrior: comes at the hero's side or back, falls apart and gets up once, a hit on the pile ends it.
	player.face_now(Vector3(0, 0, 1))
	var skeleton := _spawn("skeleton_warrior", Vector3(0, 0, 6))
	skeleton.provoke(player)
	var side_angle := -1.0
	for i in 360:
		await get_tree().physics_frame
		if side_angle < 0.0 and skeleton.flat_distance_to(player) < 1.8:
			var to := skeleton.global_position - player.global_position
			side_angle = rad_to_deg(player.facing().angle_to(Vector3(to.x, 0, to.z).normalized()))
	_check(side_angle > 50.0, "skeleton warrior flanks (comes in %.0f° off the hero's facing)" % side_angle)
	skeleton.take_damage(1e5, player)
	_check(skeleton.is_downed and not skeleton.is_dead, "skeleton falls apart instead of dying")
	await _wait(4.0)
	_check(not skeleton.is_downed and not skeleton.is_dead and skeleton.health > 0.0,
			"skeleton gets back up (%.0f hp)" % skeleton.health)
	skeleton.take_damage(1e5, player)
	_check(skeleton.is_dead, "the second time it stays down")
	var pile := _spawn("skeleton_warrior", Vector3(-3, 0, 0))
	await _wait(0.3)
	pile.take_damage(1e5, player)
	pile.take_damage(1.0, player)
	_check(pile.is_dead, "a hit on the bone pile finishes it")

	# Skeleton archer: shoots from far.
	health = player.health
	var archer := _spawn("skeleton_archer", Vector3(-9, 0, 0))
	archer.provoke(player)
	closest = INF
	for i in 420:
		await get_tree().physics_frame
		closest = minf(closest, archer.flat_distance_to(player))
	_check(player.health < health, "skeleton archer shoots (%.0f damage)" % (health - player.health))
	_check(closest > 5.0, "skeleton archer stays back (closest %.1f m)" % closest)
	archer.queue_free()

	# Zombie: lunges, then bursts when it dies.
	var zombie := _spawn("zombie", Vector3(0, 0, -4))
	zombie.provoke(player)
	used = await _watch(zombie, 6.0)
	_check(used.has("Lunge"), "zombie lunges")
	zombie.global_position = player.global_position + Vector3(0.8, 0, 0)
	await get_tree().physics_frame
	zombie.health_drop_chance = 0.0  # a potion landing on the hero would heal the burst away
	health = player.health
	zombie.take_damage(1e5, player)
	await _wait(1.3)
	_check(player.health < health - 5.0, "zombie bursts on death (%.0f damage)" % (health - player.health))

	# Ghost: floats, flies through walls, phases through hits.
	var ghost := _spawn("ghost", Vector3(3, 0, 3))
	ghost.provoke(player)
	await _wait(0.6)
	_check(ghost.model.position.y > 0.15, "ghost floats (%.2f m up)" % ghost.model.position.y)
	_check(ghost.collision_mask & GameConfig.LAYER_WORLD == 0, "ghost drifts through trees and walls")
	var phase := ghost.component(PhaseAbility) as PhaseAbility
	phase.start(player)
	var ghost_health := ghost.health
	ghost.take_damage(30.0, player)
	_check(is_equal_approx(ghost.health, ghost_health), "a phasing ghost can't be hurt")
	await _wait(2.0)
	ghost.take_damage(5.0, player)
	_check(ghost.health < ghost_health or phase.is_active(), "after phasing it can be hurt again")
	ghost.queue_free()

	# Vampire: blinks behind the hero, heals by biting.
	var vampire := _spawn("vampire", Vector3(10, 0, 0))
	vampire.provoke(player)
	used = await _watch(vampire, 5.0)
	_check(used.has("Blink"), "vampire blinks")
	_check(vampire.flat_distance_to(player) < 4.5, "vampire ends up next to the hero (%.1f m)" % vampire.flat_distance_to(player))
	vampire.health = vampire.max_health * 0.4
	var bitten := vampire.health
	await _wait(6.0)
	_check(vampire.health > bitten, "vampire heals by biting (%.0f -> %.0f)" % [bitten, vampire.health])
	vampire.queue_free()

	# Necromancer: raises skeletons, casts bolts from range.
	health = player.health
	var necro := _spawn("necromancer", Vector3(0, 0, 10))
	necro.provoke(player)
	used = await _watch(necro, 7.0)
	var raised := get_tree().get_nodes_in_group(&"enemies").filter(func(e: Node) -> bool:
		return (e as Enemy).rising and not (e as Enemy).is_dead).size()
	_check(used.has("Summon") and raised >= 1, "necromancer raises skeletons (%d up)" % raised)
	_check(used.has("Bolt"), "necromancer casts bolts")
	_clear_around(player.global_position, 30.0)
	await _wait(0.5)


## A band of orcs on one hero spreads around them instead of queueing on one side.
func _surround_check() -> void:
	var band := Warband.new()
	band.name = "TestSurround"
	band.roster = load("res://resources/data/orc_warband.tres")
	band.size = 5
	band.replicated = false
	band.position = player.global_position + Vector3(9, 0, 0)
	main.get_node("World").add_child(band)
	band.start()
	for enemy in band.members():
		enemy.max_health = 1e5
		enemy.health = 1e5
	await _wait(0.3)
	band.alert(player)
	await _wait(6.0)
	var sum := Vector2.ZERO
	var close := 0
	for enemy in band.members():
		if enemy.movement is KiteMovement or enemy.flat_distance_to(player) > 3.0:
			continue
		var angle := atan2(enemy.global_position.z - player.global_position.z, enemy.global_position.x - player.global_position.x)
		sum += Vector2(cos(angle), sin(angle))
		close += 1
	var bunched := sum.length() / maxf(close, 1.0)  # 1 = all on one side, 0 = all around
	_check(close >= 3 and bunched < 0.6, "a band surrounds its foe (%d around, bunching %.2f)" % [close, bunched])
	for enemy in band.members():
		enemy.routed = true
		enemy.die()


# --- Bosses ---------------------------------------------------------------------------------

func _boss_checks() -> void:
	for boss_scene in ["vampire_lord", "orc_warlord"]:
		var band := Warband.new()
		band.name = "TestBand_%s" % boss_scene
		band.roster = load("res://resources/data/%s_warband.tres" % ("undead" if boss_scene == "vampire_lord" else "orc"))
		band.leader_scene = load(ENEMIES + boss_scene + ".tscn")
		band.size = 6
		band.replicated = false
		band.position = player.global_position + Vector3(14, 0, 0)
		main.get_node("World").add_child(band)
		band.start()
		await _wait(0.5)
		var boss := band.leader
		_check(boss != null and boss.is_in_group(&"bosses") and not boss.is_in_group(&"tracked"), "%s leads its band (hidden from the minimap)" % boss_scene)
		band.alert(player)
		await _wait(3.0)
		var hud := main.get_node("HUD") as Hud
		_check(hud._boss_panel.visible and hud._boss_name.text == boss.get_meta(&"marker_label"), "boss bar shows %s" % hud._boss_name.text)
		var crew := band.members()
		boss.take_damage(1e7, player)
		await _wait(0.2)
		var standing := crew.filter(func(e: Enemy) -> bool: return is_instance_valid(e) and not e.is_dead).size()
		_check(standing == 0 and (not is_instance_valid(band) or band.is_dead),
				"%s falls: its band (%d) is routed" % [boss_scene, crew.size() - 1])
		await _wait(2.5)
