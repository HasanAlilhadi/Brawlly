class_name ShopMenu
extends CanvasLayer
## A stall's shop (see ShopStation): spend coins on the items in `catalog` that this stall sells. Pauses the
## game while open (solo only). Rows are built from the catalog, so a new item only needs an UpgradeDef entry
## with its `stalls`. Closes by itself when you walk away from the stall.
## At the barracks a first row shows your army (following / in the pen / training, out of the cap)
## with a "Take" button that calls the soldiers waiting in the pen.

signal opened
signal closed

const COIN_ICON := preload("res://assets/ui/icons/coin.png")
const SOLDIER_ICON := preload("res://assets/ui/icons/soldier.png")

@export var catalog: UpgradeCatalog

var _player: Player
## Online matches keep running: the shop doesn't pause the game.
var online: bool = false
var _rows: Array[Dictionary] = []  # {def, panel, title, button}
## The stall this shop is open for.
var stall: ShopStation

var _army_panel: PanelContainer
var _army_title: Label
var _army_detail: Label
var _take_button: Button
var _army_timer: float = 0.0

@onready var _coins_label: Label = %CoinsLabel
@onready var _list: VBoxContainer = %List
@onready var _close_button: Button = %CloseButton
@onready var _title: Label = $Panel/Box/Header/Title


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	_close_button.pressed.connect(close)
	_build_army_row()
	for def in catalog.upgrades:
		_add_row(def)


func setup(player: Player) -> void:
	_player = player
	player.coins_changed.connect(func(_c: int) -> void: _refresh())
	player.upgrades_changed.connect(_refresh)


func open(at: ShopStation) -> void:
	if visible or get_tree().paused or _player == null or _player.is_dead or at == null \
			or not at.can_access(_player):
		return
	stall = at
	_title.text = at.title()
	for row in _rows:
		(row.panel as Control).visible = at.sells(row.def)
	_army_panel.visible = at.stall_id == ShopStation.BARRACKS
	if not online:
		get_tree().paused = true
	_refresh()
	show()
	opened.emit()


func close() -> void:
	if not visible:
		return
	hide()
	stall = null
	if not online:
		get_tree().paused = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact")):
		close()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and visible:
		close()


func _process(delta: float) -> void:
	# Barracks: training countdowns tick while the menu is open.
	if not visible or not _army_panel.visible:
		return
	_army_timer -= delta
	if _army_timer <= 0.0:
		_army_timer = 0.2
		_refresh()


## Barracks: "Your army 4/10" + what waits in the pen / is training, and the Take button.
func _build_army_row() -> void:
	_army_panel = PanelContainer.new()
	_army_panel.theme_type_variation = &"PanelLight"
	_list.add_child(_army_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_army_panel.add_child(row)
	var icon := TextureRect.new()
	icon.texture = SOLDIER_ICON
	icon.custom_minimum_size = Vector2(64, 64)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)
	_army_title = Label.new()
	_army_title.add_theme_font_size_override("font_size", 28)
	text.add_child(_army_title)
	_army_detail = Label.new()
	_army_detail.add_theme_font_size_override("font_size", 20)
	_army_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(_army_detail)
	_take_button = Button.new()
	_take_button.theme_type_variation = &"ButtonBeige"
	_take_button.custom_minimum_size = Vector2(150, 76)
	_take_button.add_theme_font_size_override("font_size", 26)
	_take_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_take_button.pressed.connect(_take_soldiers)
	row.add_child(_take_button)


func _take_soldiers() -> void:
	if _player:
		_player.request_collect_soldiers()
		_army_timer = 0.1


func _refresh_army() -> void:
	var ready := _player.penned_soldiers().size()
	_army_title.text = "Your army  %d/%d" % [_player.army_size(), _player.follower_cap]
	var detail := ShopStation.soldier_status(_player)
	_army_detail.text = "Buy soldiers below: each trains for %ds, then waits in the pen." % roundi(GameConfig.SOLDIER_TRAIN_TIME) \
			if detail == "" else detail
	_take_button.text = "Take %d" % ready if ready > 0 else "Take"
	_take_button.disabled = ready == 0


func _add_row(def: UpgradeDef) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"PanelInset"
	_list.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)

	var icon := TextureRect.new()
	icon.texture = def.icon
	icon.custom_minimum_size = Vector2(64, 64)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 28)
	text.add_child(title)
	var description := Label.new()
	description.text = def.description
	description.add_theme_font_size_override("font_size", 20)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(description)

	var button := Button.new()
	button.custom_minimum_size = Vector2(150, 76)
	button.icon = COIN_ICON
	button.expand_icon = false
	button.add_theme_font_size_override("font_size", 28)
	button.add_theme_constant_override("icon_max_width", 36)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(_buy.bind(def))
	row.add_child(button)

	_rows.append({"def": def, "panel": panel, "title": title, "button": button})


func _buy(def: UpgradeDef) -> void:
	if _player and _player.can_buy(def):
		_player.request_buy(def)
		_refresh()


func _refresh() -> void:
	if _player == null:
		return
	_coins_label.text = str(_player.coins)
	if _army_panel.visible:
		_refresh_army()
	for row in _rows:
		var def: UpgradeDef = row.def
		var title: Label = row.title
		var button: Button = row.button
		var level := _player.upgrade_level(def.id)
		title.text = def.title if def.is_consumable() else "%s  %d/%d" % [def.title, level, def.max_level]
		if _player.is_upgrade_maxed(def):
			button.text = "MAX"
			button.icon = null
		else:
			button.text = str(_player.upgrade_cost(def))
			button.icon = COIN_ICON
		button.disabled = not _player.can_buy(def)
