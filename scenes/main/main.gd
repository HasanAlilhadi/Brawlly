extends Node3D
## Game entry point for multiplayer matches (every player's hero is of the class picked in the lobby).
## - Every peer builds the same world from the shared seed in Net.settings.
## - The server waits until every peer has built it, then spawns one Player per peer and starts the warbands.
## - Local input (HUD touch controls / keyboard) goes to the local Player on the server.
## - Everything is bought from the upgrades sheet (T); recruits train, then join their hero (Player.soldiers_training).
## - World events (treasure goblin, Orc Warlord, invasion waves), match stats + awards, pings and army orders.
## - The map (Net.settings.map, a MapCatalog row) sets the light and what WorldBuilder lays out.
## - Last Stand: no respawns — a fallen hero spectates a teammate (attack / switch weapon picks the next one).

const PLAYER_SCENE := preload("res://scenes/characters/player.tscn")
const ALLY_SCENE := preload("res://scenes/characters/ally.tscn")
const PICKUP_SCENE := preload("res://scenes/items/pickup.tscn")
const GOBLIN_SCENE := preload("res://scenes/characters/treasure_goblin.tscn")
const ANIMAL_SCENE := preload("res://scenes/characters/animal.tscn")
const TRAINING_FIELD_SCENE := preload("res://scenes/training/training_field.tscn")
## PC cursor: the kit's gold sword while playing (menus use the gauntlet from Project Settings).
const MATCH_CURSOR := preload("res://assets/ui/cursors/cursor_sword_gold.png")
const MENU_CURSOR := preload("res://assets/ui/cursors/cursor_gauntlet_bronze.png")
const PROJECTILE_SCENES := {
	&"arrow": preload("res://scenes/combat/arrow_projectile.tscn"),
	&"spear": preload("res://scenes/combat/spear_projectile.tscn"),
	&"player_spear": preload("res://scenes/combat/player_spear_projectile.tscn"),
	&"sword_wave": preload("res://scenes/combat/sword_wave_projectile.tscn"),
	&"enemy_arrow": preload("res://scenes/combat/enemy_arrow_projectile.tscn"),
	&"bolt": preload("res://scenes/combat/bolt_projectile.tscn"),
	&"blood_bolt": preload("res://scenes/combat/blood_bolt_projectile.tscn"),
}
## Desktop monitors show the world from a bit further away than phones.
const DESKTOP_CAMERA_ZOOM: float = 1.25
## Default camera zoom-out on top of that (1.2 = 20% further than the camera's offset).
const CAMERA_ZOOM: float = 1.2
## Extra zoom-out while holding a ranged weapon, so you see further where you shoot.
const WEAPON_CAMERA_ZOOM: Dictionary = {"spear": 0.05, "javelin": 0.1, "bow": 0.2}
## Share of the Fire Range gain the camera zooms out by (1 = in proportion: +50% range, +50% further out).
const RANGE_CAMERA_ZOOM: float = 0.8
## Army orders from the keyboard / buttons without a cursor point: this far in front of the player.
const ORDER_AHEAD: float = 9.0

enum PingKind { HERE, ATTACK, HELP, LOOT }
const PING_TEXT: PackedStringArray = ["Here!", "Attack!", "Help!", "Loot!"]
const PING_COLORS: Array[Color] = [Color(0.45, 0.8, 1.0), Color(1.0, 0.35, 0.3), Color(0.45, 1.0, 0.5), Color(1.0, 0.82, 0.25)]
## Seconds between pings from the same player (server-enforced).
const PING_COOLDOWN: float = 0.7
## Clients send held-button actions at most this often (the server enforces cooldowns anyway).
const ACTION_SEND_INTERVAL: float = 0.15
const ARMY_ACTIONS: Array[StringName] = [&"army_follow", &"army_charge", &"army_hold", &"army_kill"]
const ARMY_SHOUTS: PackedStringArray = ["Follow me!", "Charge!", "Hold here!", "Kill!"]
## Kill order with the mouse: an enemy counts as clicked this close to the cursor (px at 1080 p).
const KILL_PICK_PIXELS: float = 70.0
## Kill order without a cursor (gamepad / touch): the enemy nearest this far ahead, within this radius.
const KILL_AHEAD: float = 5.0
const KILL_AHEAD_RADIUS: float = 6.0
const KILL_MARK_TEXTURE := preload("res://assets/ui/icons/game/target.svg")
## A quick left click keeps aiming the sword this long, so the swing also reaches the server online.
const MOUSE_CLICK_HOLD: float = 0.2
## Last Stand plays on a bigger procedural world than the other modes (same band count, more room between the circles).
const LAST_STAND_WORLD_SCALE: float = 1.15

@onready var world: Node3D = $World
@onready var camera: FollowCamera3D = $Camera
@onready var hud: Hud = $HUD
@onready var pause_menu: PauseMenu = $PauseMenu

var game_mode: GameMode
var local_player: Player
var match_stats: MatchStats
var world_events: WorldEvents
var training_field: TrainingField
var training_mode: bool = false
## The map being played (MapCatalog; setting `map`).
var map: MapDef

var _bands: Array[Warband] = []
var _bands_left: int = 0
var _ready_peers: Dictionary = {}
var _started: bool = false
var _game_over: bool = false
var _melee_send_timer: float = 0.0
var _shoot_send_timer: float = 0.0
var _knife_send_timer: float = 0.0
## Mouse: the HUD Kill button was clicked; the next left click in the world picks the target.
var _kill_picking: bool = false
## Over the enemy our soldiers are told to kill (local player's KILL order).
var _kill_mark: Sprite3D
var _last_coins: int = 0
var _last_health: float = 0.0
var _vibrate_cooldown: float = 0.0
var _respawn_left: float = 0.0
var _mouse_attack: bool = false
var _mouse_block: bool = false  # right mouse holds the shield up (melee weapon in hand)
var _mouse_knife: bool = false  # right mouse stabs with the knife (Bowman with the Knife upgrade)
var _mouse_bow: bool = false
var _aim_cursor: ImageTexture
var _bow_cursor: bool = false
var _mouse_bow_button: int = MOUSE_BUTTON_RIGHT
var _mouse_click_left: float = 0.0
var _last_ping_ms: Dictionary = {}  # peer -> time of their last ping (server)
var _training_switching: bool = false
var _training_welcomed: bool = false
var _bow_rain_targeting: bool = false
## Last Stand: the teammate the camera follows while the local hero is gone.
var _spectating: Player


func _ready() -> void:
	if Net.players.is_empty():
		# Scene run directly (e.g. from the editor): offline with default settings.
		Net.open_offline_lobby()
		Net.settings.seed = randi()
	var settings := Net.settings
	seed(settings.seed)
	training_mode = settings.get("training", false)
	map = MapCatalog.find(StringName(settings.get("map", &"wildlands")))
	if not map.supports(settings.mode):
		map = MapCatalog.for_mode(settings.mode)[0]
	if training_mode:
		GameConfig.world_half = 23.0
	elif map.layout:
		GameConfig.world_half = map.world_half
	else:
		GameConfig.world_half = clampf(40.0 + sqrt(float(settings.band_count)) * 10.0, 60.0, 170.0)
		if settings.mode == Net.Mode.LAST_STAND:
			GameConfig.world_half *= LAST_STAND_WORLD_SCALE
	WorldBuilder.wave_entries = map.wave_entries
	if not training_mode:
		_apply_map(map)
	GameConfig.orc_strength = Net.DIFFICULTY_STRENGTH[settings.difficulty]
	GameConfig.orc_respawn_scale = Net.DIFFICULTY_RESPAWN[settings.difficulty]
	# Downed + revive needs teammates: every online mode has them.
	GameConfig.downed_enabled = Net.is_online()
	GameConfig.blood_moon = false
	_setup_spawners()
	HitFx.world = world
	HitFx.main = self
	HitFx.camera = camera

	# Conquest runs its own rules on top of GameMode; every other mode uses GameMode as it is.
	game_mode = ConquestMode.new() if settings.mode == Net.Mode.CONQUEST else GameMode.new()
	game_mode.setup(settings, Net.players, map)
	add_child(game_mode)
	match_stats = MatchStats.new()
	add_child(match_stats)
	match_stats.awards_ready.connect(hud.show_awards)
	world_events = WorldEvents.new()
	var events := PackedStringArray() if training_mode else WorldEvents.ids_from_setting(settings.get("events", true))
	if settings.mode == Net.Mode.LAST_STAND:
		events.erase("waves")  # squads assault the circles instead of the border waves
	world_events.setup(self, game_mode, events)
	add_child(world_events)
	if training_mode:
		training_field = TRAINING_FIELD_SCENE.instantiate() as TrainingField
		world.add_child(training_field)
	else:
		var builder := WorldBuilder.new()
		builder.map = map
		builder.band_count = settings.band_count
		builder.spawn_points = game_mode.world_spawn_points()
		builder.clear_areas = game_mode.world_clear_areas()
		builder.clear_radius = game_mode.world_clear_radius()
		builder.vein_spots = game_mode.world_vein_spots()
		builder.bands_avoid_clear_areas = settings.mode != Net.Mode.LAST_STAND
		_bands = builder.build(world)
		game_mode.build_objectives(world)
	_bands_left = _bands.size()
	for band in _bands:
		band.defeated.connect(_on_band_defeated)

	hud.set_bands(_bands_left, _bands.size())
	hud.set_training_mode(training_mode)
	hud.restart_requested.connect(_restart)
	hud.main_menu_requested.connect(func() -> void: Net.leave())
	hud.pause_requested.connect(pause_menu.open)
	hud.bow_stick.aim_released.connect(_on_bow_released)
	hud.bow_stick.tapped.connect(func() -> void: _fire(Vector3.ZERO))
	hud.melee_button.tapped.connect(_melee_once)
	hud.weapon_switch_requested.connect(_switch_weapon)
	hud.dash_requested.connect(_dash)
	hud.ability_requested.connect(_use_ability)
	hud.army_command_requested.connect(_on_army_button)
	hud.ping_requested.connect(func() -> void: _ping(_ahead_point(0.0)))
	hud.set_mode_label(game_mode.score_text())
	pause_menu.online = Net.is_online()
	if training_mode:
		pause_menu.set_hint("F: choose hero   •   X: special ability   •   Attack the targets to test damage")
	pause_menu.paused.connect(_on_paused)
	game_mode.scores_changed.connect(func() -> void: hud.set_mode_label(game_mode.score_text()))
	hud.set_objective_source(game_mode)
	if not training_mode:
		hud.minimap.background = map.minimap_color
	game_mode.announced.connect(func(message: String) -> void: hud.show_toast(Net.localize(message)))
	game_mode.match_over.connect(_end)

	if not Platform.mobile_layout:
		camera.offset *= DESKTOP_CAMERA_ZOOM
		Input.set_custom_mouse_cursor(MATCH_CURSOR, Input.CURSOR_ARROW, Vector2(2, 2))
	camera.zoom = CAMERA_ZOOM
	# Look at our spawn until our player appears.
	var spawn := game_mode.spawn_point_for(Net.my_id())
	camera.global_position = spawn + camera.offset * camera.zoom
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


## The map's light: sky color, ambient, sun and (Gravemoor) a little mist. The Weather (storm, Blood Moon)
## blends from these.
func _apply_map(map_def: MapDef) -> void:
	var environment := ($WorldEnvironment as WorldEnvironment).environment.duplicate() as Environment
	environment.background_color = map_def.sky_color
	environment.ambient_light_color = map_def.ambient_color
	environment.ambient_light_energy = map_def.ambient_energy
	environment.fog_enabled = map_def.fog_density > 0.0
	if map_def.fog_density > 0.0:
		environment.fog_light_color = map_def.fog_color
		environment.fog_density = map_def.fog_density
		environment.fog_sky_affect = 0.0
	($WorldEnvironment as WorldEnvironment).environment = environment
	var sun := $Sun as DirectionalLight3D
	sun.light_color = map_def.sun_color
	sun.light_energy = map_def.sun_energy


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
			player.set_class(data.get("class", &""))
			player.training_mode = data.get("training", false)
			player.coins = data.get("start_coins", 0)
			unit = player
		&"ally":
			var ally := ALLY_SCENE.instantiate() as Ally
			ally.weapon = data.get("weapon", "sword")
			unit = ally
		&"animal":
			var animal := ANIMAL_SCENE.instantiate() as Animal
			animal.set_species(data.get("species", "pig"))
			animal.home = data.get("home", data.pos)
			unit = animal
		&"goblin":
			unit = GOBLIN_SCENE.instantiate() as TreasureGoblin
			unit.max_health *= data.get("health_scale", 1.0)
		&"enemy":
			var enemy := (load(data.scene) as PackedScene).instantiate() as Enemy
			enemy.home = data.pos
			enemy.wave_enemy = data.get("wave_enemy", false)
			enemy.wave_number = data.get("wave_number", 0)
			enemy.rising = data.get("rise", false)
			enemy.tracked = data.get("tracked", false)
			if data.has("band"):
				enemy.band = get_node_or_null(data.band) as Warband
			enemy.power = data.strength
			enemy.max_health *= data.strength
			enemy.melee_damage *= data.strength
			enemy.coin_multiplier = data.coins
			unit = enemy
			if data.get("training_orc", false):
				unit.add_to_group(&"training_orcs")
	unit.name = data.name
	unit.position = data.pos
	unit.team_id = data.get("team", GameConfig.ORC_TEAM)
	unit.owner_peer = data.get("owner", data.get("peer", 0))
	# Players and soldiers in this device's colors (you blue, teammates green, enemies red); others from the data.
	var owner_peer: int = unit.owner_peer
	unit.unit_color = Net.color_of(owner_peer) if owner_peer > 0 else data.get("color", Color(1, 1, 1, 0))
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
		projectile.check_shooter_origin = data.get("check_shooter_origin", true)
		projectile.rain_arrow = data.get("rain_arrow", false)
		if data.get("speed", 0.0) > 0.0:
			projectile.speed = data.speed
		projectile.pierce = data.get("pierce", 0)
		projectile.lifetime *= data.get("lifetime_scale", 1.0)
		node = projectile
	node.name = data.name
	return node


func _on_unit_spawned(node: Node) -> void:
	if node is Player and (node as Player).is_local():
		_bind_local_player(node)


func _spawn_player(peer: int, class_override: StringName = &"", position_override: Vector3 = Vector3.INF) -> Player:
	var spawn_position := game_mode.spawn_point_for(peer)
	if training_mode:
		spawn_position = TrainingField.SPAWN_POINT
	if position_override != Vector3.INF:
		spawn_position = position_override
	var player := NetSpawn.unit(&"player", spawn_position, {
		"peer": peer,
		"display_name": Net.name_of(peer),
		"class": class_override if class_override != &"" else Net.class_of(peer),
		"team": Net.team_of(peer),
		"start_coins": int(Net.settings.start_coins),
		"training": training_mode,
	}) as Player
	player.died.connect(_on_player_died)
	player.went_down.connect(_on_player_down)
	player.revived.connect(_on_player_revived)
	if player.is_local():
		_bind_local_player(player)
	return player


func _bind_local_player(player: Player) -> void:
	_cancel_bow_rain()
	local_player = player
	if not multiplayer.is_server():
		player.enable_prediction()  # move instantly on this device, the server corrects drift
	camera.target = player
	camera.snap()
	hud.setup(player, _bands)
	hud.set_training_mode(training_mode)
	_last_coins = player.coins
	player.coins_changed.connect(_on_local_coins_changed)
	_last_health = player.health
	player.health_changed.connect(_on_local_health_changed)
	Transition.fade_in(0.6)
	if training_mode and not _training_welcomed:
		_training_welcomed = true
		hud.show_toast("Welcome! Walk to a hero and press F to try them.", 4.5)


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
	for band in _bands:
		band.start()
	for herd in get_tree().get_nodes_in_group(&"herds"):
		(herd as AnimalHerd).start()


func _on_peer_left(peer: int) -> void:
	if not multiplayer.is_server():
		return
	for unit in get_tree().get_nodes_in_group(&"units"):
		if unit.get("owner_peer") == peer:
			unit.queue_free()
	if not _started:
		_on_world_ready(1)  # someone left while loading: start with the rest


# --- Input ---------------------------------------------------------------------
# Desktop: WASD / arrows / left stick move. The class's weapon in hand (Spearman: E / Y switch thrust <-> throw):
# left mouse swings / thrusts toward the cursor, or with a ranged weapon aims at the cursor (left or right
# mouse, release to shoot). J / RB and Space / K / RT use the weapon on the nearest enemy (ranged: at the
# right-stick direction when aiming). Touch: HUD joystick + the stick of the weapon in hand + a switch button.

func _physics_process(delta: float) -> void:
	if _game_over or local_player == null or not is_instance_valid(local_player):
		_show_bow_cursor(false)
		return
	_mouse_click_left = maxf(_mouse_click_left - delta, 0.0)
	# Sticks / WASD are screen directions: turn them with the camera (R rotates it in 90° steps).
	var move := hud.joystick.output
	var keys := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if keys != Vector2.ZERO:
		move = keys
	move = camera.to_world(move)
	var aim := Vector3.ZERO
	if hud.bow_stick.is_aiming:
		aim = _screen_to_world(hud.bow_stick.output)
	var stick := Input.get_vector(&"aim_left", &"aim_right", &"aim_up", &"aim_down")
	if stick != Vector2.ZERO:
		aim = _screen_to_world(stick)
	if _mouse_bow:
		aim = _cursor_aim()
	_show_bow_cursor(_kill_picking or (local_player.holds_ranged() and not local_player.is_dead and not local_player.is_downed))
	var melee := local_player.holds_melee()
	var melee_aim := Vector3.ZERO
	if hud.melee_button.is_aiming:
		melee_aim = _screen_to_world(hud.melee_button.output)
	if melee and (_mouse_attack or _mouse_click_left > 0.0):
		melee_aim = _cursor_direction()
	# Holding the sword button without dragging (or an attack key) keeps auto-attacking the nearest enemy;
	# with the bow in hand the same keys shoot.
	# Shield: right mouse (turns toward the cursor), LT (toward the right stick) or the touch shield button.
	var pad_block := Input.is_action_pressed(&"block") and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var block := local_player.can_block() and (_mouse_block or pad_block or hud.shield_button.is_held)
	if block and _mouse_block:
		aim = _cursor_direction()
	# Knife (Bowman with the upgrade): right mouse toward the cursor, LT / the touch button toward the aim or ahead.
	var knife_held := local_player.has_knife() and (_mouse_knife or pad_block or hud.shield_button.is_held)
	var knife_aim := _cursor_direction() if _mouse_knife else aim
	# Its fan shows under the hero while held, like the sword's wedge (no aim yet: where the hero faces).
	local_player.set_knife_aim((knife_aim if knife_aim != Vector3.ZERO else local_player.facing()) if knife_held else Vector3.ZERO)
	var use_held := (_attack_key_held() or Input.is_action_pressed(&"shoot")) and not _bow_rain_targeting
	var melee_held := melee and not block and melee_aim == Vector3.ZERO and (hud.melee_button.is_held or use_held)
	var shoot_held := not melee and use_held and not knife_held  # the knife in hand: no arrows
	if multiplayer.is_server():
		local_player.set_input(move, aim, melee_aim, block)
		if melee_held:
			local_player.attack_melee()
		if shoot_held:
			local_player.shoot(aim)
		if knife_held:
			local_player.knife_attack(knife_aim)
		return
	# Client: move / aim locally right away (prediction), send everything to the server.
	local_player.predict_input = move if not local_player.is_dead else Vector2.ZERO
	local_player.set_melee_aim(melee_aim)
	if melee_aim == Vector3.ZERO:
		if aim != Vector3.ZERO:
			local_player.set_aim(aim)
		elif local_player.is_aiming():
			local_player.clear_aim()
	if block and aim != Vector3.ZERO:
		local_player.look_override = aim.normalized()  # turn right away; the server decides the block
	local_player.net_input.rpc_id(1, move, aim, melee_aim, block)
	_melee_send_timer -= delta
	_shoot_send_timer -= delta
	if melee_held and _melee_send_timer <= 0.0:
		_melee_send_timer = ACTION_SEND_INTERVAL
		local_player.net_melee.rpc_id(1)
	if shoot_held and _shoot_send_timer <= 0.0:
		_shoot_send_timer = ACTION_SEND_INTERVAL
		local_player.net_shoot.rpc_id(1, aim)
	_knife_send_timer -= delta
	if knife_held and _knife_send_timer <= 0.0:
		_knife_send_timer = ACTION_SEND_INTERVAL
		local_player.net_knife.rpc_id(1, knife_aim)


## Mouse buttons only count when they didn't land on the HUD (pause / upgrades buttons, minimap).
func _unhandled_input(event: InputEvent) -> void:
	if _game_over or local_player == null:
		return
	var button := event as InputEventMouseButton
	var real_click := button != null and button.pressed and button.device != InputEvent.DEVICE_ID_EMULATION \
			and not Platform.mobile_layout
	if local_player.is_dead and game_mode.match_mode == Net.Mode.LAST_STAND:
		var tap := event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed
		if (real_click or tap or event.is_action_pressed(&"switch_weapon") or event.is_action_pressed(&"attack")) \
				and not event.is_echo():
			_spectate_next()
			get_viewport().set_input_as_handled()
		return
	if _bow_rain_targeting:
		if real_click:
			if button.button_index == MOUSE_BUTTON_LEFT:
				_confirm_bow_rain(_pointer_point())
			else:
				_cancel_bow_rain()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"ability") and not event.is_echo():
			_cancel_bow_rain()
			get_viewport().set_input_as_handled()
			return
		if (event.is_action_pressed(&"attack") or event.is_action_pressed(&"shoot")) and not event.is_echo():
			_confirm_bow_rain(_pointer_point())
			get_viewport().set_input_as_handled()
			return
	if _kill_picking and real_click:
		# Picking the kill target: left click orders it, any other button cancels. No swing / shot.
		_set_kill_picking(false)
		if button.button_index == MOUSE_BUTTON_LEFT:
			_command_army(Player.Order.KILL, _cursor_point())
		get_viewport().set_input_as_handled()
		return
	if real_click and button.is_action(&"block") and local_player.has_knife():
		_mouse_knife = true  # the Bowman's right mouse stabs once the knife is bought (instead of aiming)
	elif real_click and local_player.holds_ranged() and (button.is_action(&"attack") or button.is_action(&"aim_bow")):
		_mouse_bow = true
		_mouse_bow_button = button.button_index
	elif real_click and button.is_action(&"block") and local_player.can_block():
		_mouse_block = true
	elif real_click and button.is_action(&"attack"):
		_mouse_attack = true
		_mouse_click_left = MOUSE_CLICK_HOLD
	elif event.is_action_pressed(&"switch_weapon") and not event.is_echo():
		_switch_weapon()
	elif event.is_action_pressed(&"ability") and not event.is_echo():
		_use_ability()
	elif event.is_action_pressed(&"dash") and not event.is_echo():
		_dash()
	elif event.is_action_pressed(&"upgrades") and not event.is_echo():
		hud.toggle_upgrades()
	elif event.is_action_pressed(&"interact") and not event.is_echo() and training_mode:
		_interact_training()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"rotate_camera") and not event.is_echo():
		camera.rotate_step(1)
	elif event.is_action_pressed(&"ping") and not event.is_echo():
		_ping(_ahead_point(6.0) if event is InputEventJoypadButton else _pointer_point())
	elif event.is_action_pressed(&"ping_help") and not event.is_echo():
		_ping(local_player.global_position, true)
	else:
		for order in ARMY_ACTIONS.size():
			if event.is_action_pressed(ARMY_ACTIONS[order]) and not event.is_echo():
				_command_army(order, Vector3.INF if event is InputEventJoypadButton else _pointer_point())  # INF: ahead of us


## Releases are caught everywhere (also over the HUD) so buttons never stick.
func _input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or button.pressed:
		return
	if button.is_action(&"attack"):
		_mouse_attack = false
	if button.is_action(&"block"):
		_mouse_block = false
		_mouse_knife = false
	if _mouse_bow and button.button_index == _mouse_bow_button:
		_mouse_bow = false
		_fire(_cursor_aim())
		if local_player:
			local_player.clear_aim()


## Keyboard / gamepad sword button (the mouse button is handled separately, it aims at the cursor).
func _attack_key_held() -> bool:
	return Input.is_action_pressed(&"attack") and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


## Ground point under the mouse cursor (Vector3.INF if the cursor points at the sky); `height` above the
## player's feet picks a higher plane.
func _cursor_point(height: float = 0.0) -> Vector3:
	var mouse := get_viewport().get_mouse_position()
	var ground := Plane(Vector3.UP, local_player.global_position.y + height)
	var hit: Variant = ground.intersects_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
	return hit if hit != null else Vector3.INF


## Where pings / orders from the keyboard go: the cursor on desktop, in front of the player on phones.
func _pointer_point() -> Vector3:
	var point := Vector3.INF if Platform.mobile_layout else _cursor_point()
	return point if point != Vector3.INF else _ahead_point(ORDER_AHEAD)


func _ahead_point(distance: float) -> Vector3:
	return local_player.global_position + local_player.facing() * distance


## A screen-space stick direction (x right, y down) as a flat world direction for the current camera turn.
func _screen_to_world(screen: Vector2) -> Vector3:
	var flat := camera.to_world(screen)
	return Vector3(flat.x, 0.0, flat.y)


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


## Ranged aim from the mouse: the flat offset from the player to the cursor at shot height (so the arrow /
## spear flies right under the cursor and hits what it points at), or a unit direction when the cursor is
## too close to make a point (`Player.set_aim`).
func _cursor_aim() -> Vector3:
	if local_player == null or not is_instance_valid(local_player):
		return Vector3.ZERO
	var hit := _cursor_point(Player.SHOT_HEIGHT)
	if hit == Vector3.INF:
		return Vector3.ZERO
	var offset: Vector3 = hit - local_player.global_position
	offset.y = 0.0
	if offset.length() <= Player.AIM_POINT_MIN + 0.5:
		return offset.normalized() if offset.length() > 0.15 else local_player.facing()
	return offset


## X / R3 / the touch ability button: the class's special ability (when charged with XP).
func _use_ability() -> void:
	if local_player == null or _game_over or local_player.is_dead or not local_player.ability_ready():
		return
	_mouse_attack = false
	_mouse_block = false
	if local_player.class_def.ability == &"bow_rain":
		_bow_rain_targeting = true
		_mouse_bow = false
		_update_bow_rain_target()
		return
	local_player.request_ability()


func _update_bow_rain_target() -> void:
	if not _bow_rain_targeting:
		return
	if local_player == null or not local_player.ability_ready() or local_player.class_def.ability != &"bow_rain":
		_cancel_bow_rain()
		return
	local_player.set_bow_rain_preview(_pointer_point(), true)


func _confirm_bow_rain(point: Vector3) -> void:
	if not _bow_rain_targeting or local_player == null:
		return
	var target := local_player.clamp_bow_rain_point(point)
	_bow_rain_targeting = false
	local_player.set_bow_rain_preview(target, false)
	local_player.request_bow_rain(target)


func _cancel_bow_rain() -> void:
	_bow_rain_targeting = false
	if local_player and is_instance_valid(local_player):
		local_player.set_bow_rain_preview(Vector3.ZERO, false)


## C / L3 / the touch dash button (Swordsman with Dash Attack): along the movement input, else toward the
## mouse cursor, else straight ahead.
func _dash() -> void:
	if local_player == null or _game_over or not local_player.has_dash():
		return
	var move := hud.joystick.output
	var keys := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if keys != Vector2.ZERO:
		move = keys
	var direction := Vector3.ZERO
	if move.length() > 0.2:
		var world := camera.to_world(move)
		direction = Vector3(world.x, 0.0, world.y)
	elif not Platform.touch_mode:
		direction = _cursor_direction()
	local_player.request_dash(direction)


## E / Y / the HUD switch button: next weapon in hand (drops any aim in progress).
func _switch_weapon() -> void:
	if local_player == null or _game_over or local_player.is_dead:
		return
	_mouse_bow = false
	_mouse_attack = false
	_mouse_block = false
	_cancel_bow_rain()
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
	if _bow_rain_targeting and local_player:
		var direction := _screen_to_world(aim).normalized()
		_confirm_bow_rain(local_player.global_position + direction * Player.BOW_RAIN_RANGE)
		return
	_fire(_screen_to_world(aim))
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
	_cancel_bow_rain()
	hud.reset_touch_controls()
	_mouse_attack = false
	_mouse_bow = false
	_mouse_knife = false
	_mouse_click_left = 0.0
	if local_player:
		local_player.clear_aim()
		local_player.set_melee_aim(Vector3.ZERO)
		if multiplayer.is_server():
			local_player.set_input(Vector2.ZERO, Vector3.ZERO)


# --- Per-frame ---------------------------------------------------------------------

func _process(delta: float) -> void:
	_vibrate_cooldown -= delta
	_update_bow_rain_target()
	_update_respawn_display(delta)
	_update_spectating()
	_update_camera_zoom()
	_update_kill_mark()
	if training_mode and training_field:
		if is_instance_valid(local_player):
			training_field.update_player(local_player)
		else:
			training_field.hide_prompt()


## Training only: replace the local hero at the same spot with the class beside them.
func _switch_training_class() -> void:
	if _training_switching or not training_field or not is_instance_valid(local_player):
		return
	var class_id := training_field.selected_class_id()
	if class_id == &"":
		return
	if local_player.class_def.id == class_id:
		hud.show_toast("You are already training as %s." % local_player.class_def.display_name)
		return
	_training_switching = true
	var at := local_player.global_position
	var old := local_player
	local_player = null
	training_field.hide_prompt()
	Net.set_class(class_id)
	Net.players[Net.my_id()]["class"] = class_id
	old.queue_free()
	await get_tree().process_frame
	var replacement := _spawn_player(Net.my_id(), class_id, at)
	if replacement:
		replacement.face_now(Vector3.FORWARD)
		hud.show_toast("Now training as %s — abilities are unlimited." % replacement.class_def.display_name, 3.5)
	_training_switching = false


## F near a class pedestal switches hero; F near the orc station spawns one live orc.
func _interact_training() -> void:
	if not training_field or not is_instance_valid(local_player) or local_player.is_dead:
		return
	if training_field.is_near_orc_station(local_player.global_position):
		if training_field.spawn_orc(local_player) == null:
			hud.show_toast("Orc practice is full. Defeat an orc to spawn another.")
		return
	_switch_training_class()


## Default zoom + a bit more with the bow / spear in hand; with the bow, Fire Range zooms out further
## (in step with the longer range, `RANGE_CAMERA_ZOOM` of it), so you see as far as you shoot.
func _update_camera_zoom() -> void:
	var extra := 0.0
	var range_scale := 1.0
	if is_instance_valid(local_player):
		extra = WEAPON_CAMERA_ZOOM.get(local_player.current_weapon(), 0.0)
		if local_player.current_weapon() == "bow":
			range_scale = 1.0 + RANGE_CAMERA_ZOOM * (local_player.aim_range_scale() - 1.0)
	camera.zoom = (CAMERA_ZOOM + extra) * range_scale


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


## Last Stand: while our hero is gone, the camera follows a teammate who is still in the match.
func _update_spectating() -> void:
	if game_mode.match_mode != Net.Mode.LAST_STAND or not is_instance_valid(local_player) or _game_over:
		return
	if not local_player.is_dead:
		return
	if not is_instance_valid(_spectating) or _spectating.is_dead:
		_spectate_next()
	hud.show_spectating(_spectating.display_name if is_instance_valid(_spectating) else "")


## Follow the next teammate still in the match (wraps around).
func _spectate_next() -> void:
	var candidates: Array[Player] = []
	for node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != local_player and not player.is_dead:
			candidates.append(player)
	if candidates.is_empty():
		_spectating = null
		return
	candidates.sort_custom(func(a: Player, b: Player) -> bool: return a.peer_id < b.peer_id)
	var at := candidates.find(_spectating)
	_spectating = candidates[(at + 1) % candidates.size()]
	camera.target = _spectating


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

## HUD army buttons. Kill with a mouse: wait for a click on the enemy; on touch / gamepad: the enemy ahead.
func _on_army_button(order: int) -> void:
	if order == Player.Order.KILL and not Platform.touch_mode and not Platform.mobile_layout:
		_set_kill_picking(not _kill_picking)
		return
	_command_army(order)


func _set_kill_picking(on: bool) -> void:
	_kill_picking = on
	hud.set_kill_picking(on)
	if on:
		hud.show_toast("Click an enemy to kill")


## `point`: the cursor (keys / clicks) or INF = in front of the player (gamepad / touch buttons).
## KILL takes the enemy under the cursor (or ahead); with none there it becomes a CHARGE to the point.
func _command_army(order: int, point: Vector3 = Vector3.INF) -> void:
	if local_player == null or _game_over:
		return
	if _kill_picking and order != Player.Order.KILL:
		_set_kill_picking(false)
	var from_cursor := point != Vector3.INF
	if point == Vector3.INF:
		point = _ahead_point(ORDER_AHEAD)
	if order == Player.Order.KILL:
		var prey := _kill_pick() if from_cursor and not Platform.mobile_layout else \
				local_player.kill_target_near(_ahead_point(KILL_AHEAD), KILL_AHEAD_RADIUS)
		if prey:
			point = prey.global_position  # the server takes the enemy standing here
		else:
			order = Player.Order.CHARGE
	if multiplayer.is_server():
		local_player.command_army(order, point)
	else:
		local_player.net_command.rpc_id(1, order, point)
	var shout: String = ARMY_SHOUTS[order]
	FloatingText3D.spawn(world, local_player.global_position + Vector3(0, 2.1, 0), shout, Color(1.0, 0.95, 0.8), 52)
	if order == Player.Order.CHARGE or order == Player.Order.HOLD:
		PingMarker.spawn(world, point, shout, local_player.unit_color if local_player.unit_color.a > 0.0 else Color.WHITE,
				local_player.display_name)


## The hostile unit drawn nearest the mouse cursor (models stand up, so compare on screen).
func _kill_pick() -> Node3D:
	var mouse := get_viewport().get_mouse_position()
	var best: Node3D = null
	var best_px := KILL_PICK_PIXELS * get_viewport().get_visible_rect().size.y / 1080.0
	for group in Player.KILL_GROUPS:
		for node in get_tree().get_nodes_in_group(group):
			var candidate := node as Node3D
			if candidate == null or GameConfig.is_gone(candidate) or not GameConfig.is_hostile(local_player, candidate) \
					or not candidate.is_visible_in_tree():
				continue
			var center := candidate.global_position + Vector3(0, 0.6, 0)
			if camera.is_position_behind(center):
				continue
			var px := camera.unproject_position(center).distance_to(mouse)
			px = maxf(px - maxf(Unit.target_radius(candidate) - 0.4, 0.0) * 40.0, 0.0)  # big ones: anywhere over them
			if px < best_px:
				best_px = px
				best = candidate
	return best


## Local player's KILL order: a red target mark bobs over the enemy being hunted.
func _update_kill_mark() -> void:
	var prey: Node3D = null
	if is_instance_valid(local_player) and local_player.army_order == Player.Order.KILL \
			and not local_player.army_target_path.is_empty():
		prey = get_node_or_null(local_player.army_target_path) as Node3D
	if prey == null or GameConfig.is_gone(prey):
		if _kill_mark:
			_kill_mark.visible = false
		return
	if _kill_mark == null:
		_kill_mark = Sprite3D.new()
		_kill_mark.texture = KILL_MARK_TEXTURE
		_kill_mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_kill_mark.no_depth_test = true
		_kill_mark.pixel_size = 0.004
		_kill_mark.modulate = Color(1.0, 0.3, 0.25)
		world.add_child(_kill_mark)
	var bar: Variant = prey.get("health_bar_height")
	var height: float = (bar if bar is float else 1.3) + 0.6  # just over the health bar
	_kill_mark.visible = true
	_kill_mark.global_position = prey.global_position + Vector3(0, height + 0.15 * sin(Time.get_ticks_msec() * 0.006), 0)


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
	for group in [&"active_enemies", &"players", &"allies"]:
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
	if game_mode.match_mode == Net.Mode.LAST_STAND:
		game_mode.on_player_fell(player)  # gone for good: spectates until the match ends
		return
	if game_mode.uses_respawn():
		game_mode.on_player_died(player)
		get_tree().create_timer(game_mode.respawn_time()).timeout.connect(func() -> void:
			if is_instance_valid(player) and not game_mode.is_over:
				player.revive(game_mode.spawn_point_for(player.peer_id)))
	else:
		await get_tree().create_timer(1.2).timeout
		game_mode.finish("You fell", "The orcs hold the land... for now.")


## Our own hits on other devices: the server sends the damage number here.
@rpc("authority", "call_local", "reliable")
func _net_rain_impact(at: Vector3, normal: Vector3, damageable: bool) -> void:
	HitFx.rain_impact(at, normal, damageable)


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


## PC: a crosshair while the bow is in hand, the gold sword otherwise.
func _show_bow_cursor(aiming: bool) -> void:
	if aiming == _bow_cursor or Platform.mobile_layout:
		return
	_bow_cursor = aiming
	if aiming:
		if _aim_cursor == null:
			_aim_cursor = AimCursor.make()
		Input.set_custom_mouse_cursor(_aim_cursor, Input.CURSOR_ARROW, _aim_cursor.get_size() * 0.5)
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


func _on_band_defeated(band: Warband) -> void:
	_bands_left -= 1
	hud.set_bands(_bands_left, _bands.size())
	var what := "an undead horde" if band.faction == &"undead" else "an orc warband"
	if band.defeated_by() == Net.my_id():
		hud.show_toast("You wiped out %s!" % what)
	elif Net.is_online() and band.defeated_by() != 0:
		hud.show_toast("%s wiped out %s" % [Net.name_of(band.defeated_by()), what])
	if multiplayer.is_server() and game_mode.match_mode == Net.Mode.COOP and _bands_left <= 0:
		game_mode.finish("Victory!", "Every warband has been wiped out.")


func _end(title: String, subtitle: String) -> void:
	if _game_over:
		return
	_game_over = true
	match_stats.publish_awards(game_mode.player_names())
	pause_menu.can_pause = false
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
