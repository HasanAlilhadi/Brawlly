extends Node
var t := 0.0
var phase := 0
var pt := 0.0
var main: Node
var player: Player
var hud: Hud
var band: Warband

func _ready() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")

func _next(msg: String) -> void:
	printerr("[%.1fs] %s" % [t, msg]); phase += 1; pt = 0.0

func _drive(p: Vector3, stop := 0.8) -> bool:
	var to := p - player.global_position; to.y = 0
	hud.joystick.output = Vector2(to.x, to.z).normalized() if to.length() > stop else Vector2.ZERO
	return to.length() <= stop

func _nearest(group: StringName, filter := Callable()) -> Node3D:
	var best: Node3D = null
	for n in get_tree().get_nodes_in_group(group):
		if GameConfig.is_gone(n): continue
		if filter.is_valid() and not filter.call(n): continue
		if best == null or n.global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position): best = n
	return best

func _process(delta: float) -> void:
	if _tick(delta):
		get_tree().quit()


func _tick(delta: float) -> bool:
	t += delta; pt += delta
	main = get_tree().current_scene
	if main == null or not main.has_node("HUD"): return false
	hud = main.get_node("HUD")
	var players := get_tree().get_nodes_in_group(&"players")
	if players.is_empty(): return false
	player = players[0]
	match phase:
		0:
			if Chest.DEFINITIONS.size() != 5:
				printerr("FAILED chest rarity count: %d" % Chest.DEFINITIONS.size())
			for i in Chest.DEFINITIONS.size() - 1:
				var current: Dictionary = Chest.DEFINITIONS[i]
				var next: Dictionary = Chest.DEFINITIONS[i + 1]
				if (next.coins as Vector2i).x <= (current.coins as Vector2i).x \
						or float(next.health) <= float(current.health) or next.color == current.color:
					printerr("FAILED chest rarity progression at tier %d" % i)
			player.max_health = 1e6; player.health = 1e6
			_next("solo started: players=%d warbands=%d enemies=%d peer=%d team=%d" % [players.size(), get_tree().get_nodes_in_group(&"warbands").size(), get_tree().get_nodes_in_group(&"enemies").size(), player.peer_id, player.team_id])
		1:
			var chest: Node3D = null
			for c in main.get_node("World").get_children():
				if c is Chest and (chest == null or c.global_position.distance_to(player.global_position) < chest.global_position.distance_to(player.global_position)): chest = c
			# Break it open with the sword.
			if is_instance_valid(chest) and _drive(chest.global_position, 1.0): player.attack_melee_toward(chest.global_position - player.global_position)
			if pt > 5: _next("chest: coins %d" % player.coins)
		2:
			var tree := _nearest(&"choppable")
			if tree and _drive(tree.global_position, 1.1): player.attack_melee()
			if pt > 6: _next("chop: tree %s" % ("felled" if tree == null or tree.is_dead else "standing"))
		3:
			band = _nearest(&"warbands", func(b: Warband) -> bool: return b.size <= 6 and not b.is_dead)
			player.global_position = band.global_position + Vector3(0, 0, 4)
			_next("at a warband of %d" % band.size)
		4:
			# Sword only: fight the band until it is wiped out (they come to us).
			var foe := _nearest(&"active_enemies")
			if foe and _drive(foe.global_position, 1.2): player.attack_melee_toward(foe.global_position - player.global_position)
			elif foe == null: hud.joystick.output = Vector2.ZERO
			if band.is_dead:
				if player.followers().size() > 0: printerr("FAILED a wiped-out band gave soldiers")
				_next("warband wiped out: my soldiers=%d coins=%d" % [player.followers().size(), player.coins])
			elif pt > 60: _next("FAILED warband still has %d" % band.alive)
		5:
			_drive(band.global_position + Vector3(0, 0, 4), 0.5)
			if pt > 3:
				hud.joystick.output = Vector2.ZERO
				# No town, no stalls: the spawn area stays clear of warbands; everything is bought anywhere.
				for group: StringName in [&"towns", &"shop_stations", &"penned"]:
					if get_tree().get_node_count_in_group(group) > 0: printerr("FAILED group %s still used" % group)
				var nearest_camp := INF
				for c: Warband in get_tree().get_nodes_in_group(&"warbands"):
					nearest_camp = minf(nearest_camp, Vector3.ZERO.distance_to(c.global_position))
				if nearest_camp < 24.0: printerr("FAILED a warband %.1f m from the spawn" % nearest_camp)
				player.coins += 100
				var vitality := _def(&"vitality")
				var max_before := player.max_health
				player.request_buy(vitality)
				if player.max_health <= max_before: printerr("FAILED Vitality from the sheet")
				# Potion: a consumable, bought again and again while hurt (not at full health).
				var potion := _def(&"potion")
				player.health = player.max_health
				if player.can_buy(potion): printerr("FAILED potion buyable at full health")
				player.coins += 100
				var potions := 0
				for i in 3:
					player.health = player.max_health * 0.3
					potions += int(player.buy_upgrade(potion))
				if potions != 3 or player.health <= player.max_health * 0.3:
					printerr("FAILED potions: bought %d, health %.0f" % [potions, player.health])
				_next("nearest warband to the spawn %.1f m; bought vitality + %d potions: max health %.0f, coins %d" % [nearest_camp, potions, player.max_health, player.coins])
		6:
			# Recruit: 10 each, trains one after another (5 s each), then joins right behind the player.
			player.coins = 30
			var recruit := _def(&"recruit")
			var bought := int(player.buy_upgrade(recruit)) + int(player.buy_upgrade(recruit))
			if bought != 2 or player.coins != 10 or player.soldiers_training != 2:
				printerr("FAILED recruit: bought %d, coins %d, training %d" % [bought, player.coins, player.soldiers_training])
			_next("recruited 2 (training %d, next in %.1fs)" % [player.soldiers_training, player.next_soldier_in()])
		7:
			if pt > 5.6 and pt < 5.65 and (player.followers().size() != 1 or player.soldiers_training != 1):
				printerr("FAILED queue at 5 s: following %d training %d" % [player.followers().size(), player.soldiers_training])
			if pt > 10.6:
				var d := _army_center().distance_to(player.global_position)
				if player.followers().size() != 2 or player.soldiers_training != 0 or d > 4.0:
					printerr("FAILED joined at 10 s: following %d training %d, %.1f m from the player" % [player.followers().size(), player.soldiers_training, d])
				# Fill the army (cap 10) and skip the training.
				player.coins = 100000
				var recruit := _def(&"recruit")
				while player.buy_upgrade(recruit): pass
				if player.army_size() != 10: printerr("FAILED cap 10: army %d" % player.army_size())
				for i in player._training_left.size(): player._training_left[i] = 0.0
				_next("army capped at %d (training %d)" % [player.army_size(), player.soldiers_training])
		8:
			if pt > 4.0:
				var far := player.followers().filter(func(a: Node3D) -> bool: return a.global_position.distance_to(player.global_position) > 5.0).size()
				if player.followers().size() != 10 or player.soldiers_training != 0 or far > 0:
					printerr("FAILED army: following %d, training %d, far %d" % [player.followers().size(), player.soldiers_training, far])
				# Command: +1 per level, 100 coins each (constant), up to 15.
				var command := _def(&"command")
				var prices := PackedInt32Array()
				while player.can_buy(command):
					prices.append(player.upgrade_cost(command))
					player.buy_upgrade(command)
				if player.follower_cap != 15 or prices != PackedInt32Array([100, 100, 100, 100, 100]):
					printerr("FAILED cap: %d, command prices %s" % [player.follower_cap, prices])
				_next("all %d soldiers follow (far %d); Command -> cap %d (prices %s)" % [player.followers().size(), far, player.follower_cap, prices])
		9:
			player.max_health = 100; player.health = 1
			player.take_damage(5)
			_next("player killed")
		10:
			if pt > 2.0:
				printerr("end panel visible=", hud.end_panel.visible, " title=", hud.end_title.text, " restart=", hud.restart_button.text)
				return true
	return t > 150


func _def(id: StringName) -> UpgradeDef:
	for def in Player.CATALOG.upgrades:
		if def.id == id: return def
	return null


func _army_center() -> Vector3:
	var sum := Vector3.ZERO
	for ally in player.followers():
		sum += (ally as Node3D).global_position
	return sum / maxf(player.followers().size(), 1.0)
