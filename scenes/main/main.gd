extends Node3D
## Game entry point for solo and multiplayer matches.
## - Every peer builds the same world from the shared seed in Net.settings.
## - The server waits until every peer has built it, then spawns one Player per peer and starts the camps.
## - Local input (HUD touch controls / keyboard) goes to the local Player on the server.
## - Soldiers from each player's reserve are sent in as follower slots free up.
## - World events (treasure goblin, Orc Warlord), match stats + awards, pings and army orders.

const PLAYER_SCENE := preload("res://scenes/characters/player.tscn")
const ALLY_SCENE := preload("res://scenes/characters/ally.tscn")
const PICKUP_SCENE := preload("res://scenes/items/pickup.tscn")
const GOBLIN_SCENE := preload("res://scenes/characters/treasure_goblin.tscn")
## PC cursor: the kit's gold sword while playing (menus use the gauntlet from Project Settings).
const MATCH_CURSOR := preload("res://assets/ui/cursors/cursor_sword_gold.png")
const MENU_CURSOR := preload("res://assets/ui/cursors/cursor_gauntlet_bronze.png")
const AIM_CURSOR := preload("res://assets/ui/cursors/cursor_target_round_b.png")
const PROJECTILE_SCENES := {
	&"arrow": preload("res://scenes/combat/arrow_projectile.tscn"),
	&"spear": preload("res://scenes/combat/spear_projectile.tscn"),
}
## Reserve soldiers appear this far from their player (off-screen, also on wide desktop screens) and run in.
const REINFORCE_DISTANCE: float = 15.0
## Desktop monitors show the world from a bit further away than phones.
const DESKTOP_CAMERA_ZOOM: float = 1.25
## Army orders from the keyboard / buttons without a cursor point: this far in front of the player.
const ORDER_AHEAD: float = 9.0

enum PingKind { HERE, ATTACK, HELP, LOOT }
const PING_TEXT: PackedStringArray = ["Here!", "Attack!", "Help!", "Loot!"]
const PING_COLORS: Array[Color] = [Color(0.45, 0.8, 1.0), Color(1.0, 0.35, 0.3), Color(0.45, 1.0, 0.5), Color(1.0, 0.82, 0.25)]
## Seconds between pings from the same player (server-enforced).
const PING_COOLDOWN: float = 0.7
## Clients send held-button actions at most this often (the server enforces cooldowns anyway).
const ACTION_SEND_INTERVAL: float = 0.15
const ARMY_ACTIONS: Array[StringName] = [&"army_follow", &"army_charge", &"army_hold"]
## A quick left click keeps aiming the sword this long, so the swing also reaches the server online.
const MOUSE_CLICK_HOLD: float = 0.2

@onready var world: Node3D = $World
@onready var camera: FollowCamera3D = $Camera
@onready var hud: Hud = $HUD
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var shop_menu: ShopMenu = $ShopMenu

var game_mode: GameMode
var local_player: Player
var match_stats: MatchStats
var world_events: WorldEvents

var _camps: Array[Camp] = []
var _camps_left: int = 0
var _ready_peers: Dictionary = {}
var _started: bool = false
var _game_over: bool = false
var _reinforce_timer: float = 0.0
var _melee_send_timer: float = 0.0
var _shoot_send_timer: float = 0.0
var _last_coins: int = 0
var _last_health: float = 0.0
var _vibrate_cooldown: float = 0.0
var _respawn_left: float = 0.0
var _mouse_attack: bool = false
var _mouse_bow: bool = false
var _bow_cursor: bool = false
var _mouse_bow_button: int = MOUSE_BUTTON_RIGHT
var _mouse_click_left: float = 0.0
var _last_ping_ms: Dictionary = {}  # peer -> time of their last ping (server)


func _ready() -> void:
	if Net.players.is_empty():
		# Scene run directly (e.g. from the editor): solo with default settings.
		Net.open_solo_lobby()
		Net.settings.seed = randi()
	var settings := Net.settings
	seed(settings.seed)
	GameConfig.world_half = clampf(40.0 + sqrt(float(settings.camp_count)) * 10.0, 60.0, 170.0)
	GameConfig.orc_strength = Net.DIFFICULTY_STRENGTH[settings.difficulty]
	GameConfig.orc_respawn_scale = Net.DIFFICULTY_RESPAWN[settings.difficulty]
	# Downed + revive needs teammates: online co-op and team modes.
	GameConfig.downed_enabled = Net.is_online() and settings.mode != Net.Mode.DEATHMATCH
	_setup_spawners()
	HitFx.world = world
	HitFx.main = self
	HitFx.camera = camera

	game_mode = GameMode.new()
	game_mode.setup(settings, Net.players)
	add_child(game_mode)
	match_stats = MatchStats.new()
	add_child(match_stats)
	match_stats.awards_ready.connect(hud.show_awards)
	world_events = WorldEvents.new()
	world_events.setup(self, game_mode, settings.get("events", true))
	add_child(world_events)
	var builder := WorldBuilder.new()
	builder.camp_count = settings.camp_count
	builder.spawn_points = game_mode.world_spawn_points()
	builder.clear_areas = game_mode.world_clear_areas()
	_camps = builder.build(world)
	game_mode.build_objectives(world)
	_camps_left = _camps.size()
	for camp in _camps:
		camp.destroyed.connect(_on_camp_destroyed)

	hud.set_camps(_camps_left, _camps.size())
	hud.restart_requested.connect(_restart)
	hud.main_menu_requested.connect(func() -> void: Net.leave())
	hud.pause_requested.connect(pause_menu.open)
	hud.shop_requested.connect(shop_menu.open)
	hud.bow_stick.aim_released.connect(_on_bow_released)
	hud.bow_stick.tapped.connect(func() -> void: _fire(Vector3.ZERO))
	hud.melee_button.tapped.connect(_melee_once)
	hud.weapon_switch_requested.connect(_switch_weapon)
	hud.army_command_requested.connect(func(order: int) -> void: _command_army(order))
	hud.ping_requested.connect(func() -> void: _ping(_ahead_point(0.0)))
	hud.set_mode_label(game_mode.score_text())
	pause_menu.online = Net.is_online()
	shop_menu.online = Net.is_online()
	pause_menu.paused.connect(_on_paused)
	shop_menu.opened.connect(_on_paused)
	game_mode.scores_changed.connect(func() -> void: hud.set_mode_label(game_mode.score_text()))
	game_mode.announced.connect(func(message: String) -> void: hud.show_toast(message))
	game_mode.match_over.connect(_end)

	if not Platform.mobile_layout:
		camera.offset *= DESKTOP_CAMERA_ZOOM
		Input.set_custom_mouse_cursor(MATCH_CURSOR, Input.CURSOR_ARROW, Vector2(2, 2))
	# Look at our spawn until our player appears.
	var spawn := game_mode.spawn_point_for(Net.my_id())
	camera.global_position = spawn + camera.offset
	camera.look_at(spawn, Vector3.UP)

	multiplayer.peer_disconnected.connect(_on_peer_left)
	# Safety: never stay black if something goes wrong while starting.
	get_tree().create_timer(8.0).timeout.connect(func() -> void:
		if Transition.is_black():
			Transition.fade_in())
	if multiplayer.is_server():
		_on_world_ready(1)
	else:
		_report_world_ready()


## Client: tell the server our world is built. Repeated until our player appears, because a faster
## client can finish loading before the server's match scene exists (that first message would be lost).
func _report_world_ready() -> void:
	while is_inside_tree() and local_player == null and multiplayer.has_multiplayer_peer():
		_net_world_ready.rpc_id(1)
		await get_tree().create_timer(0.5).timeout


# --- Spawning ------------------------------------------------------------------

func _setup_spawners() -> void:
	var units := Node3D.new()
	units.name = "Units"
	world.add_child(units)
	var items := Node3D.new()
	items.name = "Items"
	world.add_child(items)
	var unit_spawner := MultiplayerSpawner.new()
	unit_spawner.name = "UnitSpawner"
	add_child(unit_spawner)
	unit_spawner.spawn_path = unit_spawner.get_path_to(units)
	unit_spawner.spawn_function = _spawn_unit
	unit_spawner.spawned.connect(_on_unit_spawned)
	var item_spawner := MultiplayerSpawner.new()
	item_spawner.name = "ItemSpawner"
	add_child(item_spawner)
	item_spawner.spawn_path = item_spawner.get_path_to(items)
	item_spawner.spawn_function = _spawn_item
	NetSpawn.units = unit_spawner
	NetSpawn.items = item_spawner
	NetSpawn._counter = 0


## Builds a unit from spawn data (runs on the server and on every client).
func _spawn_unit(data: Dictionary) -> Node:
	var unit: Unit
	match data.kind:
		&"player":
			var player := PLAYER_SCENE.instantiate() as Player
			player.peer_id = data.peer
			player.display_name = data.display_name
			player.coins = data.get("start_coins", 0)
			unit = player
		&"ally":
			unit = ALLY_SCENE.instantiate() as Ally
		&"goblin":
			unit = GOBLIN_SCENE.instantiate() as TreasureGoblin
			unit.max_health *= data.get("health_scale", 1.0)
		&"enemy":
			var enemy := (load(data.scene) as PackedScene).instantiate() as Enemy
			enemy.home = data.pos
			if data.has("camp"):
				enemy.camp = get_node_or_null(data.camp) as Camp
			if data.has("warlord"):
				enemy.warlord = get_node_or_null(data.warlord) as Warlord
			enemy.max_health *= data.strength
			enemy.melee_damage *= data.strength
			enemy.throw_damage *= data.strength
			enemy.coin_multiplier = data.coins
			unit = enemy
	unit.name = data.name
	unit.position = data.pos
	unit.team_id = data.get("team", GameConfig.ORC_TEAM)
	unit.owner_peer = data.get("owner", data.get("peer", 0))
	unit.unit_color = data.get("color", Color(1, 1, 1, 0))
	return unit


func _spawn_item(data: Dictionary) -> Node:
	var node: Node3D
	if data.kind == &"pickup":
		var pickup := PICKUP_SCENE.instantiate() as Pickup
		pickup.kind = data.pickup_kind
		pickup.amount = data.amount
		pickup.position = data.pos
		node = pickup
	else:
		var projectile := (PROJECTILE_SCENES[data.kind] as PackedScene).instantiate() as ArrowProjectile
		projectile.start = data.pos
		projectile.direction = data.dir
		projectile.damage = data.damage
		projectile.crit = data.get("crit", false)
		projectile.team_id = data.team
		projectile.owner_peer = data.owner
		projectile.shooter_path = data.shooter
		node = projectile
	node.name = data.name
	return node


func _on_unit_spawned(node: Node) -> void:
	if node is Player and (node as Player).is_local():
		_bind_local_player(node)


func _spawn_player(peer: int) -> void:
	var player := NetSpawn.unit(&"player", game_mode.spawn_point_for(peer), {
		"peer": peer,
		"display_name": Net.name_of(peer),
		"team": Net.team_of(peer),
		"color": Net.color_of(peer),
		"start_coins": int(Net.settings.start_coins),
	}) as Player
	player.died.connect(_on_player_died)
	player.went_down.connect(_on_player_down)
	player.revived.connect(_on_player_revived)
	if player.is_local():
		_bind_local_player(player)


func _bind_local_player(player: Player) -> void:
	local_player = player
	if not multiplayer.is_server():
		player.enable_prediction()  # move instantly on this device, the server corrects drift
	camera.target = player
	camera.snap()
	hud.setup(player, _camps)
	shop_menu.setup(player)
	_last_coins = player.coins
	player.coins_changed.connect(_on_local_coins_changed)
	_last_health = player.health
	player.health_changed.connect(_on_local_health_changed)
	Transition.fade_in(0.6)


# --- Match start (server waits for everyone's world) -----------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _net_world_ready() -> void:
	if multiplayer.is_server():
		_on_world_ready(multiplayer.get_remote_sender_id())


func _on_world_ready(peer: int) -> void:
	_ready_peers[peer] = true
	if _started:
		return
	for p in Net.players:
		if not _ready_peers.has(p):
			return
	_started = true
	for p in Net.players:
		_spawn_player(p)
	for camp in _camps:
		camp.start()


func _on_peer_left(peer: int) -> void:
	if not multiplayer.is_server():
		return
	for unit in get_tree().get_nodes_in_group(&"units"):
		if unit.get("owner_peer") == peer:
			unit.queue_free()
	if not _started:
		_on_world_ready(1)  # someone left while loading: start with the rest


# --- Input ---------------------------------------------------------------------
# Desktop: WASD / arrows / left stick move. One weapon in hand (Q / Y switch): left mouse swings the sword
# toward the cursor, or with the bow aims at the cursor (left or right mouse, release to shoot). J / RB and
# Space / K / RT use the weapon on the nearest enemy (the bow at the right-stick direction when aiming).
# Touch: HUD joystick + the stick of the weapon in hand + a switch button.

func _physics_process(delta: float) -> void:
	if _game_over or local_player == null or not is_instance_valid(local_player):
		_show_bow_cursor(false)
		return
	_mouse_click_left = maxf(_mouse_click_left - delta, 0.0)
	var move := hud.joystick.output
	var keys := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if keys != Vector2.ZERO:
		move = keys
	var aim := Vector3.ZERO
	if hud.bow_stick.is_aiming:
		aim = Vector3(hud.bow_stick.output.x, 0.0, hud.bow_stick.output.y)
	var stick := Input.get_vector(&"aim_left", &"aim_right", &"aim_up", &"aim_down")
	if stick != Vector2.ZERO:
		aim = Vector3(stick.x, 0.0, stick.y)
	if _mouse_bow:
		aim = _cursor_direction()
	_show_bow_cursor(_mouse_bow and not local_player.is_dead)
	var melee := local_player.holds_melee()
	var melee_aim := Vector3.ZERO
	if hud.melee_button.is_aiming:
		melee_aim = Vector3(hud.melee_button.output.x, 0.0, hud.melee_button.output.y)
	if melee and (_mouse_attack or _mouse_click_left > 0.0):
		melee_aim = _cursor_direction()
	# Holding the sword button without dragging (or an attack key) keeps auto-attacking the nearest enemy;
	# with the bow in hand the same keys shoot.
	var use_held := _attack_key_held() or Input.is_action_pressed(&"shoot")
	var melee_held := melee and melee_aim == Vector3.ZERO and (hud.melee_button.is_held or use_held)
	var shoot_held := not melee and use_held
	if multiplayer.is_server():
		local_player.set_input(move, aim, melee_aim)
		if melee_held:
			local_player.attack_melee()
		if shoot_held:
			local_player.shoot(aim)
		return
	# Client: move / aim locally right away (prediction), send everything to the server.
	local_player.predict_input = move if not local_player.is_dead else Vector2.ZERO
	local_player.set_melee_aim(melee_aim)
	if melee_aim == Vector3.ZERO:
		if aim != Vector3.ZERO:
			local_player.set_aim(aim)
		elif local_player.is_aiming():
			local_player.clear_aim()
	local_player.net_input.rpc_id(1, move, aim, melee_aim)
	_melee_send_timer -= delta
	_shoot_send_timer -= delta
	if melee_held and _melee_send_timer <= 0.0:
		_melee_send_timer = ACTION_SEND_INTERVAL
		local_player.net_melee.rpc_id(1)
	if shoot_held and _shoot_send_timer <= 0.0:
		_shoot_send_timer = ACTION_SEND_INTERVAL
		local_player.net_shoot.rpc_id(1, aim)


## Mouse buttons only count when they didn't land on the HUD (pause / shop buttons, minimap).
func _unhandled_input(event: InputEvent) -> void:
	if _game_over or local_player == null:
		return
	var button := event as InputEventMouseButton
	var real_click := button != null and button.pressed and button.device != InputEvent.DEVICE_ID_EMULATION \
			and not Platform.mobile_layout
	if real_click and local_player.holds_ranged() and (button.is_action(&"attack") or button.is_action(&"aim_bow")):
		_mouse_bow = true
		_mouse_bow_button = button.button_index
	elif real_click and button.is_action(&"attack"):
		_mouse_attack = true
		_mouse_click_left = MOUSE_CLICK_HOLD
	elif event.is_action_pressed(&"switch_weapon") and not event.is_echo():
		_switch_weapon()
	elif event.is_action_pressed(&"shop") and not event.is_echo():
		shop_menu.open()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ping") and not event.is_echo():
		_ping(_ahead_point(6.0) if event is InputEventJoypadButton else _pointer_point())
	elif event.is_action_pressed(&"ping_help") and not event.is_echo():
		_ping(local_player.global_position, true)
	else:
		for order in 3:
			if event.is_action_pressed(ARMY_ACTIONS[order]) and not event.is_echo():
				_command_army(order, _ahead_point(ORDER_AHEAD) if event is InputEventJoypadButton else _pointer_point())


## Releases are caught everywhere (also over the HUD) so buttons never stick.
func _input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or button.pressed:
		return
	if button.is_action(&"attack"):
		_mouse_attack = false
	if _mouse_bow and button.button_index == _mouse_bow_button:
		_mouse_bow = false
		_fire(_cursor_direction())
		if local_player:
			local_player.clear_aim()


## Keyboard / gamepad sword button (the mouse button is handled separately, it aims at the cursor).
func _attack_key_held() -> bool:
	return Input.is_action_pressed(&"attack") and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


## Ground point under the mouse cursor (Vector3.INF if the cursor points at the sky).
func _cursor_point() -> Vector3:
	var mouse := get_viewport().get_mouse_position()
	var ground := Plane(Vector3.UP, local_player.global_position.y)
	var hit: Variant = ground.intersects_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
	return hit if hit != null else Vector3.INF


## Where pings / orders from the keyboard go: the cursor on desktop, in front of the player on phones.
func _pointer_point() -> Vector3:
	var point := Vector3.INF if Platform.mobile_layout else _cursor_point()
	return point if point != Vector3.INF else _ahead_point(ORDER_AHEAD)


func _ahead_point(distance: float) -> Vector3:
	return local_player.global_position + local_player.facing() * distance


## Flat direction from the local player to the point under the mouse cursor (ZERO if unknown).
func _cursor_direction() -> Vector3:
	if local_player == null or not is_instance_valid(local_player):
		return Vector3.ZERO
	var hit := _cursor_point()
	if hit == Vector3.INF:
		return Vector3.ZERO
	var direction: Vector3 = hit - local_player.global_position
	direction.y = 0.0
	return direction.normalized() if direction.length() > 0.15 else local_player.facing()


## Q / Y / the HUD switch button: next weapon in hand (drops any aim in progress).
func _switch_weapon() -> void:
	if local_player == null or _game_over or local_player.is_dead:
		return
	_mouse_bow = false
	_mouse_attack = false
	hud.reset_touch_controls()
	local_player.request_switch_weapon()


func _melee_once() -> void:
	if local_player == null or _game_over:
		return
	if multiplayer.is_server():
		local_player.attack_melee()
	else:
		local_player.net_melee.rpc_id(1)


func _on_bow_released(aim: Vector2) -> void:
	_fire(Vector3(aim.x, 0.0, aim.y))
	if local_player:
		local_player.clear_aim()


func _fire(direction: Vector3) -> void:
	if local_player == null or _game_over:
		return
	if multiplayer.is_server():
		local_player.shoot(direction)
	else:
		local_player.net_shoot.rpc_id(1, direction)


func _on_paused() -> void:
	hud.reset_touch_controls()
	_mouse_attack = false
	_mouse_bow = false
	_mouse_click_left = 0.0
	if local_player:
		local_player.clear_aim()
		local_player.set_melee_aim(Vector3.ZERO)
		if multiplayer.is_server():
			local_player.set_input(Vector2.ZERO, Vector3.ZERO)


# --- Per-frame ---------------------------------------------------------------------

func _process(delta: float) -> void:
	_vibrate_cooldown -= delta
	if multiplayer.is_server() and _started and not _game_over:
		_reinforce(delta)
	_update_respawn_display(delta)


## Each player's reserve soldiers run in, one at a time, while that player has free follower slots.
func _reinforce(delta: float) -> void:
	_reinforce_timer -= delta
	if _reinforce_timer > 0.0:
		return
	_reinforce_timer = 0.4
	for node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player.reserve_soldiers <= 0 or player.is_dead or player.followers().size() >= player.follower_cap:
			continue
		var spot := free_spot_around(player.global_position, REINFORCE_DISTANCE)
		if spot == Vector3.INF:
			continue
		player.reserve_soldiers -= 1
		NetSpawn.unit(&"ally", spot, {"team": player.team_id, "owner": player.peer_id, "color": player.unit_color})


## A point `distance` from `center` not inside a tree/building (tries a few directions).
func free_spot_around(center: Vector3, distance: float) -> Vector3:
	var space := get_world_3d().direct_space_state
	var probe := SphereShape3D.new()
	probe.radius = 0.4
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	query.collision_mask = GameConfig.LAYER_WORLD
	var start := randf() * TAU
	for i in 8:
		var angle := start + TAU * i / 8.0
		var spot := GameConfig.clamp_to_world(center + Vector3(cos(angle), 0.0, sin(angle)) * distance)
		query.transform = Transform3D(Basis(), spot + Vector3(0, 0.5, 0))
		if space.intersect_shape(query, 1).is_empty():
			return spot
	return Vector3.INF


func _update_respawn_display(delta: float) -> void:
	if local_player == null or not is_instance_valid(local_player) or _game_over:
		return
	if local_player.is_dead and game_mode.uses_respawn():
		if _respawn_left <= 0.0:
			_respawn_left = game_mode.respawn_time()
		_respawn_left = maxf(_respawn_left - delta, 0.01)
		hud.show_respawn(ceili(_respawn_left))
	elif _respawn_left > 0.0:
		_respawn_left = 0.0
		hud.show_respawn(0)


# --- Army orders & pings ---------------------------------------------------------

func _command_army(order: int, point: Vector3 = Vector3.INF) -> void:
	if local_player == null or _game_over:
		return
	if point == Vector3.INF:
		point = _ahead_point(ORDER_AHEAD)
	if multiplayer.is_server():
		local_player.command_army(order, point)
	else:
		local_player.net_command.rpc_id(1, order, point)
	var shout: String = ["Follow me!", "Charge!", "Hold here!"][order]
	FloatingText3D.spawn(world, local_player.global_position + Vector3(0, 2.1, 0), shout, Color(1.0, 0.95, 0.8), 52)
	if order != Player.Order.FOLLOW:
		PingMarker.spawn(world, point, shout, local_player.unit_color if local_player.unit_color.a > 0.0 else Color.WHITE,
				local_player.display_name)


## Pings what's at `point` for your team: an enemy → "Attack!", a chest → "Loot!", else "Here!".
func _ping(point: Vector3, help: bool = false) -> void:
	if local_player == null or _game_over:
		return
	var kind := PingKind.HELP if help else PingKind.HERE
	if not help:
		var target := _ping_target(point)
		if target:
			point = target.global_position
			kind = PingKind.LOOT if target is Chest else PingKind.ATTACK
	if multiplayer.is_server():
		_on_ping(Net.my_id(), kind, point)
	else:
		_net_ping.rpc_id(1, kind, point)


func _ping_target(point: Vector3) -> Node3D:
	var best: Node3D = null
	var best_dist := 2.5
	for group in [&"active_enemies", &"camps", &"players", &"allies"]:
		for node in get_tree().get_nodes_in_group(group):
			var candidate := node as Node3D
			if GameConfig.is_gone(candidate) or not GameConfig.is_hostile(local_player, candidate):
				continue
			var d := candidate.global_position.distance_to(point)
			if d < best_dist:
				best_dist = d
				best = candidate
	if best == null:
		for child in world.get_children():
			if child is Chest and not child.get("_opened") and (child as Node3D).global_position.distance_to(point) < 2.0:
				return child
	return best


@rpc("any_peer", "call_remote", "reliable")
func _net_ping(kind: int, point: Vector3) -> void:
	if multiplayer.is_server():
		_on_ping(multiplayer.get_remote_sender_id(), kind, point)


## Server: show the ping to the sender's team (rate-limited).
func _on_ping(sender: int, kind: int, point: Vector3, forced: bool = false) -> void:
	var now := Time.get_ticks_msec()
	if not forced and now - int(_last_ping_ms.get(sender, -100000)) < PING_COOLDOWN * 1000.0:
		return
	_last_ping_ms[sender] = now
	kind = clampi(kind, 0, PingKind.size() - 1)
	point = GameConfig.clamp_to_world(Vector3(point.x, 0.0, point.z))
	if not forced:
		MatchStats.add(sender, &"pings")
	var team := Net.team_of(sender)
	for peer in Net.players:
		if Net.team_of(peer) != team:
			continue
		if peer == multiplayer.get_unique_id():
			_show_ping(sender, kind, point)
		else:
			_net_show_ping.rpc_id(peer, sender, kind, point)


@rpc("authority", "call_remote", "reliable")
func _net_show_ping(sender: int, kind: int, point: Vector3) -> void:
	_show_ping(sender, kind, point)


func _show_ping(sender: int, kind: int, point: Vector3) -> void:
	var color := PING_COLORS[kind]
	if kind == PingKind.HERE:
		color = Net.color_of(sender)
	PingMarker.spawn(world, point, PING_TEXT[kind], color, Net.name_of(sender))


# --- Events --------------------------------------------------------------------

## Server: a player went down — tell everyone, drop a carried flag, and call for help.
func _on_player_down(player: Player) -> void:
	game_mode.on_player_downed(player)
	_on_ping(player.peer_id, PingKind.HELP, player.global_position, true)


func _on_player_revived(player: Player, helpers: Array) -> void:
	var names := PackedStringArray()
	for helper in helpers:
		names.append((helper as Player).display_name)
	game_mode.announce("%s revived %s!" % [" & ".join(names), player.display_name])

func _on_player_died(unit: Unit) -> void:
	var player := unit as Player
	if game_mode.uses_respawn():
		game_mode.on_player_died(player)
		get_tree().create_timer(game_mode.respawn_time()).timeout.connect(func() -> void:
			if is_instance_valid(player) and not game_mode.is_over:
				player.revive(game_mode.spawn_point_for(player.peer_id)))
	else:
		await get_tree().create_timer(1.2).timeout
		game_mode.finish("You fell", "The orcs hold the land... for now.")


## Our own hits on other devices: the server sends the damage number here.
@rpc("authority", "call_remote", "unreliable")
func _net_hit_number(at: Vector3, amount: float, crit: bool, is_melee: bool) -> void:
	HitFx.show_number(at, amount, crit, is_melee)


## Two players hit the same orc within a second (see `Enemy.take_damage`).
@rpc("authority", "call_local", "unreliable")
func _net_combo(at: Vector3) -> void:
	HitFx.show_combo(at)


## We got hit: vibrate, red screen edges, camera shake and a red number over us.
func _on_local_health_changed(current: float, maximum: float) -> void:
	var lost := _last_health - current
	_last_health = current
	if lost < 0.5 or local_player == null:
		return
	var strength := clampf(lost / maximum * 4.0, 0.25, 1.0)
	hud.flash_hurt(strength)
	camera.shake(0.08 + 0.14 * strength, 0.22)
	FloatingText3D.spawn(world, local_player.global_position + Vector3(0, 1.9, 0), str(roundi(lost)), HitFx.HURT_COLOR, 60)
	if _vibrate_cooldown <= 0.0:
		_vibrate_cooldown = 0.15
		Input.vibrate_handheld(int(lerpf(35.0, 110.0, strength)), lerpf(0.4, 1.0, strength))


## PC: a crosshair while the right mouse button aims the bow, the gold sword otherwise.
func _show_bow_cursor(aiming: bool) -> void:
	if aiming == _bow_cursor or Platform.mobile_layout:
		return
	_bow_cursor = aiming
	if aiming:
		Input.set_custom_mouse_cursor(AIM_CURSOR, Input.CURSOR_ARROW, AIM_CURSOR.get_size() * 0.5)
	else:
		Input.set_custom_mouse_cursor(MATCH_CURSOR, Input.CURSOR_ARROW, Vector2(2, 2))


func _exit_tree() -> void:
	Engine.time_scale = 1.0  # in case we leave during a hit-stop
	if not Platform.mobile_layout:
		Input.set_custom_mouse_cursor(MENU_CURSOR, Input.CURSOR_ARROW, Vector2(2, 2))


func _on_local_coins_changed(count: int) -> void:
	if count > _last_coins and local_player:
		FloatingText3D.spawn(world, local_player.global_position + Vector3(randf_range(-0.3, 0.3), 1.6, 0),
				"+%d" % (count - _last_coins), Color(1.0, 0.85, 0.3))
	_last_coins = count


func _on_camp_destroyed(camp: Camp) -> void:
	_camps_left -= 1
	hud.set_camps(_camps_left, _camps.size())
	if camp.destroyed_by() == Net.my_id():
		hud.show_toast("Camp freed!  +%d soldiers" % camp.squad_size)
	elif Net.is_online():
		hud.show_toast("%s freed a camp" % Net.name_of(camp.destroyed_by()))
	if multiplayer.is_server() and game_mode.match_mode == Net.Mode.COOP and _camps_left <= 0:
		game_mode.finish("Victory!", "Every orc camp has fallen.")


func _end(title: String, subtitle: String) -> void:
	if _game_over:
		return
	_game_over = true
	match_stats.publish_awards(game_mode.player_names())
	pause_menu.can_pause = false
	shop_menu.close()
	var restart_label := "Play again"
	if Net.is_online():
		restart_label = "Back to lobby" if Net.is_host() else ""
	hud.show_end(title, subtitle, restart_label)


func _restart() -> void:
	if Net.is_online():
		# Remove replicated units first so every peer despawns them cleanly, then go to the lobby.
		for container in [world.get_node("Units"), world.get_node("Items")]:
			for child in container.get_children():
				child.queue_free()
		await get_tree().create_timer(0.4).timeout
		Net.return_to_lobby()
	else:
		Net.start_game(false)
