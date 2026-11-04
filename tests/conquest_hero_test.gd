extends Node
## Conquest heroes have no class (offline): the hero starts Unarmed (fists, weak), buys a weapon on the Hero tab
## (the hero is swapped at the same spot: coins, Vitality, health share and soldiers carry over), levels up from
## kills (+8% health and damage a level), and a new weapon starts its level and weapon upgrades over. The wizard's
## staff fires magic bolts, the healer's heals the hurt friend at the aim point (heals count toward levels).
## Then the left-column supplies panel: per-minute flows (comes in / goes out by reason) and its hover card.
##   "$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/conquest_hero_test.gd

var t := 0.0
var pt := 0.0
var phase := 0
var failures := 0
var main: Node
var mode: ConquestMode
var hero: Player
var old_hero: Player
var soldier: Ally
var coins_before := 0


func _ready() -> void:
	Net.open_offline_lobby()
	Net.settings.mode = Net.Mode.CONQUEST
	Net.settings.seed = 777
	Net.settings.events = []
	TerritoryNode.unguarded_falls = false
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


func _def(id: StringName) -> UpgradeDef:
	for def in Player.CATALOG.upgrades:
		if def.id == id:
			return def
	return null


func _done() -> void:
	_log("done: %d failure(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)


## Buys `id` and waits for the swapped hero (main.rearm_player) on the next phase.
func _buy_weapon(id: StringName) -> void:
	old_hero = hero
	coins_before = hero.coins
	_check(hero.buy_upgrade(_def(id)), "bought %s" % id)


## The new hero once the swap is done (null while it is under way).
func _swapped() -> Player:
	var now: Player = main.local_player
	if now == null or now == old_hero or not is_instance_valid(now):
		return null
	return now


func _process(delta: float) -> void:
	t += delta
	pt += delta
	if t > 120.0:
		_check(false, "finished in time (phase %d)" % phase)
		_done()
		return
	match phase:
		0:
			main = get_tree().current_scene
			if main == null or main.name != "Main" or main.get("local_player") == null or pt < 2.0:
				return
			mode = main.game_mode as ConquestMode
			hero = main.local_player
			_check(hero.classless and hero.class_def.id == Player.START_CLASS and hero.weapons == PackedStringArray(["fists"]),
					"a Conquest hero starts Unarmed (fists)")
			_check(is_equal_approx(hero.melee_damage, 36.0 * 0.35), "fists hit softly (%.1f)" % hero.melee_damage)
			_check(hero.sheet_items(&"weapon").size() == 4, "the Hero tab sells 4 weapons")
			_check(not hero.can_buy(_def(&"arm_sword")), "no coins, no sword")
			var sheet: UpgradeSheet = main.hud.upgrade_sheet
			_check(sheet._hero_tab.text == "Unarmed", "the Hero tab is named for the hero: " + sheet._hero_tab.text)
			# Levels from kills.
			for i in 3:
				hero.credit_kill(hero)
			_check(hero.hero_level == 1 and hero.max_health == 150.0 * 1.08, "3 kills: level 1, +8%% health (%.0f)" % hero.max_health)
			_check(is_equal_approx(hero.melee_damage, 36.0 * 0.35 * 1.08), "and +8% damage")
			_check("Lv 1" in hero._name_label.text, "its name label shows the level: " + hero._name_label.text)
			var pig := Node3D.new()
			pig.add_to_group(&"animals")
			hero.credit_kill(pig)
			pig.free()
			_check(hero.hero_kills == 3, "animals don't count")
			# A soldier and Vitality to carry over.
			soldier = NetSpawn.unit(&"ally", hero.global_position + Vector3(2, 0, 0), {"team": hero.team_id,
					"owner": hero.peer_id, "weapon": "sword"}) as Ally
			hero.coins = 500
			_check(hero.buy_upgrade(_def(&"vitality")), "Vitality bought")
			hero.health = hero.max_health * 0.5
			hero.command_army(Player.Order.HOLD, hero.global_position + Vector3(4, 0, 0))
			_buy_weapon(&"arm_sword")
			_next()
		1:
			var now := _swapped()
			if now == null:
				if pt > 3.0:
					_check(false, "the hero is swapped for a swordsman")
					_done()
				return
			_check(not is_instance_valid(old_hero) or old_hero.is_queued_for_deletion(), "the old hero is gone")
			hero = now
			_check(hero.class_def.id == &"swordsman" and hero.weapons == PackedStringArray(["sword"]), "now a swordsman")
			_check(hero.coins == coins_before - 30, "the sword cost 30 coins (%d left)" % hero.coins)
			_check(hero.upgrade_level(&"vitality") == 1 and is_equal_approx(hero.max_health, 180.0),
					"Vitality carried over, the level did not (max %.0f)" % hero.max_health)
			_check(hero.hero_level == 0 and hero.hero_kills == 0, "level and kills start over")
			_check(absf(hero.health / hero.max_health - 0.5) < 0.02, "the health share carried over (%.0f)" % hero.health)
			_check(hero.army_order == Player.Order.HOLD, "the army order carried over")
			_check(is_equal_approx(hero.melee_damage, 36.0), "the sword hits full (%.1f)" % hero.melee_damage)
			_check(main.hud.upgrade_sheet._hero_tab.text == "Swordsman", "the Hero tab now sells sword upgrades")
			_check(not hero.can_buy(_def(&"arm_sword")), "no second sword")
			_check(hero.buy_upgrade(_def(&"sword_damage")), "a sword upgrade bought")
			_next()
		2:
			if pt < 0.5:
				return
			_check(soldier.leader == hero, "the soldier follows the new hero")
			_check(hero.army_size() >= 1 and hero.soldiers().has(soldier), "it is still in the army")
			for i in 8:
				hero.credit_kill(hero)
			_check(hero.hero_level == 2, "8 kills: level 2")
			_buy_weapon(&"arm_wizard")
			_next()
		3:
			var now := _swapped()
			if now == null:
				return
			hero = now
			_check(hero.class_def.id == &"wizard" and hero.weapons == PackedStringArray(["staff"]), "now a wizard (staff)")
			_check(hero.hero_level == 0 and hero.upgrade_level(&"sword_damage") == 0 and hero.upgrade_level(&"vitality") == 1,
					"level and sword upgrades gone, Vitality kept")
			_check(hero.holds_ranged() and is_equal_approx(hero.shoot_cooldown, 0.8), "the staff casts every 0.8 s")
			hero.shoot(Vector3(0, 0, 5))
			_next()
		4:
			var bolt_found := false
			for node in main.world.get_node("Items").get_children():
				if String(node.name).begins_with("magic_bolt"):
					bolt_found = true
			_check(bolt_found, "the staff fires a magic bolt")
			_buy_weapon(&"arm_healer")
			phase = 40
			pt = 0.0
		40:
			var now := _swapped()
			if now == null:
				return
			hero = now
			_check(hero.class_def.id == &"healer" and hero.weapons == PackedStringArray(["heal_staff"]), "now a healer")
			soldier.health = soldier.max_health - 40.0
			var before := soldier.health
			for i in 3:
				hero._shoot_timer = 0.0
				hero.shoot((soldier.global_position - hero.global_position) * 1.0)
			_check(soldier.health > before, "the healer's staff heals the hurt soldier (%.0f -> %.0f)" % [before, soldier.health])
			_check(hero.hero_kills == 1, "3 heals count as a kill (%d)" % hero.hero_kills)
			phase = 5
			pt = 0.0
		5:
			# The supplies panel: a minute of flows, by reason.
			var logistics := mode.logistics
			var home := mode.territories[hero.team_id]
			home.train_kind = 1
			for i in 3:
				logistics.tick()
			var stock := logistics.stock_of(hero.team_id)
			var flow: Dictionary = stock.get(&"flow", {})
			_check(int(flow.get(&"food", {}).get("in", {}).get("Citadel", 0)) > 0, "food comes in from the Citadel: %s" % [flow.get(&"food")])
			_check(int(flow.get(&"equipment", {}).get("out", {}).get("Arming people in barracks", 0)) > 0,
					"arming people in the barracks spends weapons: %s" % [flow.get(&"equipment")])
			_check(int(flow.get(&"gold", {}).get("in", {}).get("Citadel", 0)) > 0, "gold comes in")
			var panel: ConquestPanel = main.conquest_panel
			_check(panel != null and panel.get_parent() == main.hud.left_column, "the supplies panel sits in the HUD's left column")
			panel._refresh()
			var food_row: Dictionary = panel._rows[&"food"]
			_check(("Food  %d" % stock[&"food"]) == food_row.total.text and "a minute" in food_row.flow.text,
					"its food row: %s / %s" % [food_row.total.text, food_row.flow.text])
			panel._hover(&"equipment")
			var lines := PackedStringArray()
			for child in panel._detail_lines.get_children():
				lines.append((child as Label).text)
			_check(panel._detail.visible and "   Arming people in barracks" in lines,
					"hovering Weapons shows where they go: %s" % ", ".join(lines))
			panel._hover(&"")
			_check(not panel._detail.visible, "and hides again")
			_check(not ("Food" in mode.score_text()), "the top line no longer carries the supplies")
			_check("Level 0" in panel._hero_title.text and "Healer" in panel._hero_title.text, "the panel shows the hero: " + panel._hero_title.text)
			_done()
