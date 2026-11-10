class_name ConquestMap
extends Control
## Conquest: the big map (M). The whole land, north up: the zone rings, every place in its holder's color (demons
## dark red, free places grey; bigger dots for bigger places, a gold ring around the ones you lord), your faction's
## supply routes (arrows) and couriers on the road, and you. Click a place for its card: kind, zone, holder, lord,
## its store / treasury / barracks / couriers and route. Places of your faction you lord (or any, as the General;
## or nobody's lord yet) take orders from the card: take its gold, its barracks (people waiting unarmed, then a row
## per class: armed / rank, "Train" = arm its people with that class, "Take" = a squad of that class, of the size
## picked above — 4 or 8, ConquestSquads.SIZES), send its goods to another place of yours (then click that place) or
## to your army, stop sending, buy a courier (LogisticsManager.COURIER_COST coins). Orders go to the server through
## `Player.request_place_action`. Your faction's squads are shields on the map (the soldiers in it inside; yours
## outlined white, a line to where it goes); click one for its card: send it to a place (then click the place), hold
## a point (then click the map) or have it join your army (`Player.request_squad_action`).
## A place of yours shows two pages on its card (the tabs under its numbers): Training (its barracks) and Upgrades
## (TerritoryNode.UPGRADES: Walls / Workshops / Barracks / Storehouse, three levels each, paid from its treasury).
## Zoom: mouse wheel (toward the cursor), drag to pan, the + / − / Fit buttons; zoomed in, places show their names.
## The map is drawn in a clipping child (`_canvas`, the map square); `_to_map` / `_from_map` go between the world and
## that square through `_zoom` and `_view` (the world point at its middle).
## Built in code; the numbers come from the places (LogisticsManager `_net_stock` sends them to every peer).

const BACKGROUND := Color(0.06, 0.07, 0.06, 0.82)
const LAND := Color(0.18, 0.3, 0.16)
const ZONE_LINE := Color(1, 1, 1, 0.16)
const DEMON_COLOR := Color(0.55, 0.1, 0.1)
const FREE_COLOR := Color(0.78, 0.78, 0.78)
const LORD_RING := Color(1.0, 0.82, 0.3)
const ROUTE_COLOR := Color(1.0, 0.86, 0.45, 0.9)
const COURIER_COLOR := Color(0.85, 0.62, 0.35)
const SQUAD_LINE := Color(1, 1, 1, 0.5)
## The card's place orders and squad orders (one set shows at a time).
const PLACE_BUTTONS: Array[StringName] = [&"withdraw", &"pick_route", &"route_army", &"route_stop", &"courier"]
const SQUAD_BUTTONS: Array[StringName] = [&"squad_go", &"squad_hold", &"squad_join"]
const OUTLINE := Color(0, 0, 0, 0.8)
## Dot radius per TerritoryNode.Kind (px on a 900 px map).
const DOT: Array[float] = [4.0, 5.0, 7.0, 10.0, 12.0]
const PANEL_WIDTH: float = 430.0
const MARGIN: float = 40.0
const ZOOM_MAX: float = 6.0
const ZOOM_STEP: float = 1.25
## Zoomed in at least this much, places show their names.
const NAMES_ZOOM: float = 2.0
## A press that moves farther than this (px) pans the map instead of clicking.
const DRAG_PX: float = 6.0

var _main: Node
var _mode: ConquestMode
var _selected: TerritoryNode
## Waiting for a click on the map: &"route" (the place the selected one's goods go to), &"squad_go" (the place
## the selected squad goes to), &"squad_hold" (the point it holds); &"" = not waiting.
var _picking: StringName = &""
## The selected squad (ConquestSquads id; 0 = the selected place's card shows) and the size Take sends.
var _squad: int = 0
var _size_index: int = 0
var _size_buttons: Array[Button] = []
var _map_rect := Rect2()
var _refresh: float = 0.0
var _canvas: Control
var _zoom: float = 1.0
var _view := Vector2.ZERO
var _press := Vector2.INF
var _dragged: bool = false
var _zoom_box: HBoxContainer

var _panel: PanelContainer
var _title: Label
var _info: Label
var _hint: Label
var _buttons: Dictionary = {}
var _barracks_box: VBoxContainer
var _people: Label
## Per class (TerritoryNode.SOLDIER_KINDS order): {label, train, take}.
var _class_rows: Array[Dictionary] = []
## The card's page for a place of yours: 0 = Training, 1 = Upgrades.
var _page: int = 0
var _page_tabs: HBoxContainer
var _page_buttons: Array[Button] = []
var _upgrades_box: VBoxContainer
## Per upgrade (TerritoryNode.UPGRADES order): {label, buy}.
var _upgrade_rows: Array[Dictionary] = []


func setup(main: Node, mode: ConquestMode) -> void:
	_main = main
	_mode = mode


func _ready() -> void:
	name = "ConquestMap"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_canvas = Control.new()
	_canvas.name = "Canvas"
	_canvas.clip_contents = true
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_map)
	add_child(_canvas)
	_zoom_box = HBoxContainer.new()
	_zoom_box.add_theme_constant_override("separation", 6)
	add_child(_zoom_box)
	for row in [["ZoomIn", "+", ZOOM_STEP], ["ZoomOut", "−", 1.0 / ZOOM_STEP], ["ZoomFit", "Fit", 0.0]]:
		var zoom := MenuKit.button(row[1], false, Vector2(64.0 if row[2] == 0.0 else 48.0, 44.0))
		zoom.name = row[0]
		zoom.focus_mode = Control.FOCUS_NONE
		zoom.add_theme_font_size_override("font_size", HudStyle.FONT_BUTTON)
		zoom.pressed.connect(_on_zoom.bind(float(row[2])))
		_zoom_box.add_child(zoom)
	var close := MenuKit.button("Close (M)", true, Vector2(150.0, 44.0))
	close.name = "CloseMap"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", HudStyle.FONT_BUTTON)
	close.pressed.connect(toggle)
	_zoom_box.add_child(close)
	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"PanelLight"
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)
	_title = MenuKit.label("", &"HeaderLabel")
	box.add_child(_title)
	_info = MenuKit.label("", &"", HudStyle.FONT_BODY)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_info)
	_build_pages(box)
	_build_barracks(box)
	_build_upgrades(box)
	for row in [[&"withdraw", "Take gold"], [&"pick_route", "Send goods to…"],
			[&"route_army", "Send goods to my army"], [&"route_stop", "Stop sending"], [&"courier", "Buy courier"],
			[&"squad_go", "Send to a place…"], [&"squad_hold", "Hold a point…"], [&"squad_join", "Join my army"]]:
		var button := MenuKit.button(row[1], false, Vector2(PANEL_WIDTH - 40.0, 38.0))
		button.add_theme_font_size_override("font_size", HudStyle.FONT_BUTTON)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_button.bind(row[0]))
		box.add_child(button)
		_buttons[row[0]] = button
	_hint = MenuKit.label("", &"HintLabel", HudStyle.FONT_SMALL)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_hint)
	resized.connect(_layout)
	_layout()


## Training | Upgrades: which page of a place of yours the card shows.
func _build_pages(box: VBoxContainer) -> void:
	_page_tabs = HBoxContainer.new()
	_page_tabs.add_theme_constant_override("separation", 6)
	box.add_child(_page_tabs)
	for i in 2:
		var tab := MenuKit.button(["Training", "Upgrades"][i], false, Vector2(150.0, 38.0))
		tab.name = ["TrainingPage", "UpgradesPage"][i]
		tab.theme_type_variation = &"ButtonTab"
		tab.toggle_mode = true
		tab.focus_mode = Control.FOCUS_NONE
		tab.add_theme_font_size_override("font_size", HudStyle.FONT_SMALL)
		tab.pressed.connect(func() -> void:
			_page = i
			_update_panel())
		_page_tabs.add_child(tab)
		_page_buttons.append(tab)


## The upgrades page: one row per upgrade — its level, what a level does, and Upgrade (gold from the treasury).
func _build_upgrades(box: VBoxContainer) -> void:
	_upgrades_box = VBoxContainer.new()
	_upgrades_box.add_theme_constant_override("separation", 6)
	box.add_child(_upgrades_box)
	for i in TerritoryNode.UPGRADES.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_upgrades_box.add_child(row)
		var label := MenuKit.label("", &"", HudStyle.FONT_SMALL)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		var buy := MenuKit.button("Upgrade", false, Vector2(150.0, 38.0))
		buy.name = "Upgrade_%s" % TerritoryNode.UPGRADES[i][0]
		buy.focus_mode = Control.FOCUS_NONE
		buy.add_theme_font_size_override("font_size", HudStyle.FONT_SMALL)
		buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		buy.pressed.connect(func() -> void:
			if _selected:
				_order(&"upgrade", i)
				_update_panel())
		row.add_child(buy)
		_upgrade_rows.append({"label": label, "buy": buy})


## The upgrades page of a place of yours: level / top, what the next level does, its price (from the treasury).
func _update_upgrades(place: TerritoryNode, commands: bool) -> void:
	for i in _upgrade_rows.size():
		var row: Dictionary = _upgrade_rows[i]
		var fits := place.can_upgrade(i) or place.upgrades[i] >= TerritoryNode.UPGRADE_MAX
		if i == TerritoryNode.UP_WALLS and place.gate == null or i == TerritoryNode.UP_BARRACKS and not place.has_barracks():
			fits = false
		(row.label as Label).get_parent().visible = fits
		var level := place.upgrades[i]
		(row.label as Label).text = "%s %d/%d · %s" % [TerritoryNode.UPGRADES[i][1], level, TerritoryNode.UPGRADE_MAX,
				TerritoryNode.UPGRADES[i][2]]
		var buy := row.buy as Button
		buy.visible = commands
		if level >= TerritoryNode.UPGRADE_MAX:
			buy.text = "Done"
			buy.disabled = true
		else:
			var cost := place.upgrade_cost(i)
			buy.text = "Upgrade %d" % cost
			buy.disabled = place.treasury < cost
			buy.tooltip_text = "%d gold from its treasury (%d there)" % [cost, place.treasury]


## The barracks part of the card: people, then one row per soldier class.
func _build_barracks(box: VBoxContainer) -> void:
	_barracks_box = VBoxContainer.new()
	_barracks_box.add_theme_constant_override("separation", 6)
	box.add_child(_barracks_box)
	_people = MenuKit.label("", &"", HudStyle.FONT_BODY)
	_people.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_barracks_box.add_child(_people)
	var sizes := HBoxContainer.new()
	sizes.add_theme_constant_override("separation", 6)
	_barracks_box.add_child(sizes)
	for i in ConquestSquads.SIZES.size():
		var pick := MenuKit.button("Squad of %d" % ConquestSquads.SIZES[i], false, Vector2(150.0, 38.0))
		pick.name = "SquadSize_%d" % ConquestSquads.SIZES[i]
		pick.theme_type_variation = &"ButtonTab"
		pick.toggle_mode = true
		pick.focus_mode = Control.FOCUS_NONE
		pick.add_theme_font_size_override("font_size", HudStyle.FONT_SMALL)
		pick.pressed.connect(_on_size.bind(i))
		sizes.add_child(pick)
		_size_buttons.append(pick)
	for k in TerritoryNode.SOLDIER_KINDS.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_barracks_box.add_child(row)
		var label := MenuKit.label("", &"", HudStyle.FONT_SMALL)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		row.add_child(label)
		var train := MenuKit.button("Train", false, Vector2(96.0, 38.0))
		train.name = "Train_%s" % TerritoryNode.SOLDIER_KINDS[k]
		train.theme_type_variation = &"ButtonTab"
		train.toggle_mode = true
		train.focus_mode = Control.FOCUS_NONE
		train.add_theme_font_size_override("font_size", HudStyle.FONT_SMALL)
		train.pressed.connect(_on_train.bind(k))
		row.add_child(train)
		var take := MenuKit.button("Take", false, Vector2(96.0, 38.0))
		take.name = "Take_%s" % TerritoryNode.SOLDIER_KINDS[k]
		take.focus_mode = Control.FOCUS_NONE
		take.add_theme_font_size_override("font_size", HudStyle.FONT_SMALL)
		take.pressed.connect(_on_take.bind(k))
		row.add_child(take)
		_class_rows.append({"label": label, "train": train, "take": take})


func is_open() -> bool:
	return visible


func toggle() -> void:
	visible = not visible
	_picking = &""
	if visible:
		if _selected == null:
			_selected = _place_of_hero()
		var me := _hero()
		if me and _zoom > 1.0:
			_view = Vector2(me.global_position.x, me.global_position.z)  # zoomed in: open on yourself
			_clamp_view()
		_layout()
		_update_panel()


func _layout() -> void:
	var view := get_viewport_rect().size
	if size != view:
		position = Vector2.ZERO
		size = view  # a Control under the HUD's CanvasLayer: anchors alone left it at its first (empty) size
	var side := maxf(minf(view.y - MARGIN * 2.0, view.x - PANEL_WIDTH - MARGIN * 3.0), 200.0)
	var left := maxf((view.x - side - PANEL_WIDTH - MARGIN) * 0.5, MARGIN)
	_map_rect = Rect2(Vector2(left, (view.y - side) * 0.5), Vector2(side, side))
	if _canvas:
		_canvas.position = _map_rect.position
		_canvas.size = _map_rect.size
		_zoom_box.reset_size()
		_zoom_box.position = Vector2(_map_rect.end.x - _zoom_box.size.x - 8.0, _map_rect.position.y + 8.0)
	if _panel:
		_panel.position = Vector2(_map_rect.end.x + MARGIN, _map_rect.position.y)
		_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
		_panel.size = Vector2(PANEL_WIDTH, 0.0)


func _process(delta: float) -> void:
	if not visible:
		return
	if size != get_viewport_rect().size:
		_layout()
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.25
		_update_panel()
		_redraw()


## Esc closes the map before anything else sees it (the pause menu would open under it otherwise).
## M too while it is open (main.gd's M handling waits for a living hero; the map must close anyway).
func _input(event: InputEvent) -> void:
	if not visible or event.is_echo():
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause") or event.is_action_pressed(&"map"):
		toggle()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion and _press != Vector2.INF:
		if _dragged or motion.position.distance_to(_press) > DRAG_PX:
			_dragged = true
			var half := maxf(GameConfig.world_half, 1.0) / _zoom
			_view -= motion.relative / _map_rect.size * 2.0 * half
			_clamp_view()
			_redraw()
		accept_event()
		return
	var click := event as InputEventMouseButton
	if click == null or click.device == InputEvent.DEVICE_ID_EMULATION:
		return
	accept_event()
	if click.pressed and (click.button_index == MOUSE_BUTTON_WHEEL_UP or click.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		if _map_rect.has_point(click.position):
			_zoom_at(click.position - _map_rect.position,
					ZOOM_STEP if click.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP)
		return
	if click.button_index == MOUSE_BUTTON_LEFT:
		if click.pressed:
			_press = click.position  # a click on release, unless it turned into a drag
			_dragged = false
			return
		var was_drag := _dragged
		_press = Vector2.INF
		_dragged = false
		if was_drag:
			return
	elif not click.pressed:
		return
	if click.button_index != MOUSE_BUTTON_LEFT:
		_picking = &""
		_update_panel()
		return
	_click(click.position)


## A click (left button let go without dragging) at `screen` (this control's own position).
func _click(screen: Vector2) -> void:
	var local := screen - _map_rect.position
	var place := _place_at(local)
	var picking := _picking
	_picking = &""
	match picking:
		&"route":
			if place and _selected and place != _selected and place.owner_team == _my_team():
				_order(&"route", place.index)
		&"squad_go":
			if place:
				_squad_order(&"go", place.index, Vector3.ZERO)
		&"squad_hold":
			if _map_rect.has_point(screen):
				_squad_order(&"hold", -1, _from_map(local))
		_:
			var squad := _squad_at(local)
			if squad:
				_squad = squad
			elif place:
				_selected = place
				_squad = 0
	_update_panel()
	_redraw()


func _redraw() -> void:
	queue_redraw()
	if _canvas:
		_canvas.queue_redraw()


# --- Zoom ---------------------------------------------------------------------------------

## + / − (`factor`) around the middle of the map; 0 = the whole land again.
func _on_zoom(factor: float) -> void:
	if factor <= 0.0:
		_zoom = 1.0
		_view = Vector2.ZERO
		_redraw()
		return
	_zoom_at(_map_rect.size * 0.5, factor)


## Zooms by `factor` keeping the world point under `local` (a spot of the map square) where it is.
func _zoom_at(local: Vector2, factor: float) -> void:
	var under := _from_map(local)
	_zoom = clampf(_zoom * factor, 1.0, ZOOM_MAX)
	var half := maxf(GameConfig.world_half, 1.0) / _zoom
	var share := local / _map_rect.size - Vector2(0.5, 0.5)
	_view = Vector2(under.x, under.z) - share * 2.0 * half
	_clamp_view()
	_redraw()


## The view never shows past the edge of the land.
func _clamp_view() -> void:
	var half := maxf(GameConfig.world_half, 1.0)
	var room := half - half / _zoom
	_view = _view.clamp(Vector2(-room, -room), Vector2(room, room))


# --- Map drawing -------------------------------------------------------------------------

## A world point on the map square (`_canvas`'s own coordinates).
func _to_map(point: Vector3) -> Vector2:
	var half := maxf(GameConfig.world_half, 1.0) / _zoom
	var share := (Vector2(point.x, point.z) - _view) / half * 0.5 + Vector2(0.5, 0.5)
	return share * _map_rect.size


## The flat world point under a spot of the map square.
func _from_map(local: Vector2) -> Vector3:
	var half := maxf(GameConfig.world_half, 1.0) / _zoom
	var share := local / _map_rect.size - Vector2(0.5, 0.5)
	var at := _view + share * 2.0 * half
	return Vector3(at.x, 0.0, at.y)


## Size of dots and lines: with the map's size, a little bigger zoomed in.
func _scale() -> float:
	return _map_rect.size.x / 900.0 * sqrt(_zoom)


func _draw() -> void:
	if _mode == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	draw_rect(_map_rect, OUTLINE, false, 3.0)
	var prompt := ""
	match _picking:
		&"route":
			prompt = "Click a place of yours to send the goods to (right click: cancel)"
		&"squad_go":
			prompt = "Click the place the squad goes to (right click: cancel)"
		&"squad_hold":
			prompt = "Click the point the squad holds (right click: cancel)"
	if prompt == "":
		prompt = "M / Esc: close · wheel / + −: zoom · drag: move"
	if prompt != "":
		draw_string(get_theme_default_font(), _map_rect.position + Vector2(0, -12), prompt, HORIZONTAL_ALIGNMENT_LEFT, -1,
				HudStyle.FONT_BODY, ROUTE_COLOR)


## The land, drawn in `_canvas` (it clips what is outside the map square).
func _draw_map() -> void:
	if _mode == null:
		return
	var c := _canvas
	var font := get_theme_default_font()
	c.draw_rect(Rect2(Vector2.ZERO, _map_rect.size), BACKGROUND)
	var land_from := _to_map(Vector3(-GameConfig.world_half, 0.0, -GameConfig.world_half))
	c.draw_rect(Rect2(land_from, _to_map(Vector3(GameConfig.world_half, 0.0, GameConfig.world_half)) - land_from), LAND)
	for i in ConquestMode.ZONE_EDGES.size():
		var reach := ConquestMode.ZONE_EDGES[i] * GameConfig.world_half
		var from := _to_map(Vector3(-reach, 0.0, -reach))
		c.draw_rect(Rect2(from, _to_map(Vector3(reach, 0.0, reach)) - from), ZONE_LINE, false, 2.0)
		var outer := (ConquestMode.ZONE_EDGES[i + 1] if i + 1 < ConquestMode.ZONE_EDGES.size() else 1.0) * GameConfig.world_half
		c.draw_string(font, _to_map(Vector3(-outer, 0.0, -outer)) + Vector2(6.0, 20.0), "Z%d" % (i + 1),
				HORIZONTAL_ALIGNMENT_LEFT, -1, HudStyle.FONT_SMALL, ZONE_LINE * 2.5)
	var k := _scale()
	var team := _my_team()
	# Routes of my faction: an arrow from each sending place to where its goods go.
	for place in _mode.territories:
		if place.owner_team != team or place.state != TerritoryNode.State.OWNED or place.route == TerritoryNode.ROUTE_NONE:
			continue
		var to := _route_end(place)
		if to != Vector3.INF:
			_arrow(_to_map(place.global_position), _to_map(to), ROUTE_COLOR, 3.0 * k)
	for node in get_tree().get_nodes_in_group(&"caravans"):
		var caravan := node as CaravanUnit
		if caravan.team_id == team and not caravan.is_dead:
			var at := _to_map(caravan.global_position)
			_canvas.draw_rect(Rect2(at - Vector2(5, 5) * k, Vector2(10, 10) * k), COURIER_COLOR)
			_canvas.draw_rect(Rect2(at - Vector2(5, 5) * k, Vector2(10, 10) * k), OUTLINE, false, 1.5)
	for place in _mode.territories:
		var at := _to_map(place.global_position)
		var r: float = DOT[place.kind] * k * 1.4 * TerritoryNode.SIZE_REACH[place.place_size]
		_canvas.draw_circle(at, r + 2.0, OUTLINE)
		_canvas.draw_circle(at, r, _place_color(place))
		if place.state == TerritoryNode.State.OWNED and place.lord == Net.my_id():
			_canvas.draw_arc(at, r + 4.0 * k, 0.0, TAU, 32, LORD_RING, 3.0 * k)
		if place.state == TerritoryNode.State.OWNED and place.owner_team == team and place.unguarded_left >= 0.0:
			# Unguarded: a blinking red ring (the demons take it when its time runs out).
			var blink := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.008)
			_canvas.draw_arc(at, r + 6.0 * k, 0.0, TAU, 32, Color(1.0, 0.2, 0.15, blink), 3.0 * k)
		if place == _selected:
			_canvas.draw_arc(at, r + 8.0 * k, 0.0, TAU, 32, Color.WHITE, 3.0 * k)
	_draw_squads(font, k)
	if _zoom >= NAMES_ZOOM:
		for place in _mode.territories:
			var at := _to_map(place.global_position) + Vector2(-80.0, DOT[place.kind] * k * 1.4 + 18.0)
			_canvas.draw_string_outline(font, at, place.display_name, HORIZONTAL_ALIGNMENT_CENTER, 160.0,
					HudStyle.FONT_SMALL, 4, OUTLINE)
			_canvas.draw_string(font, at, place.display_name, HORIZONTAL_ALIGNMENT_CENTER, 160.0, HudStyle.FONT_SMALL,
					Color(1, 1, 1, 0.9))
	var me := _hero()
	if me:
		var at := _to_map(me.global_position)
		_canvas.draw_circle(at, 9.0 * k, OUTLINE)
		_canvas.draw_circle(at, 7.0 * k, Color.WHITE)


## Your faction's squads: a shield at its leader with the count inside, a line to its goal; yours outlined white.
func _draw_squads(font: Font, k: float) -> void:
	var squads := _mode.squads
	if squads == null:
		return
	for id: int in squads.squads:
		var data: Dictionary = squads.squads[id]
		if int(data.team) != _my_team():
			continue
		var all := squads.members(id)
		if all.is_empty():
			continue
		var at := _to_map(all[0].global_position)
		var goal := squads.goal(id)
		if goal != Vector3.INF and _to_map(goal).distance_to(at) > 6.0:
			_canvas.draw_dashed_line(at, _to_map(goal), SQUAD_LINE, 2.0 * k, 6.0 * k)
		var r := 9.0 * k
		var shield := PackedVector2Array([at + Vector2(-r, -r), at + Vector2(r, -r), at + Vector2(r, r * 0.3),
				at + Vector2(0, r * 1.3), at + Vector2(-r, r * 0.3)])
		_canvas.draw_colored_polygon(shield, Net.color_of(int(data.owner)))
		var edge := shield.duplicate()
		edge.append(shield[0])
		var mine := int(data.owner) == Net.my_id()
		_canvas.draw_polyline(edge, Color.WHITE if mine else OUTLINE, (3.0 if id == _squad else 1.5) * k)
		_canvas.draw_string(font, at + Vector2(-r, r * 0.35), str(all.size()), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0,
				int(HudStyle.FONT_SMALL * maxf(k, 0.7)), Color.WHITE)


func _arrow(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var dir := (to - from)
	if dir.length() < 4.0:
		return
	dir = dir.normalized()
	_canvas.draw_line(from, to, color, width)
	var tip := to - dir * 10.0 * _scale()
	var side := Vector2(-dir.y, dir.x) * 8.0 * _scale()
	_canvas.draw_colored_polygon(PackedVector2Array([to, tip - dir * 8.0 * _scale() + side, tip - dir * 8.0 * _scale() - side]), color)


func _place_color(place: TerritoryNode) -> Color:
	match place.state:
		TerritoryNode.State.INFESTED:
			return DEMON_COLOR
		TerritoryNode.State.OWNED:
			return Net.team_color(place.owner_team)
	return FREE_COLOR


## Where a place's goods go: the place it sends to, or its lord (its army); INF when nowhere.
func _route_end(place: TerritoryNode) -> Vector3:
	if place.route >= 0 and place.route < _mode.territories.size():
		return _mode.territories[place.route].global_position
	if place.route == TerritoryNode.ROUTE_ARMY:
		var lord := _player_of(place.lord)
		return lord.global_position if lord else Vector3.INF
	return Vector3.INF


## Your faction's squad whose shield is at `point` (0 = none).
func _squad_at(point: Vector2) -> int:
	if _mode.squads == null:
		return 0
	var best := 0
	var best_d := 14.0 * maxf(_scale(), 0.6)
	for id: int in _mode.squads.squads:
		if int(_mode.squads.squads[id].team) != _my_team():
			continue
		var all := _mode.squads.members(id)
		if all.is_empty():
			continue
		var d := _to_map(all[0].global_position).distance_to(point)
		if d < best_d:
			best_d = d
			best = id
	return best


func _place_at(point: Vector2) -> TerritoryNode:
	var best: TerritoryNode = null
	var best_d := 18.0 * maxf(_scale(), 0.6)
	for place in _mode.territories:
		var d := _to_map(place.global_position).distance_to(point)
		if d < best_d:
			best_d = d
			best = place
	return best


# --- The card ----------------------------------------------------------------------------

func _update_panel() -> void:
	if _mode == null:
		return
	if _squad != 0:
		if _mode.squads and _mode.squads.squads.has(_squad):
			_update_squad_card()
			return
		_squad = 0  # it broke up or fell
	var place := _selected
	if place == null:
		_title.text = "The land"
		_info.text = "Click a place to see it."
		_page_tabs.visible = false
		_upgrades_box.visible = false
		_barracks_box.visible = false
		for id in _buttons:
			(_buttons[id] as Button).visible = false
		_hint.text = "M / Esc: close"
		return
	var team := _my_team()
	_title.text = place.display_name
	var lines := PackedStringArray()
	var ours := place.state == TerritoryNode.State.OWNED and place.owner_team == team
	var holder := "demons"
	match place.state:
		TerritoryNode.State.NEUTRAL:
			holder = "free: stand in it to take it"
		TerritoryNode.State.OWNED:
			holder = ("yours, lord " + (Net.name_of(place.lord) if place.lord != 0 else "nobody")) if ours \
					else Net.localize("{label:%d}" % place.owner_team)
	lines.append("%s · Zone %d · %s" % [place.full_name(), place.zone, holder])
	if ours:
		if place.unguarded_left >= 0.0:
			lines.append("UNGUARDED: demons take it in %d s. Leave soldiers here." % ceili(place.unguarded_left))
		# Per minute (a tick is LogisticsManager.TICK s).
		var made := place.output()
		var per_min := 60.0 / LogisticsManager.TICK
		var room := place.store_cap()
		lines.append("Food %d/%d (+%d/min) · Weapons %d/%d (+%d/min) · Gold %d" % [place.store[&"food"], room,
				roundi(made[&"food"] * per_min), place.store[&"equipment"], room,
				roundi(made[&"equipment"] * per_min), place.treasury])
		lines.append(_eating_text(place))
		lines.append("Goods go %s (%d/%d couriers home)" % [_route_text(place), place.couriers, place.courier_total])
	_info.text = "\n".join(lines)
	var commands := ours and _can_command(place)
	var me := _hero()
	for id in _buttons:
		(_buttons[id] as Button).visible = commands and id in PLACE_BUTTONS
	_page_tabs.visible = ours
	for i in _page_buttons.size():
		_page_buttons[i].set_pressed_no_signal(i == _page)
	_upgrades_box.visible = ours and _page == 1
	if _upgrades_box.visible:
		_update_upgrades(place, commands)
	_update_barracks(place, ours and _page == 0, commands, me)
	if commands and me:
		var take := _buttons[&"withdraw"] as Button
		take.text = "Take gold (%d)" % place.treasury
		take.disabled = place.treasury <= 0 or place.lord != me.peer_id
		(_buttons[&"route_stop"] as Button).disabled = place.route == TerritoryNode.ROUTE_NONE
		(_buttons[&"route_army"] as Button).disabled = place.route == TerritoryNode.ROUTE_ARMY and place.lord == me.peer_id
		var courier := _buttons[&"courier"] as Button
		courier.text = "Buy courier (%d coins)" % LogisticsManager.COURIER_COST
		courier.disabled = place.courier_total >= TerritoryNode.COURIER_MAX or me.coins < LogisticsManager.COURIER_COST
	if ours and not commands:
		_hint.text = "Only its lord or the General gives orders here."
	elif _picking == &"route":
		_hint.text = "Click the place to send the goods to."
	elif ours:
		_hint.text = "Weapons: Iron / Lumber Cities make them · couriers carry %d a trip · worn soldiers re-arm by a place." % \
				CaravanUnit.CARGO[&"equipment"]
	else:
		_hint.text = ""
	_panel.reset_size()


## What the soldiers standing by this place eat from its store: how many they are, the rations a meal, and how
## many meals (how long) the food here lasts them with nothing more coming in.
func _eating_text(place: TerritoryNode) -> String:
	var eaters := 0
	var reach := float(place.info().supply)
	for node in get_tree().get_nodes_in_group(&"allies"):
		var ally := node as Ally
		if ally == null or ally.is_dead or ally.team_id != place.owner_team:
			continue
		var offset := ally.global_position - place.global_position
		offset.y = 0.0
		if offset.length() <= reach:
			eaters += 1
	if eaters <= 0:
		return "Eats: no soldiers here"
	var seconds := int(place.store[&"food"]) / eaters * LogisticsManager.MEAL_SECONDS
	return "%d soldiers eat %d a meal · lasts %d:%02d" % [eaters, eaters, seconds / 60, seconds % 60]


## The barracks rows: people waiting, then per class how many are armed and their rank, which class its people
## are armed with (the pressed Train), and Take (armed ones first, then people armed on the spot).
func _update_barracks(place: TerritoryNode, ours: bool, commands: bool, me: Player) -> void:
	_barracks_box.visible = ours and place.has_barracks()
	if not _barracks_box.visible:
		return
	var weapons_here := int(place.store[&"equipment"])
	var lines := PackedStringArray()
	var per_min := float(place.info().pool) * TerritoryNode.ZONE_PEOPLE[place.zone] * 60.0 \
			/ (LogisticsManager.TICK * LogisticsManager.POOL_EVERY)
	lines.append("Waiting: %d (+%.1f/min) · room %d/%d" % [place.people, per_min, place.barracks,
			place.barracks_cap()])
	# What arming everybody who waits takes: a weapon each from this store, and the time at this place's pace.
	var need := place.people * LogisticsManager.MUSTER_EQUIPMENT
	var seconds := ceili(float(place.people) / place.arm_per_tick()) * int(LogisticsManager.TICK)
	var have := "%d here" % weapons_here if weapons_here >= need else "%d here, %d SHORT" % [weapons_here, need - weapons_here]
	if place.train_kind < 0:
		lines.append("1. Press Train on a class. 2. Each person takes a weapon from this store. 3. Armed ones drill "
				+ "and rank up (I 45 s · II 2 min · III 4 min · IV 7 min). 4. Take sends them out.")
		if place.people > 0:
			lines.append("Arming all %d needs %d weapons (%s)." % [place.people, need, have])
	elif place.people <= 0:
		lines.append("Arming %s: nobody waiting. Armed ones drill and rank up." % TerritoryNode.SOLDIER_NAMES[place.train_kind].to_lower())
	else:
		lines.append("Arming %s, %d a tick: all %d need %d weapons (%s) · %d:%02d" % [
				TerritoryNode.SOLDIER_NAMES[place.train_kind].to_lower(), place.arm_per_tick(), place.people, need, have,
				seconds / 60, seconds % 60])
	_people.text = "\n".join(lines)
	for i in _size_buttons.size():
		_size_buttons[i].visible = commands
		_size_buttons[i].set_pressed_no_signal(i == _size_index)
	var room := me.follower_cap - me.army_size() if me else 0
	var food := int(place.store[&"food"]) / LogisticsManager.MUSTER_FOOD
	var weapons := int(place.store[&"equipment"]) / LogisticsManager.MUSTER_EQUIPMENT
	for k in _class_rows.size():
		var row: Dictionary = _class_rows[k]
		var armed := place.armed[k]
		(row.label as Label).text = "%s %d%s" % [TerritoryNode.SOLDIER_NAMES[k], armed,
				(" · " + Ally.RANK_NAMES[place.ranks[k]]) if armed > 0 and place.ranks[k] > 0 else ""]
		var train := row.train as Button
		train.visible = commands
		train.set_pressed_no_signal(place.train_kind == k)
		var take := row.take as Button
		take.visible = commands
		var can := mini(mini(armed + mini(place.people, weapons), food), mini(ConquestSquads.SIZES[_size_index], room))
		take.text = "Take %d" % maxi(can, 0) if can > 0 else "Take"
		take.disabled = can <= 0


func _on_train(k: int) -> void:
	if _selected:
		var pick := TerritoryNode.NO_TRAINING if _selected.train_kind == k else k
		_order(&"train", pick)
		_selected.train_kind = pick  # shown at once (the server's comes with the next update)
		_update_panel()


## A squad of class `k`, of the picked size (place_action packs both: class + 10 × size index).
func _on_take(k: int) -> void:
	if _selected:
		_order(&"muster", k + 10 * _size_index)
		_update_panel()


func _on_size(index: int) -> void:
	_size_index = index
	_update_panel()


## A squad's card: its class, size, leader, order; its hero (or the General) sends it on.
func _update_squad_card() -> void:
	var squads := _mode.squads
	var data := squads.squad(_squad)
	var all := squads.members(_squad)
	var head := squads.leader_of(_squad)
	var kind := int(data.kind)
	_title.text = "Squad of %s" % (TerritoryNode.SOLDIER_NAMES[kind] if kind >= 0 else "soldiers")
	var lines := PackedStringArray()
	lines.append("%d soldiers · %s's" % [all.size(), Net.name_of(int(data.owner))])
	if head:
		lines.append("Led by a %s" % Ally.RANK_NAMES[head.rank])
	lines.append(squads.order_text(_squad))
	_info.text = "\n".join(lines)
	_barracks_box.visible = false
	_page_tabs.visible = false
	_upgrades_box.visible = false
	var me := _hero()
	var commands := me != null and (int(data.owner) == me.peer_id
			or int(_mode.logistics.stock_of(me.team_id).get(&"general", 0)) == me.peer_id)
	for id in _buttons:
		(_buttons[id] as Button).visible = commands and id in SQUAD_BUTTONS
	if _picking == &"squad_go":
		_hint.text = "Click the place it goes to: it takes it if it can and guards it."
	elif _picking == &"squad_hold":
		_hint.text = "Click the point it holds."
	else:
		_hint.text = "It fights what comes near on the way, and guards where it stands. M / Esc: close"
	_panel.reset_size()


func _squad_order(action: StringName, arg: int, point: Vector3) -> void:
	var me := _hero()
	if me and _squad:
		me.request_squad_action(_squad, action, arg, point)


func _route_text(place: TerritoryNode) -> String:
	if place.route >= 0 and place.route < _mode.territories.size():
		return "to " + _mode.territories[place.route].display_name
	if place.route == TerritoryNode.ROUTE_ARMY:
		return "to %s's army" % Net.name_of(place.lord)
	return "nowhere (kept here)"


## Its lord, the faction's General, or anyone of the faction while it has no lord.
func _can_command(place: TerritoryNode) -> bool:
	var me := Net.my_id()
	if place.lord == 0 or place.lord == me:
		return true
	return _mode.logistics != null and int(_mode.logistics.stock_of(place.owner_team).get(&"general", 0)) == me


func _on_button(id: StringName) -> void:
	if _selected == null:
		return
	match id:
		&"pick_route":
			_picking = &"route"
		&"squad_go", &"squad_hold":
			_picking = id
		&"squad_join":
			_squad_order(&"join", -1, Vector3.ZERO)
		&"route_army":
			_order(&"route", TerritoryNode.ROUTE_ARMY)
		&"route_stop":
			_order(&"route", TerritoryNode.ROUTE_NONE)
		_:
			_order(id, 0)
	_update_panel()
	_redraw()


func _order(action: StringName, arg: int) -> void:
	var me := _hero()
	if me and _selected:
		me.request_place_action(_selected.index, action, arg)


func _my_team() -> int:
	return Net.team_of(Net.my_id())


func _hero() -> Player:
	return _player_of(Net.my_id())


func _player_of(peer: int) -> Player:
	if peer == 0:
		return null
	for node in get_tree().get_nodes_in_group(&"players"):
		if (node as Player).peer_id == peer:
			return node
	return null


func _place_of_hero() -> TerritoryNode:
	var me := _hero()
	if me == null or _mode == null:
		return null
	var best: TerritoryNode = null
	for place in _mode.territories:
		if best == null or place.global_position.distance_to(me.global_position) < best.global_position.distance_to(me.global_position):
			best = place
	return best
