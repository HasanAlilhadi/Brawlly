extends Node
## Conquest gates (offline): a held gate opens for its own soldier even with demons right at it (the garrison must
## get out to fight), and attackers don't press against the walls — soldiers ordered into a rival's walled
## Citadel walk to its gate and hit it until it breaks, then march in.
##   "$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/conquest_gates_test.gd

var t := 0.0
var pt := 0.0
var phase := 0
var failures := 0
var main: Node
var mode: ConquestMode
var hero: Player
var home: TerritoryNode
var rival: TerritoryNode
var soldier: Ally
var grunts: Array[Enemy] = []
var army: Array[Ally] = []
var gate_before := 0.0


func _ready() -> void:
	Net.open_offline_lobby()
	Net.settings.mode = Net.Mode.CONQUEST
	Net.settings.seed = 515
	Net.settings.events = []
	TerritoryNode.unguarded_falls = false
	ConquestDemons.campaigns_on = false
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
	if t > 90.0:
		_check(false, "finished in time (phase %d)" % phase)
		_done()
		return
	if hero:
		hero.health = hero.max_health
	match phase:
		0:
			main = get_tree().current_scene
			if main == null or main.name != "Main" or main.get("local_player") == null or pt < 1.0:
				return
			mode = main.game_mode as ConquestMode
			hero = main.local_player
			home = mode.territories[hero.team_id]
			rival = mode.territories[(hero.team_id + 1) % ConquestMode.FACTIONS]
			_check(home.gate != null and rival.gate != null and rival.owner_team != hero.team_id, "two walled Citadels")
			# Our soldier inside, just behind our gate; three demons outside it, after him.
			var gate := home.gate
			var inward := -gate.global_basis.z.normalized()
			hero.global_position = home.position + inward * 2.0
			soldier = NetSpawn.unit(&"ally", gate.global_position + inward * 3.0,
					{"owner": hero.peer_id, "team": hero.team_id, "weapon": "sword"}) as Ally
			for i in 3:
				var grunt := NetSpawn.unit(&"enemy", gate.outside_point(1.5) + gate.global_basis.x * (i - 1) * 1.2,
						{"scene": "res://scenes/characters/enemies/orc_grunt.tscn", "strength": 1.0, "coins": 1.0}) as Enemy
				grunt.add_to_group(&"active_enemies")
				grunt.max_health = 1e5
				grunt.health = 1e5
				grunts.append(grunt)
			_next(1)
		1:
			if pt < 0.5:
				return
			for grunt in grunts:
				grunt.provoke(soldier, true)
			# Walk the soldier up to the gate from inside.
			soldier.global_position = home.gate.global_position - home.gate.global_basis.z.normalized() * 1.6
			_next(2)
		2:
			# Held at the gate (it would run to its hero): the gate must open for it with the demons right there.
			soldier.global_position = home.gate.global_position - home.gate.global_basis.z.normalized() * 1.6
			if pt < 0.8:
				return
			_check(not home.gate.shut, "our gate opens for our soldier with demons right at it")
			var layer := home.gate.collision_layer
			_check(layer != 0 and (soldier.collision_mask & layer) == 0 and grunts.all(func(g: Enemy) -> bool:
					return (g.collision_mask & layer) != 0), "open, it is still solid for the demons (only our side walks through)")
			_check((hero.melee_mask & layer) != 0, "and can still be hit")
			var inside := grunts.filter(func(g: Enemy) -> bool:
					return Ally._flat(g.global_position - home.position).length() < home.radius() - 0.5).size()
			_check(inside == 0, "no demon got in through the open gate (%d)" % inside)
			for grunt in grunts:
				grunt.routed = true
				grunt.die()
			soldier.global_position = home.position
			_start_storm()
			_next(3)
		3:
			var breaching := army.filter(func(a: Ally) -> bool: return not a.is_dead and a.breach_point != Vector3.INF).size()
			if rival.gate.health < gate_before and breaching > 0 or pt > 30.0:
				_check(breaching >= 3, "soldiers ordered into a rival Citadel head for its gate (%d of %d)" % [breaching, army.size()])
				_check(rival.gate.health < gate_before, "and hit it (%.0f -> %.0f)" % [gate_before, rival.gate.health])
				var gate_spot := rival.gate.outside_point(1.0)
				var far := army.filter(func(a: Ally) -> bool:
						return not a.is_dead and Ally._flat(a.global_position - gate_spot).length() > 7.0).size()
				_check(far == 0, "none of them presses against the wall away from the gate (%d off)" % far)
				rival.gate.health = 1.0
				rival.gate.take_damage(1000.0, army[0])  # it breaks
				_next(4)
		4:
			if pt < 2.5:
				return
			var inside := army.filter(func(a: Ally) -> bool:
					return not a.is_dead and a.breach_point == Vector3.INF).size()
			_check(rival.gate.is_broken() and inside == army.size(), "the gate down, they march on (%d of %d, gate %.0f, state %d)" % [inside, army.size(), rival.gate.health, rival.state])
			_done()


## Six of our swordsmen and the hero in front of the rival's gate; the hero orders a march into the Citadel.
func _start_storm() -> void:
	var gate := rival.gate
	var front := gate.outside_point(12.0)
	hero.global_position = front
	for i in 6:
		var at := front + gate.global_basis.x * (i - 2.5) * 1.3
		var ally := NetSpawn.unit(&"ally", at, {"owner": hero.peer_id, "team": hero.team_id, "weapon": "sword"}) as Ally
		army.append(ally)
	gate_before = gate.health
	hero.command_army(Player.Order.MARCH, rival.position)
