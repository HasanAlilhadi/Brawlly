class_name DevPanel
extends PanelContainer
## Developer panel (the HUD's DEV button / F3, action `dev_panel`): what the game is doing right now, refreshed
## four times a second — frame time (and the worst frame of the last seconds), how many units / monsters are awake,
## and, in Conquest, where you are (zone, the nearest place: its holder, garrison, gate) and what the demons are up
## to (campaigns, the King's rally, raids), and what the commanders' mind (BattleBrain) costs. On the host (or
## offline) it also has a few tools: god mode, coins, kill the monsters around you, go to the place selected on the
## M map, an AI level-of-detail switch.
## Built in code; main.gd makes it in the HUD.

const REFRESH: float = 0.25
const WORST_WINDOW: float = 5.0
const KILL_RANGE: float = 30.0

var _main: Node
var _text: Label
var _tools: VBoxContainer
var _god_button: Button
var _refresh: float = 0.0
var _worst: float = 0.0
var _worst_age: float = 0.0
var _frames: int = 0
var _frame_sum: float = 0.0
var god: bool = false


func setup(main: Node) -> void:
	_main = main


func _ready() -> void:
	name = "DevPanel"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme_type_variation = &"PanelCompact"
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	var title := MenuKit.label("DEV", &"LabelLight", HudStyle.FONT_TITLE)
	column.add_child(title)
	_text = MenuKit.label("", &"LabelLight", HudStyle.FONT_SMALL)
	_text.name = "DevText"
	column.add_child(_text)
	_tools = VBoxContainer.new()
	_tools.add_theme_constant_override("separation", 4)
	column.add_child(_tools)
	_god_button = _tool("God mode: off", _toggle_god)
	_tool("+1000 coins", func() -> void:
		var me := _hero()
		if me:
			me.coins += 1000)
	_tool("Kill monsters near (%d m)" % KILL_RANGE, _kill_near)
	_tool("Go to the place picked on the map", _go_to_selected)
	_tool("AI level of detail: on", _toggle_lod)
	_tool("Animation level of detail: on", _toggle_anim_lod)


func _tool(text: String, action: Callable) -> Button:
	var button := MenuKit.button(text, false, Vector2(360.0, 40.0))
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", HudStyle.FONT_SMALL)
	button.pressed.connect(action)
	_tools.add_child(button)
	return button


func toggle() -> void:
	visible = not visible
	_tools.visible = multiplayer.is_server()  # tools change the game: the host's only
	if visible:
		_update()


func _process(delta: float) -> void:
	var ms := delta * 1000.0
	_worst_age += delta
	if ms > _worst or _worst_age > WORST_WINDOW:
		_worst = ms
		_worst_age = 0.0
	_frames += 1
	_frame_sum += ms
	if god and multiplayer.is_server():
		var me := _hero()
		if me and not me.is_dead:
			me.health = me.max_health
	if not visible:
		return
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = REFRESH
		_update()
		reset_size()
		position = Vector2(get_viewport_rect().size.x - size.x - HudStyle.GAP * 2.0 - HudStyle.COLUMN_WIDTH, HudStyle.GAP * 2.0)


func _update() -> void:
	var tree := get_tree()
	var lines := PackedStringArray()
	var avg := _frame_sum / maxf(_frames, 1)
	_frames = 0
	_frame_sum = 0.0
	lines.append("FPS %d · frame %.1f ms (worst %.0f) · scripts %.1f + physics %.1f ms" % [
			Engine.get_frames_per_second(), avg, _worst,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
	var awake := 0
	var bands := tree.get_nodes_in_group(&"warbands")
	for band in bands:
		if band.get("_active"):
			awake += 1
	lines.append("Monsters %d (awake %d) · soldiers %d · bands awake %d/%d · nodes %d" % [
			tree.get_nodes_in_group(&"enemies").size(), tree.get_nodes_in_group(&"active_enemies").size(),
			tree.get_nodes_in_group(&"allies").size(), awake, bands.size(),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	lines.append("Draw calls %d · objects drawn %d" % [
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	var brain := _main.get("battle_brain") as BattleBrain if _main else null
	if brain and multiplayer.is_server():
		# The commanders' mind: who fights whom, worked out for everybody on a worker thread.
		lines.append("Commanders: %d units, %d take orders · %.1f ms on a worker thread · %.1f ms here · %d a second" % [
				brain.last_rows, brain.last_asking, brain.last_thread_ms, brain.last_main_ms,
				roundi(float(Engine.physics_ticks_per_second) / BattleBrain.CYCLE_FRAMES)])
	var me := _hero()
	var mode := _main.get("game_mode") as ConquestMode if _main else null
	if me and mode:
		lines.append("")
		var at := me.global_position
		lines.append("You: (%d, %d) · zone %d · army %d/%d" % [at.x, at.z, ConquestMode.zone_of(at), me.army_size(),
				me.follower_cap])
		var place := _nearest_place(mode, at)
		if place:
			var guards: Array = place.get("_guards")
			var alive := guards.filter(func(g: Node) -> bool: return not GameConfig.is_gone(g)).size() if guards else 0
			lines.append("Nearest: %s (%s, zone %d) · %s · %d m" % [place.display_name, place.kind_name(), place.zone,
					["demons", "free", "held"][place.state] if place.state < 3 else "?",
					roundi(Vector2(place.position.x - at.x, place.position.z - at.z).length())])
			var garrison := "not risen" if not place.get("_guards_spawned") else (
					"%d alive, %s" % [alive, "awake" if place.get("_guards_awake") else "asleep"])
			lines.append("  garrison: %s%s" % [garrison, ("" if place.gate == null else " · gate %d/%d %s" % [
					place.gate.health, place.gate.max_health,
					"broken" if place.gate.is_broken() else ("shut" if place.gate.shut else "open")])])
			if place.state == TerritoryNode.State.OWNED:
				lines.append("  store: food %d, weapons %d · people %d · training %s" % [place.store[&"food"],
						place.store[&"equipment"], place.people,
						TerritoryNode.SOLDIER_NAMES[place.train_kind] if place.train_kind >= 0 else "nothing"])
		if mode.demons and multiplayer.is_server():
			lines.append("Demons: %d campaigns · %s · lieutenants left %d" % [mode.demons.campaigns.size(),
					"RALLYING to the King" if mode.demons.rallying else "the King is calm",
					mode.demons.living_lieutenants().size()])
		if mode.logistics:
			lines.append("Next supply tick in %.1f s" % mode.logistics.time_to_tick())
	_text.text = "\n".join(lines)
	_god_button.text = "God mode: %s" % ("on" if god else "off")


func _nearest_place(mode: ConquestMode, at: Vector3) -> TerritoryNode:
	var best: TerritoryNode = null
	var best_d := INF
	for place in mode.territories:
		var d := Vector2(place.position.x - at.x, place.position.z - at.z).length()
		if d < best_d:
			best_d = d
			best = place
	return best


func _hero() -> Player:
	return _main.get("local_player") as Player if _main else null


func _toggle_god() -> void:
	god = not god
	_update()


func _kill_near() -> void:
	var me := _hero()
	if me == null or not multiplayer.is_server():
		return
	for node in get_tree().get_nodes_in_group(&"active_enemies"):
		var enemy := node as Enemy
		if enemy and not GameConfig.is_gone(enemy) and enemy.flat_distance_to(me) < KILL_RANGE:
			enemy.routed = true  # no getting back up
			enemy.die()


func _go_to_selected() -> void:
	var me := _hero()
	var map := _main.get("conquest_map") as ConquestMap if _main else null
	if me == null or map == null or map.get("_selected") == null:
		return
	var place := map.get("_selected") as TerritoryNode
	var spot := place.position + Vector3(0.0, 0.0, place.radius() + 3.0)
	me.global_position = spot
	me.net_position = spot


func _toggle_anim_lod() -> void:
	var lod := _main.get("animation_lod") as AnimationLod if _main else null
	if lod:
		lod.enabled = not lod.enabled
		(_tools.get_child(5) as Button).text = "Animation level of detail: %s" % ("on" if lod.enabled else "off")


func _toggle_lod() -> void:
	Enemy.lod_enabled = not Enemy.lod_enabled
	(_tools.get_child(4) as Button).text = "AI level of detail: %s" % ("on" if Enemy.lod_enabled else "off")
