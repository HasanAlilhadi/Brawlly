extends Node
## Conquest zones (offline): the outer zone where the factions start is calm — only a few small plain warbands
## (filler only, 2-3 members, ConquestMode.ZONE_BAND_SPACING apart), bigger ones toward the middle; world events
## (meteors, storm, Blood Moon, goblin, Warlord, supply drops) only reach zones 0..EVENT_ZONE: due with every hero
## outside they wait, the Blood Moon drives only enemies there, and there are no invasion waves.
## ConquestDemons: one monster back every ZONE_RESPAWN s (2 min outside; wiped-out bands come back), full bands
## campaign on held places (a Village falls to them, a Citadel's gate is hammered but it never falls), monsters
## whose target is walled in go to the gate and batter it, and the King's four lieutenants (sword, bow, magic,
## healer) lead strong armies in zone 1, the healer heals his, and they rally to the Lair when it is attacked.
##   "$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/conquest_zones_test.gd

var t := 0.0
var pt := 0.0
var phase := 0
var failures := 0
var main: Node
var mode: ConquestMode
var events: WorldEvents
var hero: Player
var demons: ConquestDemons
var village: TerritoryNode
var citadel: TerritoryNode
var rival: TerritoryNode
var grunt: Enemy
var gate_before := 0.0


func _ready() -> void:
	Net.open_offline_lobby()
	Net.settings.mode = Net.Mode.CONQUEST
	Net.settings.seed = 4242
	Net.settings.events = WorldEvents.all_ids()
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


func _process(delta: float) -> void:
	t += delta
	pt += delta
	if t > 150.0:
		_check(false, "finished in time (phase %d)" % phase)
		_done()
		return
	match phase:
		0:
			main = get_tree().current_scene
			if main == null or main.name != "Main" or main.get("local_player") == null or pt < 1.0:
				return
			mode = main.game_mode as ConquestMode
			events = main.world_events
			hero = main.local_player
			_check_bands()
			_check(not events.is_on("waves"), "no invasion waves in Conquest: %s" % [events.enabled_events])
			_check(ConquestMode.zone_of(hero.global_position) == ConquestMode.ZONES - 1, "the hero starts in the outer zone")
			_check(events._random_player() == null, "no hero where events reach")
			# Every event comes due: none starts, they wait.
			events._meteor_timer = 0.0
			events._storm_timer = 0.0
			events._goblin_timer = 0.0
			events._warlord_timer = 0.0
			events._supply_timer = 0.0
			_next(1)
		1:
			if pt < 0.3:
				return
			_check(events.meteors_left <= 0.0 and events.storm_left <= 0.0, "no meteors / storm in the outer zone")
			_check(not is_instance_valid(events.goblin) and not is_instance_valid(events.warlord), "no goblin / Warlord")
			_check(events.supply_drops == 0, "no supply drop")
			_check(events._meteor_timer > 5.0, "the meteors wait (%.1f s)" % events._meteor_timer)
			# The Blood Moon: only enemies in the inner zones rage.
			GameConfig.blood_moon = true
			var half := GameConfig.world_half
			_check(not GameConfig.raging_at(Vector3(half * 0.9, 0, half * 0.9)), "the Blood Moon spares the outer zone")
			_check(GameConfig.raging_at(Vector3(half * 0.15, 0, 0)), "and drives enemies in zone 1")
			GameConfig.blood_moon = false
			# The hero walks into zone 2: events find them.
			hero.global_position = Vector3(GameConfig.world_half * 0.3, 0.0, 0.0)
			_check(ConquestMode.zone_of(hero.global_position) == 2, "the hero is in zone 2")
			_check(events._random_player() == hero, "events reach the hero there")
			events._meteor_timer = 0.0
			_next(2)
		2:
			if pt < 0.3:
				return
			_check(events.meteors_left > 0.0, "a meteor shower starts in zone 2")
			_check(events.weather.area.is_valid() and not events.weather.area.call(Vector3(GameConfig.world_half * 0.9, 0, 0)),
					"the storm / Blood Moon sky shows only inside")
			events.meteors_left = 0.0
			demons = mode.demons
			citadel = mode.territories[hero.team_id]
			hero.global_position = citadel.position
			_check_lieutenants()
			_check_respawn()
			_start_village_campaign()
			_next(3)
		3:
			if village.state != TerritoryNode.State.INFESTED:
				if pt > 40.0:
					_check(false, "the demon host takes the village (%s, %.0f%%)" % [village.state, village.progress * 100.0])
					_start_citadel_campaign()
				return
			_check(true, "a full band's campaign takes a held village")
			_next(31)
		31:
			if pt < 1.5:
				return
			_check(not demons.campaigns.any(func(c: Dictionary) -> bool: return c.place == village), "and the campaign is over")
			_start_citadel_campaign()
		4:
			if pt < 4.0:
				return
			_check(rival.gate.health < gate_before, "a campaign hammers a Citadel's gate (%.0f -> %.0f)" % [gate_before, rival.gate.health])
			rival.gate.batter(rival.gate.max_health)
			_next(5)
		5:
			if pt < 8.0:
				return
			_check(rival.state == TerritoryNode.State.OWNED, "but a Citadel never falls to demons")
			_start_breach()
		6:
			if pt < 1.5:
				return
			_check(grunt.breach_point != Vector3.INF, "a grunt whose target is walled in heads for the gate")
			_next(7)
		7:
			if citadel.gate.health < gate_before:
				_check(true, "and batters the gate (%.0f -> %.0f)" % [gate_before, citadel.gate.health])
				grunt.take_damage(99999.0)
				_start_rally()
				return
			if pt > 20.0:
				_check(false, "the grunt batters the gate (%.1f m from it)" % Ally._flat(grunt.global_position - citadel.gate.outside_point(1.0)).length())
				_start_rally()
		8:
			if pt < 2.5:
				return
			_check(demons.rallying, "an attack on the Lair rallies the demons")
			var point := demons._rally_point()
			_check(demons.living_lieutenants().all(func(b: Warband) -> bool: return b.goal == point),
					"the lieutenants march to the Lair's gate")
			hero.global_position = citadel.position
			demons._calm = ConquestDemons.RALLY_CALM - 0.5
			_next(9)
		9:
			if pt < 2.5:
				return
			_check(not demons.rallying, "the rally ends once the attackers are gone")
			var home_bound := demons.living_lieutenants().all(func(b: Warband) -> bool:
				return b.goal == b.get_meta(&"conquest_home") or b.goal == Vector3.INF)
			_check(home_bound, "and the lieutenants go home")
			_done()


func _check_lieutenants() -> void:
	var bands := demons.lieutenants
	_check(bands.size() == 4, "the King has four lieutenants")
	var kinds := []
	for band in bands:
		kinds.append(String(band.get_meta(&"lieutenant")))
		_check(ConquestMode.zone_of(band.global_position) == 1 and band.has_boss and band.size == 1 + ConquestDemons.LIEUTENANT_ARMY,
				"%s leads an army of %d in zone 1" % [kinds.back(), band.size - 1])
	_check(kinds == ["lieutenant_blade", "lieutenant_marksman", "lieutenant_warlock", "lieutenant_mender"],
			"sword, bow, magic and healer: %s" % [kinds])
	var blade := bands[0].leader
	_check(blade != null and blade.scene_file_path.ends_with("lieutenant_blade.tscn")
			and is_equal_approx(blade.max_health, 900.0 * ConquestDemons.LIEUTENANT_POWER),
			"the Blademaster leads, strong (%.0f hp)" % (blade.max_health if blade else 0.0))
	var mender := bands[3].leader
	var hurt: Enemy = null
	for enemy in bands[3].members():
		if enemy != mender:
			hurt = enemy
			break
	hurt.health = hurt.max_health * 0.5
	var before := hurt.health
	(mender.component(HealAuraTrait) as HealAuraTrait).server_tick(2.5)
	_check(hurt.health > before, "the Mender heals his army (%.0f -> %.0f)" % [before, hurt.health])


func _check_respawn() -> void:
	var outer: Warband = null
	for band in demons._bands:
		if int(band.get_meta(&"conquest_zone")) == 6 and not band.has_meta(&"lieutenant"):
			outer = band
			break
	_check(outer.respawn_delay == 120.0 and outer.steady_respawn and outer.revives, "outer bands: one back every 2 minutes")
	for enemy in outer.members():
		enemy.routed = true  # past a skeleton's getting back up
		enemy.die()
	_check(not outer.is_dead and outer.members().is_empty(), "a wiped-out band is not gone for good")
	outer._respawn_steady(60.0)
	_check(outer.members().is_empty(), "nothing back after 1 minute")
	outer._respawn_steady(61.0)
	_check(outer.members().size() == 1, "one monster back after 2 minutes")
	var inner := demons.lieutenants[0]
	_check(inner.respawn_delay == ConquestDemons.ZONE_RESPAWN[1] and inner.respawn_delay < 120.0,
			"faster toward the middle (%.0f s)" % inner.respawn_delay)


## The nearest full roaming band to `at` (but `except`), moved next to it (members too).
func _band_at(at: Vector3, except: Warband = null) -> Warband:
	var best: Warband = null
	for band in demons._bands:
		if band == except or band.has_meta(&"lieutenant") or not band.is_full():
			continue
		if best == null or band.global_position.distance_to(at) < best.global_position.distance_to(at):
			best = band
	best.global_position = at
	for enemy in best.members():
		enemy.global_position = at + Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5))
	return best


func _start_village_campaign() -> void:
	for place in mode.territories:
		if place.kind == TerritoryNode.Kind.VILLAGE and place.zone == 6 and (village == null or
				place.position.distance_to(citadel.position) < village.position.distance_to(citadel.position)):
			village = place
	village._captured_by(hero.team_id)
	var band := _band_at(village.position + Vector3(8.0, 0.0, 0.0))
	demons.start_campaign(band, village)
	_check(band.goal != Vector3.INF and demons.campaigns.any(func(c: Dictionary) -> bool: return c.band == band),
			"a full band goes on campaign")


func _start_citadel_campaign() -> void:
	rival = mode.territories[(hero.team_id + 1) % ConquestMode.FACTIONS]
	gate_before = rival.gate.health
	var band := _band_at(rival.gate.outside_point(3.0))
	demons.start_campaign(band, rival)
	_next(4)


## The hero inside their own Citadel by the wall, a grunt outside it 60° from the gate.
func _start_breach() -> void:
	var gate_dir := citadel.gate.global_position - citadel.position
	gate_dir.y = 0.0
	var side := gate_dir.normalized().rotated(Vector3.UP, deg_to_rad(60.0))
	hero.global_position = citadel.position + side * (citadel.radius() - 2.0)
	gate_before = citadel.gate.health
	grunt = NetSpawn.unit(&"enemy", citadel.position + side * (citadel.radius() + 3.0),
			{"scene": "res://scenes/characters/enemies/orc_grunt.tscn", "strength": 1.0, "coins": 1.0}) as Enemy
	grunt.add_to_group(&"active_enemies")
	grunt.provoke(hero, true)
	_next(6)


func _start_rally() -> void:
	var lair := mode.throne()
	var toward := (citadel.position - lair.position).normalized()
	hero.global_position = lair.position + toward * (lair.radius() + 8.0)
	_next(8)


func _check_bands() -> void:
	var outer: Array[Warband] = []
	var inner_sizes := 0
	var inner := 0
	for node in get_tree().get_nodes_in_group(&"warbands"):
		var band := node as Warband
		if band == null or not band.replicated or band.has_meta(&"lieutenant"):
			continue
		var zone := ConquestMode.zone_of(band.global_position)
		if zone == ConquestMode.ZONES - 1:
			outer.append(band)
		elif zone <= 2:
			inner_sizes += band.size
			inner += 1
	_check(not outer.is_empty(), "a few bands roam the outer zone (%d)" % outer.size())
	var plain := outer.all(func(b: Warband) -> bool: return b.plain and b.size <= 3 and not b.has_boss)
	_check(plain, "outer bands are small and plain: %s" % [outer.map(func(b: Warband) -> int: return b.size)])
	var closest := INF
	for i in outer.size():
		for j in range(i + 1, outer.size()):
			closest = minf(closest, outer[i].global_position.distance_to(outer[j].global_position))
	_check(closest >= ConquestMode.ZONE_BAND_SPACING[ConquestMode.ZONES - 1] - 0.1, "and far apart (closest %.0f m)" % closest)
	var average := float(inner_sizes) / maxf(inner, 1.0)
	_check(inner > 0 and average >= 10.0, "bands near the middle are big (%d, %.1f on average)" % [inner, average])
