extends Node
## Malakor, the Six-Armed Sovereign (offline Conquest): the King of the Demon's Lair (the garrison's boss, 4.8 m),
## his six-armed model and clips, his four phases (actions / movement / life steal switched by health), the red-X
## arrow rain and dark meteors hurting the hero, the Blood Totems at 66% that heal him, the phase-4 life siphon,
## and the risen champions (Sir Eldor, Vaira, Valendor, Mother Tyressa) leading the lieutenant armies; slaying him
## wins the match for the faction with the most damage to him, the killing blow counting extra.
##   "$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/malakor_test.gd

var t := 0.0
var pt := 0.0
var phase := 0
var failures := 0
var main: Node
var mode: ConquestMode
var hero: Player
var king: Enemy
var traits: MalakorTrait
var before := 0.0


func _ready() -> void:
	Net.open_offline_lobby()
	Net.settings.mode = Net.Mode.CONQUEST
	Net.settings.seed = 99
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
	if hero and not phase in [4, 51, 6]:
		hero.health = hero.max_health  # the hero stands it all (phases 4, 51, 6 read the damage)
	match phase:
		0:
			main = get_tree().current_scene
			if main == null or main.name != "Main" or main.get("local_player") == null or pt < 1.0:
				return
			mode = main.game_mode as ConquestMode
			hero = main.local_player
			hero.max_health = 100000.0
			hero.health = hero.max_health
			_check_champions()
			# Near the Lair: its garrison rises, led by Malakor.
			var lair := mode.throne()
			hero.global_position = lair.position + Vector3(0.0, 0.0, lair.radius() + 30.0)
			_next(1)
		1:
			if pt < 2.0:
				return
			for node in get_tree().get_nodes_in_group(&"bosses"):
				if (node as Node).scene_file_path.ends_with("malakor.tscn"):
					king = node
			_check(king != null, "Malakor rules the Demon's Lair")
			if king == null:
				_done()
				return
			_check(is_equal_approx(king.scale.x, TerritoryNode.BOSS_SIZE), "and stands 1.6x tall (%.2f)" % king.scale.x)
			var torso := king.model.get_node("Body/Torso")
			var arms := torso.get_children().filter(func(n: Node) -> bool: return n.name.begins_with("Arm"))
			_check(arms.size() == 6, "six arms (%d)" % arms.size())
			for item in ["ArmUR/Elbow/Hand/Sword", "ArmUL/Elbow/Hand/Cleaver", "ArmML/Elbow/Hand/Bow", "ArmMR/Elbow/Hand/Arrow",
					"ArmLL/Elbow/Hand/Grimoire", "ArmLR/Elbow/Hand/Chalice"]:
				_check(torso.has_node(item), "holding " + item.get_file())
			for clip in ["idle", "walk", "sprint", "attack-melee-right", "attack-melee-left", "holding-both-shoot", "cast", "die"]:
				_check(king.anim.has_animation(clip), "clip " + clip)
			traits = king.get_node("Phases") as MalakorTrait
			_check(traits.phase == 0 and not (king.get_node("ArrowRain") as EnemyAction).enabled
					and (king.get_node("Charge") as EnemyAction).enabled, "phase 1: the sword pair (charge on, rain off)")
			# Away from his garrison, in the open (outside any wall: else he goes to batter its gate).
			var home := mode.territories[hero.team_id].position
			var open := home + (mode.throne().position - home).normalized() * 40.0
			hero.global_position = open
			king.global_position = open + Vector3(0.0, 0.0, 8.0)
			king.home = king.global_position  # no leash back to the Lair
			king.provoke(hero, true)
			_next(2)
		2:
			if pt < 0.5:
				return
			_set_share(0.62)
			_next(3)
		3:
			if pt < 0.3 or (_totems() == 0 and pt < 8.0):
				return
			_check(traits.phase == 1 and (king.get_node("ArrowRain") as EnemyAction).enabled
					and not (king.get_node("Charge") as EnemyAction).enabled and king.movement == king.get_node("Kite"),
					"phase 2: the bow pair, keeping away")
			_check(_totems() >= 1, "Blood Totems rise at 66%% (%d)" % _totems())
			before = hero.health
			hero.max_health = 100000.0
			(king.get_node("ArrowRain") as BarrageAbility).start(hero)
			_next(4)
		4:
			if pt < 4.0:
				return
			_check(hero.health < hero.max_health, "the red-X arrow rain hits the hero (%.0f)" % (hero.max_health - hero.health))
			_set_share(0.45)
			_next(5)
		5:
			if pt < 0.3:
				return
			_check(traits.phase == 2 and (king.get_node("Meteors") as EnemyAction).enabled and king.movement == king.get_node("Chase"),
					"phase 3: the grimoire pair")
			(king.get_node("Meteors") as BarrageAbility).start(hero)
			_next(51)
		51:
			if pt < 2.5:
				return
			_check(hero.health < hero.max_health, "a dark meteor hits the hero (%.0f)" % (hero.max_health - hero.health))
			hero.health = hero.max_health
			_set_share(0.2)
			hero.global_position = king.global_position + Vector3(2.5, 0.0, 0.0)
			_next(6)
		6:
			if pt < 0.3:
				return
			if pt < 0.35:
				_check(traits.phase == 3 and (king.get_node("LifeSteal") as LifeStealTrait).share == MalakorTrait.LIFE_STEAL_ENRAGED
						and SWITCHED_ALL(), "phase 4: everything, life steal 200%")
				before = king.health
				hero.health = hero.max_health
			if pt < 2.5:
				return
			_check(hero.health < hero.max_health, "the life siphon drains the hero (%.0f)" % (hero.max_health - hero.health))
			_check(king.health > before or king.is_dead, "and feeds Malakor (%.0f -> %.0f)" % [before, king.health])
			var totem := _a_totem()
			if totem:
				var heal := totem.component(HealAuraTrait) as HealAuraTrait
				var hp := king.health
				heal.server_tick(5.0)
				_check(king.health > hp, "a Blood Totem heals him (%.0f -> %.0f)" % [hp, king.health])
			_slay_king()


## Slaying him wins Conquest: a rival faction's soldier does 55% of his health, our hero 45% and the killing blow
## (worth KING_BLOW_SHARE more): our faction wins.
func _slay_king() -> void:
	var title := [""]
	mode.match_over.connect(func(t: String, _s: String) -> void: title[0] = t)
	var rival_team := (hero.team_id + 1) % ConquestMode.FACTIONS
	var rival := NetSpawn.unit(&"ally", king.global_position + Vector3(2.0, 0.0, 0.0),
			{"team": rival_team, "owner": 0, "weapon": "sword"}) as Ally
	traits.damage_by_team.clear()
	king.health = king.max_health
	king.take_damage(king.max_health * 0.55, rival)
	king.take_damage(king.max_health * 0.45, hero)
	if not king.is_dead:
		king.take_damage(king.max_health, hero)  # (life steal healed a bit: finish him)
	_check(king.is_dead and traits.last_team == hero.team_id, "our hero strikes the killing blow (%s, max %.0f)" % [traits.damage_by_team, king.max_health])
	_check(mode.is_over and title[0] == Net.localize("{team:%d} wins!" % hero.team_id),
			"slaying Malakor wins the match for the killer's faction, with less damage but the last blow (%s)" % title[0])
	_done()


func SWITCHED_ALL() -> bool:
	for action_name in MalakorTrait.SWITCHED:
		if not (king.get_node(action_name) as EnemyAction).enabled:
			return false
	return true


func _set_share(share: float) -> void:
	king.health = king.max_health * share


func _totems() -> int:
	return get_tree().get_nodes_in_group(&"active_enemies").filter(func(n: Node) -> bool:
		return n.scene_file_path.ends_with("blood_totem.tscn") and not GameConfig.is_gone(n)).size()


func _a_totem() -> Enemy:
	for node in get_tree().get_nodes_in_group(&"active_enemies"):
		if node.scene_file_path.ends_with("blood_totem.tscn") and not GameConfig.is_gone(node):
			return node
	return null


func _check_champions() -> void:
	var names := []
	for band in mode.demons.lieutenants:
		names.append(band.leader.enemy_name if band.leader else "?")
	_check(names == ["Sir Eldor", "Vaira", "Valendor", "Mother Tyressa"], "the risen champions lead the lieutenant armies: %s" % [names])
	var vaira := mode.demons.lieutenants[1].leader
	var valendor := mode.demons.lieutenants[2].leader
	var tyressa := mode.demons.lieutenants[3].leader
	_check(vaira.has_node("ArrowRain") and valendor.has_node("Blink") and tyressa.has_node("LifeSteal") and tyressa.has_node("Heal"),
			"Vaira's arrow rain, Valendor's blink, Tyressa's blood drain and healing")
