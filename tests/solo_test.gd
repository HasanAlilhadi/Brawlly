extends Node
var t := 0.0
var phase := 0
var pt := 0.0
var main: Node
var player: Player
var hud: Hud
var camp: Camp
var arrows_before := 0

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
			player.max_health = 1e6; player.health = 1e6
			arrows_before = player.arrows
			_next("solo started: players=%d camps=%d orcs=%d peer=%d team=%d" % [players.size(), get_tree().get_nodes_in_group(&"camps").size(), get_tree().get_nodes_in_group(&"enemies").size(), player.peer_id, player.team_id])
		1:
			var chest: Node3D = null
			for c in main.get_node("World").get_children():
				if c is Chest and (chest == null or c.global_position.distance_to(player.global_position) < chest.global_position.distance_to(player.global_position)): chest = c
			_drive(chest.global_position, 0.2)
			if pt > 5: _next("chest: arrows %d -> %d, coins %d" % [arrows_before, player.arrows, player.coins]); arrows_before = player.arrows
		2:
			var tree := _nearest(&"choppable")
			if tree and _drive(tree.global_position, 1.1): player.attack_melee()
			if pt > 6: _next("chop: arrows %d -> %d" % [arrows_before, player.arrows])
		3:
			camp = _nearest(&"camps")
			player.global_position = camp.global_position + Vector3(0, 0, camp.radius + 3)
			_next("at camp squad=%d" % camp.squad_size)
		4:
			_drive(camp.global_position, camp.radius + 1.6)
			player.attack_melee(); player.shoot()
			if camp.is_dead: _next("camp destroyed: my soldiers=%d reserve=%d coins=%d" % [player.followers().size(), player.reserve_soldiers, player.coins])
			elif pt > 40: _next("FAILED camp hp %.0f" % camp.health)
		5:
			_drive(camp.global_position + Vector3(0, 0, 4), 0.5)
			if pt > 3:
				var shop: ShopMenu = main.get_node("ShopMenu")
				var bought := false
				player.coins += 100
				for def in shop.catalog.upgrades:
					if def.id == &"blade": player.request_buy(def); bought = true
				_next("bought blade: sword %.0f, coins %d, levels %s" % [player.melee_damage, player.coins, player.upgrade_levels])
		6:
			player.max_health = 100; player.health = 1
			player.take_damage(5)
			_next("player killed")
		7:
			if pt > 2.0:
				printerr("end panel visible=", hud.end_panel.visible, " title=", hud.end_title.text, " restart=", hud.restart_button.text)
				return true
	return t > 150
