extends Node
var t := 0.0
var phase := 0
var pt := 0.0
var main: Node
var player: Player
var hud: Hud
var camp: Camp

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
			_next("solo started: players=%d camps=%d orcs=%d peer=%d team=%d" % [players.size(), get_tree().get_nodes_in_group(&"camps").size(), get_tree().get_nodes_in_group(&"enemies").size(), player.peer_id, player.team_id])
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
			camp = _nearest(&"camps")
			player.global_position = camp.global_position + Vector3(0, 0, camp.radius + 3)
			_next("at camp squad=%d" % camp.squad_size)
		4:
			# Sword only (no bow in hand): get within reach of the wall and keep swinging at it.
			if _drive(camp.global_position, camp.radius + 0.7): player.attack_melee_toward(camp.global_position - player.global_position)
			else: player.attack_melee()
			if camp.is_dead:
				if player.followers().size() > 0: printerr("FAILED a destroyed camp gave soldiers")
				_next("camp destroyed: my soldiers=%d coins=%d" % [player.followers().size(), player.coins])
			elif pt > 40: _next("FAILED camp hp %.0f" % camp.health)
		5:
			_drive(camp.global_position + Vector3(0, 0, 4), 0.5)
			if pt > 3:
				var shop: ShopMenu = main.get_node("ShopMenu")
				player.coins += 100
				var vitality: UpgradeDef
				for def in shop.catalog.upgrades:
					if def.id == &"vitality": vitality = def
				var stalls := get_tree().get_nodes_in_group(&"shop_stations")
				var nearest_camp := INF
				for stall: ShopStation in stalls:
					for c: Camp in get_tree().get_nodes_in_group(&"camps"):
						nearest_camp = minf(nearest_camp, stall.global_position.distance_to(c.global_position))
				printerr("stalls=%d nearest camp to a stall=%.1f m" % [stalls.size(), nearest_camp])
				if stalls.size() != ShopStation.ORDER.size() or nearest_camp < 17.0: printerr("FAILED trading post")
				if player.buy_upgrade(vitality): printerr("FAILED bought Vitality away from the Healer")
				for stall: ShopStation in stalls:
					if stall.stall_id == &"armory": player.global_position = stall.front()
				if player.buy_upgrade(vitality): printerr("FAILED Bows & Spears sold Vitality")
				for stall: ShopStation in stalls:
					if stall.stall_id == &"healer": player.global_position = stall.front()
				player.request_buy(vitality)
				_next("bought vitality: max health %.0f, coins %d, levels %s" % [player.max_health, player.coins, player.upgrade_levels])
		6:
			# Barracks: soldiers cost 50 each and train one after another (10 s each), wait in the pen,
			# and join when taken (at the pen gate or the shop).
			var barracks := _stall(ShopStation.BARRACKS)
			hud.joystick.output = Vector2.ZERO
			player.global_position = barracks.front()
			player.coins = 150
			var recruit := _def(&"recruit")
			var bought := int(player.buy_upgrade(recruit)) + int(player.buy_upgrade(recruit))
			if bought != 2 or player.coins != 50 or player.soldiers_training != 2:
				printerr("FAILED recruit: bought %d, coins %d, training %d" % [bought, player.coins, player.soldiers_training])
			_next("recruited 2 (training %d, next in %.1fs)" % [player.soldiers_training, player.next_soldier_in()])
		7:
			var barracks := _stall(ShopStation.BARRACKS)
			if pt > 10.6 and pt < 10.65 and (player.penned_soldiers().size() != 1 or player.soldiers_training != 1):
				printerr("FAILED queue at 10 s: penned %d training %d" % [player.penned_soldiers().size(), player.soldiers_training])
			if pt > 20.6:
				var penned := player.penned_soldiers()
				var inside := penned.all(func(a: Node3D) -> bool: return barracks.in_pen(a.global_position, 0.0))
				if penned.size() != 2 or player.soldiers_training != 0 or player.followers().size() != 0 or not inside:
					printerr("FAILED pen at 20 s: penned %d training %d followers %d inside %s" % [penned.size(), player.soldiers_training, player.followers().size(), inside])
				player.global_position = barracks.front() + Vector3(0, 0, 9)
				if player.collect_soldiers() != 0: printerr("FAILED took soldiers away from the barracks")
				player.global_position = barracks.gate_point()
				if ShopStation.nearest_gate(player) != barracks: printerr("FAILED not at the gate")
				var taken := player.collect_soldiers()
				_next("took %d soldiers at the gate: following %d, penned %d" % [taken, player.followers().size(), player.penned_soldiers().size()])
		8:
			if pt > 5.0:
				var barracks := _stall(ShopStation.BARRACKS)
				var d := _army_center().distance_to(player.global_position)
				if d > 4.0: printerr("FAILED soldiers didn't leave the pen (%.1f m from the player)" % d)
				# Fill the army (cap 10) and skip the training so 8 soldiers crowd the pen.
				player.global_position = barracks.front()
				player.coins = 100000
				var recruit := _def(&"recruit")
				while player.buy_upgrade(recruit): pass
				if player.army_size() != 10: printerr("FAILED cap 10: army %d" % player.army_size())
				for i in player._training_left.size(): player._training_left[i] = 0.0
				_next("army capped at %d (training %d)" % [player.army_size(), player.soldiers_training])
		9:
			if pt > 3.0:
				var barracks := _stall(ShopStation.BARRACKS)
				if player.penned_soldiers().size() != 8: printerr("FAILED pen holds %d" % player.penned_soldiers().size())
				# Inside the compound soldiers pass through each other (walls still block them).
				var bumping := player.penned_soldiers().filter(func(a: Ally) -> bool:
						return a.collision_mask & GameConfig.LAYER_ALLIES != 0 or a.collision_mask & GameConfig.LAYER_FENCE == 0).size()
				if bumping > 0: printerr("FAILED %d soldiers in the courtyard still collide with each other / ignore walls" % bumping)
				player.global_position = barracks.gate_point()
				var taken := player.collect_soldiers()
				# Wait on the far side of the pen: they must file out through the gate and walk around it
				# (the fence blocks soldiers too).
				var out := barracks.gate_point() - barracks.pen_center()
				out.y = 0.0
				player.global_position = barracks.pen_center() - out.normalized() * 7.0
				_next("took %d at the gate" % taken)
		10:
			if pt > 7.0:
				var barracks := _stall(ShopStation.BARRACKS)
				var stuck := player.followers().filter(func(a: Node3D) -> bool: return barracks.in_pen(a.global_position, -0.3)).size()
				var far := player.followers().filter(func(a: Node3D) -> bool: return a.global_position.distance_to(player.global_position) > 5.0).size()
				if stuck > 0 or far > 0: printerr("FAILED soldiers stuck: %d still in the pen, %d far from the player" % [stuck, far])
				var ghosts := player.followers().filter(func(a: Ally) -> bool: return a.collision_mask & GameConfig.LAYER_ALLIES == 0).size()
				if ghosts > 0: printerr("FAILED %d soldiers outside don't collide with each other again" % ghosts)
				# Command: +1 per level, 100 coins each (constant), up to 15.
				player.global_position = barracks.front()
				var command := _def(&"command")
				var prices := PackedInt32Array()
				while player.can_buy(command):
					prices.append(player.upgrade_cost(command))
					player.buy_upgrade(command)
				if player.follower_cap != 15 or prices != PackedInt32Array([100, 100, 100, 100, 100]):
					printerr("FAILED cap: %d, command prices %s" % [player.follower_cap, prices])
				_next("all %d soldiers out (stuck %d, far %d); Command -> cap %d (prices %s)" % [player.followers().size(), stuck, far, player.follower_cap, prices])
		11:
			player.max_health = 100; player.health = 1
			player.take_damage(5)
			_next("player killed")
		12:
			if pt > 2.0:
				printerr("end panel visible=", hud.end_panel.visible, " title=", hud.end_title.text, " restart=", hud.restart_button.text)
				return true
	return t > 150


func _stall(id: StringName) -> ShopStation:
	for stall: ShopStation in get_tree().get_nodes_in_group(&"shop_stations"):
		if stall.stall_id == id: return stall
	return null


func _def(id: StringName) -> UpgradeDef:
	for def in (main.get_node("ShopMenu") as ShopMenu).catalog.upgrades:
		if def.id == id: return def
	return null


func _army_center() -> Vector3:
	var sum := Vector3.ZERO
	for ally in player.followers():
		sum += (ally as Node3D).global_position
	return sum / maxf(player.followers().size(), 1.0)
