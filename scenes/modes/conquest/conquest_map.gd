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

var _panel: PanelContainer
var _title: Label
var _info: Label
var _hint: Label
var _buttons: Dictionary = {}
var _barracks_box: VBoxContainer
var _people: Label
## Per class (TerritoryNode.SOLDIER_KINDS order): {label, train, take}.
var _class_rows: Array[Dictionary] = []


func setup(main: Node, mode: ConquestMode) -> void:
	_main = main
	_mode = mode


func _ready() -> void:
	name = "ConquestMap"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
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
	_build_barracks(box)
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
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause")):
		toggle()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.device == InputEvent.DEVICE_ID_EMULATION:
		return
	accept_event()
	if click.button_index != MOUSE_BUTTON_LEFT:
		_picking = &""
		_update_panel()
		return
	var place := _place_at(click.position)
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
			if _map_rect.has_point(click.position):
				_squad_order(&"hold", -1, _from_map(click.position))
		_:
			var squad := _squad_at(click.position)
			if squad:
				_squad = squad
			elif place:
				_selected = place
				_squad = 0
	_update_panel()
	queue_redraw()


# --- Map drawing -------------------------------------------------------------------------

func _to_map(point: Vector3) -> Vector2:
	var half := maxf(GameConfig.world_half, 1.0)
	var share := Vector2(point.x / half, point.z / half) * 0.5 + Vector2(0.5, 0.5)
	return _map_rect.position + share * _map_rect.size


## The flat world point under a spot of the map.
func _from_map(point: Vector2) -> Vector3:
	var half := maxf(GameConfig.world_half, 1.0)
	var share := (point - _map_rect.position) / _map_rect.size
	return Vector3((share.x - 0.5) * 2.0 * half, 0.0, (share.y - 0.5) * 2.0 * half)


func _scale() -> float:
	return _map_rect.size.x / 900.0


func _draw() -> void:
	if _mode == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	draw_rect(_map_rect, LAND)
	var center := _map_rect.get_center()
	var font := get_theme_default_font()
	for i in ConquestMode.ZONE_EDGES.size():
		var reach := ConquestMode.ZONE_EDGES[i] * _map_rect.size.x * 0.5
		draw_rect(Rect2(center - Vector2(reach, reach), Vector2(reach, reach) * 2.0), ZONE_LINE, false, 2.0)
		var outer := (ConquestMode.ZONE_EDGES[i + 1] if i + 1 < ConquestMode.ZONE_EDGES.size() else 1.0) * _map_rect.size.x * 0.5
		draw_string(font, center + Vector2(-outer + 6.0, -outer + 20.0), "Z%d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT,
				-1, HudStyle.FONT_SMALL, ZONE_LINE * 2.5)
	draw_rect(_map_rect, OUTLINE, false, 3.0)
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
			draw_rect(Rect2(at - Vector2(5, 5) * k, Vector2(10, 10) * k), COURIER_COLOR)
			draw_rect(Rect2(at - Vector2(5, 5) * k, Vector2(10, 10) * k), OUTLINE, false, 1.5)
	for place in _mode.territories:
		var at := _to_map(place.global_position)
		var r: float = DOT[place.kind] * k * 1.4
		draw_circle(at, r + 2.0, OUTLINE)
		draw_circle(at, r, _place_color(place))
		if place.state == TerritoryNode.State.OWNED and place.lord == Net.my_id():
			draw_arc(at, r + 4.0 * k, 0.0, TAU, 32, LORD_RING, 3.0 * k)
		if place.state == TerritoryNode.State.OWNED and place.owner_team == team and place.unguarded_left >= 0.0:
			# Unguarded: a blinking red ring (the demons take it when its time runs out).
			var blink := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.008)
			draw_arc(at, r + 6.0 * k, 0.0, TAU, 32, Color(1.0, 0.2, 0.15, blink), 3.0 * k)
		if place == _selected:
			draw_arc(at, r + 8.0 * k, 0.0, TAU, 32, Color.WHITE, 3.0 * k)
	_draw_squads(font, k)
	var me := _hero()
	if me:
		var at := _to_map(me.global_position)
		draw_circle(at, 9.0 * k, OUTLINE)
		draw_circle(at, 7.0 * k, Color.WHITE)
	var prompt := ""
	match _picking:
		&"route":
			prompt = "Click a place of yours to send the goods to (right click: cancel)"
		&"squad_go":
			prompt = "Click the place the squad goes to (right click: cancel)"
		&"squad_hold":
			prompt = "Click the point the squad holds (right click: cancel)"
	if prompt != "":
		draw_string(font, _map_rect.position + Vector2(0, -12), prompt, HORIZONTAL_ALIGNMENT_LEFT, -1,
				HudStyle.FONT_BODY, ROUTE_COLOR)


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
			draw_dashed_line(at, _to_map(goal), SQUAD_LINE, 2.0 * k, 6.0 * k)
		var r := 9.0 * k
		var shield := PackedVector2Array([at + Vector2(-r, -r), at + Vector2(r, -r), at + Vector2(r, r * 0.3),
				at + Vector2(0, r * 1.3), at + Vector2(-r, r * 0.3)])
		draw_colored_polygon(shield, Net.color_of(int(data.owner)))
		var edge := shield.duplicate()
		edge.append(shield[0])
		var mine := int(data.owner) == Net.my_id()
		draw_polyline(edge, Color.WHITE if mine else OUTLINE, (3.0 if id == _squad else 1.5) * k)
		draw_string(font, at + Vector2(-r, r * 0.35), str(all.size()), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0,
				int(HudStyle.FONT_SMALL * maxf(k, 0.7)), Color.WHITE)


func _arrow(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var dir := (to - from)
	if dir.length() < 4.0:
		return
	dir = dir.normalized()
	draw_line(from, to, color, width)
	var tip := to - dir * 10.0 * _scale()
	var side := Vector2(-dir.y, dir.x) * 8.0 * _scale()
	draw_colored_polygon(PackedVector2Array([to, tip - dir * 8.0 * _scale() + side, tip - dir * 8.0 * _scale() - side]), color)


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
		for id in _buttons:
			(_buttons[id] as Button).visible = false
		_hint.text = "M / Esc: close"
		return
	var team := _my_team()
	_title.text = place.display_name
	var lines := PackedStringArray()
	lines.append("%s · Zone %d" % [place.kind_name(), place.zone])
	match place.state:
		TerritoryNode.State.INFESTED:
			lines.append("Held by demons")
		TerritoryNode.State.NEUTRAL:
			lines.append("Free: stand in it to raise your banner")
		TerritoryNode.State.OWNED:
			lines.append("Held by " + Net.localize("{label:%d}" % place.owner_team))
	var ours := place.state == TerritoryNode.State.OWNED and place.owner_team == team
	if ours:
		lines[lines.size() - 1] += " · Lord: " + (Net.name_of(place.lord) if place.lord != 0 else "nobody")
		if place.unguarded_left >= 0.0:
			lines.append("UNGUARDED: demons take it in %d s — leave soldiers here" % ceili(place.unguarded_left))
		elif place.kind != TerritoryNode.Kind.CITADEL:
			lines.append("Guarded (unguarded it falls in %d s)" % roundi(TerritoryNode.ZONE_UNGUARDED[place.zone]))
		lines.append("Food %d · Weapons %d  (store %d each)" % [place.store[&"food"],
				place.store[&"equipment"], TerritoryNode.STORE_CAP])
		var made := place.output()
		lines.append("Makes Food %d · Weapons %d · Gold %d a tick" % [made[&"food"], made[&"equipment"],
				made[&"gold"]])
		lines.append("Treasury %d / %d gold" % [place.treasury, TerritoryNode.TREASURY_CAP])
		lines.append("Couriers %d home of %d" % [place.couriers, place.courier_total])
		lines.append("Sends goods: " + _route_text(place))
	_info.text = "\n".join(lines)
	var commands := ours and _can_command(place)
	var me := _hero()
	for id in _buttons:
		(_buttons[id] as Button).visible = commands and id in PLACE_BUTTONS
	_update_barracks(place, ours, commands, me)
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
		_hint.text = "Only its lord or the General gives orders here. M / Esc: close"
	elif _picking == &"route":
		_hint.text = "Click the place to send the goods to."
	else:
		_hint.text = "Goods go by courier: %d food, %d weapons a trip. M / Esc: close" % [
				CaravanUnit.CARGO[&"food"], CaravanUnit.CARGO[&"equipment"]]
	_panel.reset_size()


## The barracks rows: people waiting, then per class how many are armed and their rank, which class its people
## are armed with (the pressed Train), and Take (armed ones first, then people armed on the spot).
func _update_barracks(place: TerritoryNode, ours: bool, commands: bool, me: Player) -> void:
	_barracks_box.visible = ours and place.has_barracks()
	if not _barracks_box.visible:
		return
	var training := "armed as %s (a weapon each)" % TerritoryNode.SOLDIER_NAMES[place.train_kind].to_lower() \
			if place.train_kind >= 0 else "pick a class to arm them: unarmed people don't train"
	_people.text = "Barracks %d / %d · %d people unarmed, %s" % [place.barracks, place.barracks_cap(), place.people,
			training]
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
	queue_redraw()


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
