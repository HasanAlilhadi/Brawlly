extends Node
## Class upgrades sheet (T) and every upgrade's effect, for the class passed with --class:
## - all: T opens the sheet with only this class's cards; buying from a card (anywhere, no stall) spends coins;
##   Increase Damage / Fire Rate change the stats.
## - swordsman: no shield until bought; Knock Back shoves far and locks Wave; Wave sends a slash through two orcs;
##   Dash Attack moves ~4.5 m and hits each orc crossed once, then cools down.
## - spearman: stab only until Can Throw (then E switches to throwing); shield bought.
## - bowman: Fire Range lengthens aim and flight; Penetration hits 3 orcs in a line; Knife stabs up close (not as far
##   or as wide as the sword) and no arrows fly while stabbing.
## --shot=<png> saves the Army tab after its upgrades (needs a window: run off-screen, --position -4000,-4000).
##   "$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/class_upgrades_test.gd --class=bowman

## Dashes and shots go +Z from here (scenery collision is off, see `_clear_scenery`).
const LANE_START := Vector3(0, 0, -3)

var failures := 0
var shot := ""
var main: Node
var player: Player


func _check(ok: bool, message: String) -> void:
	printerr(("PASS " if ok else "FAIL ") + message)
	if not ok:
		failures += 1


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot = arg.substr(7)
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	while get_tree().current_scene == null or get_tree().current_scene.name != "Main" \
			or get_tree().get_nodes_in_group(&"players").is_empty():
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	main = get_tree().current_scene
	player = get_tree().get_nodes_in_group(&"players")[0]
	player.max_health = 100000.0
	player.health = 100000.0
	player.crit_chance = 0.0
	player.coins = 100000
	player.global_position = Vector3.ZERO
	_clear_units()
	_clear_scenery()
	await _sheet()
	match player.class_def.id:
		&"swordsman":
			await _swordsman()
		&"spearman":
			await _spearman()
		&"bowman":
			await _bowman()
	printerr("%s class upgrades (%s): %d failures" % ["PASS" if failures == 0 else "FAIL", player.class_def.id, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _clear_units() -> void:
	for node in get_tree().get_nodes_in_group(&"units"):
		if node != player:
			node.queue_free()


## Scenery (trees, town decor, buildings) stops shots and dashes; switch its collision off so the lanes only
## measure the upgrades.
func _clear_scenery() -> void:
	for node in main.find_children("*", "CollisionObject3D", true, false):
		var body := node as CollisionObject3D
		if not body is Unit and body.collision_layer & (GameConfig.LAYER_WORLD | GameConfig.LAYER_FENCE):
			body.collision_layer = 0


func _orc(at: Vector3) -> Enemy:
	var orc := NetSpawn.unit(&"enemy", at, {"scene": "res://scenes/characters/enemy.tscn", "strength": 1.0,
			"coins": 1.0}) as Enemy
	orc.add_to_group(&"active_enemies")
	orc.max_health = 5000.0
	orc.health = 5000.0
	orc.set_physics_process(false)
	return orc


## Press a card's buy button in the open sheet.
func _buy(id: StringName) -> bool:
	var button := main.find_child("Buy_%s" % id, true, false) as Button
	if button == null or button.disabled:
		return false
	button.pressed.emit()
	await get_tree().process_frame
	return true


func _def(id: StringName) -> UpgradeDef:
	for def in Player.CATALOG.upgrades:
		if def.id == id:
			return def
	return null


func _sheet() -> void:
	var hud: Hud = main.get_node("HUD")
	var press := InputEventAction.new()
	press.action = &"upgrades"
	press.pressed = true
	Input.parse_input_event(press)
	# It slides up from below the screen: sample its top edge while it opens.
	var tops: Array[float] = []
	for frame in 40:
		await get_tree().process_frame
		if hud.upgrade_sheet.visible and hud.upgrade_sheet.modulate.a > 0.0:
			tops.append(hud.upgrade_sheet.global_position.y)
	_check(hud.upgrade_sheet.is_open and hud.upgrade_sheet.visible, "T opens the upgrades sheet")
	_check(tops.size() > 5 and tops[0] > tops[-1] + 100.0 and tops[tops.size() / 2] < tops[0] and tops[tops.size() / 2] > tops[-1] - 1.0,
			"it slides up over several frames (%.0f -> %.0f px over %d frames)" % [tops[0] if tops else 0.0, tops[-1] if tops else 0.0, tops.size()])
	var cards := hud.upgrade_sheet.find_child("UpgradeCards", true, false).get_children()
	var expected := player.class_upgrades().size()
	_check(cards.size() == expected and expected >= 4, "%d cards, all for the %s" % [cards.size(), player.class_def.display_name])
	for card in cards:
		var def := _def(StringName(String(card.name).trim_prefix("Card_")))
		_check(def != null and def.classes.has(player.class_def.id), "%s belongs to this class" % card.name)
	var prefix := {&"swordsman": "sword", &"spearman": "spear", &"bowman": "bow"}[player.class_def.id] as String
	var coins := player.coins
	var damage_before := _damage()
	_check(await _buy(StringName(prefix + "_damage")), "bought Increase Damage away from any stall")
	_check(player.coins == coins - _def(StringName(prefix + "_damage")).cost_at(0), "it cost coins (%d -> %d)" % [coins, player.coins])
	_check(is_equal_approx(_damage(), damage_before * 1.2), "damage +20%% (%.1f -> %.1f)" % [damage_before, _damage()])
	var cooldown_before := _cooldown()
	_check(await _buy(StringName(prefix + "_rate")), "bought Fire Rate")
	_check(_cooldown() < cooldown_before * 0.9, "faster attacks (%.2f -> %.2f s)" % [cooldown_before, _cooldown()])
	hud.toggle_upgrades()
	await _wait(0.1)
	_check(hud.upgrade_sheet.visible, "closing slides it down (still on screen right after T)")
	await _wait(0.5)
	_check(not hud.upgrade_sheet.is_open and not hud.upgrade_sheet.visible, "T again closes it")
	hud.toggle_upgrades()
	await _wait(0.6)
	await _army(hud)


## Army tab: recruit away from any barracks (joins beside you after 10 s), Soldier Damage / Health max at 3 levels each.
func _army(hud: Hud) -> void:
	(hud.upgrade_sheet.find_child("ArmyTab", true, false) as Button).pressed.emit()
	(hud.upgrade_sheet.find_child("ArmyTab", true, false) as Button).button_pressed = true
	await _wait(0.2)
	_check((hud.upgrade_sheet.find_child("ArmyCards", true, false) as Control).visible
			and not (hud.upgrade_sheet.find_child("UpgradeCards", true, false) as Control).visible, "the Army tab shows the soldier cards")
	var coins := player.coins
	var before := player.followers().size()
	_check(await _buy(&"recruit"), "bought a soldier away from the barracks")
	_check(player.coins == coins - 50 and player.soldiers_training == 1, "50 coins, one soldier training")
	await _wait(1.0)
	var status := (hud.upgrade_sheet.find_child("RecruitStatus", true, false) as Label).text
	_check(status.begins_with("Next soldier in 9") or status.begins_with("Next soldier in 8"), "the card counts down (%s)" % status)
	await _wait(8.5)
	_check(player.followers().size() == before, "not before 10 s")
	await _wait(1.0)
	var joined := player.followers().filter(func(a: Node) -> bool: return not a.get("penned"))
	_check(joined.size() == before + 1, "after 10 s a soldier joins (%d following)" % joined.size())
	if not joined.is_empty():
		_check((joined[-1] as Node3D).global_position.distance_to(player.global_position) < 3.0, "it appears right beside you")
	var trained := joined[-1] as Ally if not joined.is_empty() else null
	var trained_health := trained.max_health if trained else 0.0
	var trained_damage := trained.melee_damage if trained else 0.0
	var damage := player.ally_damage
	for i in 3:
		_check(await _buy(&"soldier_damage"), "Soldier Damage level %d" % (i + 1))
	_check(is_equal_approx(player.ally_damage, damage + 0.75) and player.is_upgrade_maxed(_def(&"soldier_damage")),
			"soldier damage +75%% at most (x%.2f)" % player.ally_damage)
	_check(not await _buy(&"soldier_damage"), "no fourth Soldier Damage level")
	if trained:
		_check(trained.melee_damage > trained_damage and is_equal_approx(trained.max_health, trained_health),
				"Soldier Damage raises only damage (%.1f, %.0f hp)" % [trained.melee_damage, trained.max_health])
	var health := player.ally_health
	for i in 3:
		_check(await _buy(&"soldier_health"), "Soldier Health level %d" % (i + 1))
	_check(is_equal_approx(player.ally_health, health + 0.75) and player.is_upgrade_maxed(_def(&"soldier_health")),
			"soldier health +75%% at most (x%.2f)" % player.ally_health)
	_check(not await _buy(&"soldier_health"), "no fourth Soldier Health level")
	if trained:
		_check(trained.max_health > trained_health, "Soldier Health raises its health (%.0f hp)" % trained.max_health)
	if shot != "":
		await _wait(0.3)
		get_viewport().get_texture().get_image().save_png(shot)
	for soldier in player.followers():
		soldier.queue_free()  # it would fight the orcs the class checks below count hits on
	(hud.upgrade_sheet.find_child("HeroTab", true, false) as Button).button_pressed = true
	(hud.upgrade_sheet.find_child("HeroTab", true, false) as Button).pressed.emit()
	await _wait(0.2)


func _damage() -> float:
	match player.class_def.id:
		&"spearman":
			return player.spear_damage
		&"bowman":
			return player.arrow_damage
	return player.melee_damage


func _cooldown() -> float:
	return player.shoot_cooldown if player.class_def.id == &"bowman" else player.melee_cooldown


func _shield() -> void:
	_check(not player.has_shield() and not player.can_block() and not player._left_item.visible, "no shield until bought")
	_check(await _buy(&"shield"), "bought the shield")
	_check(player.has_shield() and player._left_item.visible and player.shield_health == player.class_def.shield_health,
			"the shield is carried (%.0f)" % player.shield_health)


func _swordsman() -> void:
	await _shield()
	# Knock Back: shoves far; locks Wave.
	var orc := _orc(Vector3(1.0, 0, 0))
	await _wait(0.1)
	player.face_now(Vector3.RIGHT)
	player.attack_melee_toward(Vector3.RIGHT)
	await _wait(0.5)
	# The shove each hit gives (the orc's knockback velocity; its physics is off so nothing decays it).
	var plain_push := (orc.get("_knockback") as Vector3).length()
	orc.set("_knockback", Vector3.ZERO)
	_check(await _buy(&"sword_knockback"), "bought Knock Back")
	_check(player.is_upgrade_locked(_def(&"sword_wave")) and not player.can_buy(_def(&"sword_wave")), "Knock Back locks Wave")
	var wave_button := main.find_child("Buy_sword_wave", true, false) as Button
	_check(wave_button.disabled and wave_button.text == "Other choice taken", "the Wave card says the other choice is taken")
	player._melee_timer = 0.0
	player.attack_melee_toward(Vector3.RIGHT)
	await _wait(0.5)
	var strong_push := (orc.get("_knockback") as Vector3).length()
	_check(plain_push > 0.0 and strong_push > plain_push * 2.5, "Knock Back shoves much harder (%.1f vs %.1f m/s)" % [strong_push, plain_push])
	orc.queue_free()
	# Wave: reset the choice, take Wave instead; a swing reaches two orcs 3 and 4.5 m away.
	player.upgrade_levels = {&"shield": 1, &"sword_damage": 1, &"sword_rate": 1}
	player.grant_upgrade(&"sword_wave")
	var near := _orc(Vector3(3.0, 0, 0))
	var far := _orc(Vector3(4.5, 0, 0.3))
	await _wait(0.1)
	player._melee_timer = 0.0
	player.attack_melee_toward(Vector3.RIGHT)
	await _wait(0.8)
	_check(near.health < near.max_health and far.health < far.max_health, "the slash wave goes through both orcs (%.0f, %.0f)" % [near.health, far.health])
	near.queue_free()
	far.queue_free()
	# Dash Attack.
	_check(not player.has_dash(), "no dash until bought")
	_check(await _buy(&"sword_dash"), "bought Dash Attack")
	player.global_position = LANE_START
	var crossed := _orc(LANE_START + Vector3(0, 0, 2.0))
	var start := player.global_position
	await _wait(0.1)
	player.dash(Vector3.BACK)
	_check(player.dash_active, "dash starts")
	await _wait(0.5)
	var moved := start.distance_to(player.global_position)
	_check(moved > 3.8 and moved < 5.2, "dashed %.2f m" % moved)
	_check(crossed.health < crossed.max_health, "the orc crossed takes the dash slash (%.0f)" % crossed.health)
	var after_one := crossed.health
	_check(not player.dash_active and not player.can_dash(), "dash over, cooling down")
	player.dash(Vector3.FORWARD)
	await _wait(0.4)
	_check(is_equal_approx(crossed.health, after_one), "no second dash during the cooldown")


func _spearman() -> void:
	await _shield()
	_check(player.weapons == PackedStringArray(["spear"]), "stab only before Can Throw (%s)" % player.weapons)
	player.switch_weapon()
	_check(player.current_weapon() == "spear", "E does nothing without Can Throw")
	_check(await _buy(&"spear_throw"), "bought Can Throw")
	_check(player.weapons == PackedStringArray(["spear", "javelin"]), "now carries thrust + throw")
	player.switch_weapon()
	_check(player.current_weapon() == "javelin" and player.holds_ranged(), "E switches to throwing")
	player.global_position = LANE_START
	var orc := _orc(LANE_START + Vector3(0, 0, 5.0))
	await _wait(0.1)
	player._shoot_timer = 0.0
	player.shoot(Vector3(0, 0, 5.0))
	await _wait(0.8)
	_check(orc.health < orc.max_health, "a thrown spear hits (%.0f)" % orc.health)


func _bowman() -> void:
	# Range.
	var range_before := player.aim_range
	_check(await _buy(&"bow_range"), "bought Fire Range")
	_check(is_equal_approx(player.aim_range, range_before + 2.5), "aim range %.1f -> %.1f m" % [range_before, player.aim_range])
	player.global_position = LANE_START
	var target := _orc(LANE_START + Vector3(0, 0, player.aim_range - 0.5))
	await _wait(0.1)
	player._shoot_timer = 0.0
	player.shoot(Vector3(0, 0, player.aim_range - 0.5))
	await _wait(1.2)
	_check(target.health < target.max_health, "an arrow reaches an orc at the new range (%.1f m)" % (player.aim_range - 0.5))
	target.queue_free()
	# Penetration: 3 orcs in a line, two levels → all three hit by one arrow.
	_check(await _buy(&"bow_pierce") and await _buy(&"bow_pierce"), "bought Penetration twice")
	_check(player.is_upgrade_maxed(_def(&"bow_pierce")) and player.arrow_pierce == 2, "Penetration maxed at 2")
	var line: Array[Enemy] = []
	for z in [3.0, 5.0, 7.0, 9.0]:
		line.append(_orc(LANE_START + Vector3(0, 0, z)))
	await _wait(0.1)
	player._shoot_timer = 0.0
	player.shoot(Vector3(0, 0, 10.0))
	await _wait(1.0)
	var hit := line.filter(func(o: Enemy) -> bool: return o.health < o.max_health).size()
	_check(hit == 3, "one arrow hits 3 orcs in a line, not the 4th (%d hit)" % hit)
	for orc in line:
		orc.queue_free()
	# Knife.
	_check(not player.has_knife(), "no knife until bought")
	_check(await _buy(&"knife"), "bought the Knife")
	var close := _orc(LANE_START + Vector3(0.9, 0, 0))
	var far := _orc(LANE_START + Vector3(1.8, 0, 0))  # in the sword's reach, past the knife's
	var aside := _orc(LANE_START + Vector3(cos(deg_to_rad(45.0)), 0, sin(deg_to_rad(45.0))) * 0.9)  # outside its narrow fan
	await _wait(0.1)
	player.knife_attack(Vector3.RIGHT)
	player._shoot_timer = 0.0
	player.shoot(Vector3.RIGHT * 5.0)
	_check(player._shoot_timer == 0.0, "no arrow while stabbing with the knife")
	await _wait(0.3)
	_check(is_equal_approx(close.max_health - close.health, player.knife_damage), "the knife stabs an orc up close (%.0f)" % (close.max_health - close.health))
	_check(far.health == far.max_health, "the knife doesn't reach as far as the sword")
	_check(aside.health == aside.max_health, "the knife's fan is narrow (an orc 45° aside is missed)")
	far.queue_free()
	aside.queue_free()
	var knife_item := player.get("_knife_item") as Node3D
	_check(knife_item != null, "the knife shows in the hand")
