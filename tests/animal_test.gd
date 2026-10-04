extends Node
## Animals (scenes/characters/animal.gd, herds scenes/world/animal_herd.gd), on an open field (scenery collision off):
## - every species spawns with its pet model at a sensible size, on the animal team; orcs never fight them;
## - shy animals (pig, cow, deer, fox) run from a hero that comes close and the herd runs together;
## - the wild pig (hog) winds up and rams a hero who comes close (damage + shove), then calms down;
## - an angry wild pig is fought by the hero's soldiers;
## - dead animals drop 3..8 coins, and a health potion about 2 times out of 10;
## - the world has herds that start grazing when the match starts and come back after being wiped out.
##   "$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/animal_test.gd
## --shot=<png> saves one frame with every species (needs a window: --position -4000,-4000, no --headless).

var failures := 0
var shot := ""
var main: Node
var player: Player
var _pickups: Array[Pickup] = []


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
	await _wait(1.0)
	main = get_tree().current_scene
	player = get_tree().get_nodes_in_group(&"players")[0]
	player.max_health = 100000.0
	player.health = 100000.0
	main.set_physics_process(false)  # the hero stands still unless a test moves it
	get_tree().node_added.connect(func(node: Node) -> void:
		if node is Pickup:
			_pickups.append(node))
	await _herds()
	_clear_scenery()
	await _species()
	await _orcs_ignore()
	await _shy()
	await _wild()
	await _soldiers_help()
	await _drops()
	printerr("%s animals: done (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(1 if failures else 0)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _clear_scenery() -> void:
	for node in main.find_children("*", "CollisionObject3D", true, false):
		var body := node as CollisionObject3D
		if not body is Unit and body.collision_layer & GameConfig.LAYER_WORLD:
			body.collision_layer = 0


## A spot far from the herds, camps and spawn, cleared of other units.
func _reset() -> void:
	for node in get_tree().get_nodes_in_group(&"units"):
		if node != player:
			node.queue_free()
	for node in get_tree().get_nodes_in_group(&"herds"):
		node.set_process(false)  # no respawns during the checks
	player.global_position = Vector3.ZERO
	await _wait(0.2)
	_pickups.clear()


func _animal(id: String, at: Vector3) -> Animal:
	return NetSpawn.unit(&"animal", at, {"species": id, "home": at}) as Animal


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _herds() -> void:
	var herds := get_tree().get_nodes_in_group(&"herds")
	_check(herds.size() >= 6, "the world has animal herds (%d)" % herds.size())
	var species := {}
	var grazing := 0
	for herd in herds:
		species[(herd as AnimalHerd).species] = true
		grazing += (herd as AnimalHerd).alive().size()
	_check(species.size() == Animal.SPECIES.size(), "every species has herds (%s)" % ", ".join(species.keys()))
	_check(grazing >= herds.size(), "herds are out grazing from the start (%d animals)" % grazing)
	# Wipe one out: it comes back after RESPAWN_TIME once nobody is near.
	var herd := herds[0] as AnimalHerd
	for animal in herd.alive():
		animal.take_damage(100000.0, player)
	await _wait(1.0)
	_check(herd.alive().is_empty(), "a herd can be wiped out")
	player.global_position = herd.global_position + Vector3(AnimalHerd.RESPAWN_CLEAR + 5.0, 0, 0)
	herd._respawn_left = 0.5
	await _wait(1.0)
	_check(herd.alive().size() == herd.size, "it comes back later (%d animals)" % herd.alive().size())


func _species() -> void:
	await _reset()
	var x := -4.0
	for id in Animal.SPECIES:
		var animal := _animal(id, Vector3(x, 0, 3))
		x += 2.0
		await get_tree().process_frame
		var box := AABB()
		var first := true
		for mesh in animal.model.find_children("*", "MeshInstance3D", true, false):
			var part: AABB = (mesh as MeshInstance3D).global_transform * (mesh as MeshInstance3D).get_aabb()
			box = part if first else box.merge(part)
			first = false
		_check(box.size.y > 0.4 and box.size.y < 1.1 and box.position.y > -0.05 and box.position.y < 0.2,
				"%s: pet model, %.2f m tall, standing on the ground (%.2f)" % [id, box.size.y, box.position.y])
		_check(animal.team_id == GameConfig.ANIMAL_TEAM and GameConfig.is_hostile(player, animal), "%s: on the animal team, heroes can hit it" % id)
	if shot != "":
		for animal in get_tree().get_nodes_in_group(&"animals"):
			(animal as Animal).set_physics_process(false)  # hold still (the shy ones would run off) for the picture
			(animal as Animal).face_now(Vector3(1, 0, 1).normalized())
		main.set_physics_process(true)
		main.camera.offset *= 0.55
		player.global_position = Vector3(0, 0, 1.5)
		await _wait(1.2)
		get_viewport().get_texture().get_image().save_png(shot)
		main.camera.offset /= 0.55
		main.set_physics_process(false)


func _orcs_ignore() -> void:
	await _reset()
	var pig := _animal("pig", Vector3(2, 0, 6))
	var hog := _animal("hog", Vector3(-2, 0, 6))
	var orc := NetSpawn.unit(&"enemy", Vector3(0, 0, 6), {"scene": "res://scenes/characters/enemy.tscn", "strength": 1.0,
			"coins": 1.0}) as Enemy
	orc.add_to_group(&"active_enemies")
	player.global_position = Vector3(0, 0, -40)  # far: the orc has nobody else to fight
	await _wait(3.0)
	_check(not GameConfig.is_hostile(orc, pig) and not GameConfig.is_hostile(pig, orc), "orcs and animals are not enemies")
	_check(pig.health == pig.max_health and hog.health == hog.max_health and orc.health == orc.max_health,
			"an orc next to animals leaves them alone (and the wild pig leaves it alone)")


func _shy() -> void:
	await _reset()
	var herd: Array[Animal] = []
	for i in 3:
		herd.append(_animal("deer", Vector3(-1.0 + i, 0, 3.5)))
	for animal in herd:
		animal.home = Vector3(0, 0, 3.5)
	player.global_position = Vector3(0, 0, 0)
	await _wait(0.2)
	player.global_position = Vector3(0, 0, 2.0)  # walks up to them
	await _wait(1.5)
	var fled := herd.filter(func(a: Animal) -> bool: return _flat(a.global_position, player.global_position) > Animal.FLEE_RANGE)
	_check(fled.size() == 3, "a herd of deer runs from a hero who comes close (%d of 3 got away)" % fled.size())
	# A cow hit from afar runs too (and its mates with it).
	await _reset()
	var cow := _animal("cow", Vector3(0, 0, 9))
	var mate := _animal("cow", Vector3(1, 0, 9))
	mate.home = cow.home
	var start := cow.global_position
	cow.take_damage(5.0, player)
	await _wait(1.0)
	_check(_flat(cow.global_position, start) > 2.0 and _flat(cow.global_position, player.global_position) > _flat(start, player.global_position),
			"a cow that gets hit runs away (%.1f m)" % _flat(cow.global_position, start))
	_check(mate._flee_left > 0.0 or _flat(mate.global_position, player.global_position) > 10.0, "its herd mate runs too")


func _wild() -> void:
	await _reset()
	var hog := _animal("hog", Vector3(0, 0, 3.5))
	player.global_position = Vector3(0, 0, 0)
	await _wait(0.4)
	_check(hog.is_angry() and hog.is_in_group(&"active_enemies"), "a wild pig gets angry at a hero who comes close")
	var before := player.health
	var from := player.global_position
	await _wait(3.0)
	_check(before - player.health >= Animal.SPECIES.hog.damage * 0.99, "it charges and rams the hero (%.0f damage)" % (before - player.health))
	_check(_flat(player.global_position, from) > 0.3, "the ram shoves the hero (%.1f m)" % _flat(player.global_position, from))
	# Walk away: it calms down.
	player.global_position = Vector3(0, 0, -40)
	await _wait(Animal.CALM_TIME + 2.0)
	_check(not hog.is_angry() and not hog.is_in_group(&"active_enemies"), "it calms down once the hero is gone")


func _soldiers_help() -> void:
	await _reset()
	var soldier := NetSpawn.unit(&"ally", Vector3(1.0, 0, 0.5), {"team": player.team_id, "owner": player.peer_id,
			"weapon": "sword"}) as Ally
	soldier.max_health = 100000.0
	soldier.health = 100000.0
	var hog := _animal("hog", Vector3(0, 0, 3.5))
	await _wait(1.5)
	_check(soldier.target == hog, "a soldier fights the wild pig that attacks its hero")
	var calm := _animal("pig", Vector3(-3, 0, -3))
	await _wait(1.0)
	_check(soldier.target != calm, "soldiers leave peaceful animals alone")


func _drops() -> void:
	await _reset()
	var deaths := 40
	var coins: Array[int] = []
	var health := 0
	for i in deaths:
		_pickups.clear()
		var animal := _animal(Animal.SPECIES.keys()[i % Animal.SPECIES.size()], Vector3(0, 0, 6))
		await get_tree().process_frame
		animal.take_damage(100000.0, player)
		await get_tree().process_frame
		var total := 0
		for pickup in _pickups:
			if not is_instance_valid(pickup):
				continue
			if pickup.kind == Pickup.Kind.COIN:
				total += pickup.amount
			elif pickup.kind == Pickup.Kind.HEALTH:
				health += 1
		coins.append(total)
		for pickup in _pickups:
			if is_instance_valid(pickup):
				pickup.queue_free()
	_check(coins.all(func(c: int) -> bool: return c >= Animal.COINS_MIN and c <= Animal.COINS_MAX),
			"every animal drops 3..8 coins (%s)" % str(coins))
	var share := float(health) / deaths
	_check(share > 0.05 and share < 0.4, "about 2 in 10 drop a health potion (%d of %d)" % [health, deaths])
