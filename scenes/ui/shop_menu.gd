class_name ShopMenu
extends CanvasLayer
## Shop overlay: spend coins on the upgrades in `catalog`. Pauses the game while open.
## Rows are built from the catalog, so new shop items only need a new UpgradeDef entry.

signal opened
signal closed

const COIN_ICON := preload("res://assets/ui/icons/coin.png")

@export var catalog: UpgradeCatalog

var _player: Player
## Online matches keep running: the shop doesn't pause the game.
var online: bool = false
var _rows: Array[Dictionary] = []  # {def, level_label, button}

@onready var _coins_label: Label = %CoinsLabel
@onready var _list: VBoxContainer = %List
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	_close_button.pressed.connect(close)
	for def in catalog.upgrades:
		_add_row(def)


func setup(player: Player) -> void:
	_player = player
	player.coins_changed.connect(func(_c: int) -> void: _refresh())
	player.upgrades_changed.connect(_refresh)


func open() -> void:
	if visible or get_tree().paused or _player == null or _player.is_dead:
		return
	if not online:
		get_tree().paused = true
	_refresh()
	show()
	opened.emit()


func close() -> void:
	if not visible:
		return
	hide()
	if not online:
		get_tree().paused = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("shop")):
		close()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and visible:
		close()


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

	_rows.append({"def": def, "title": title, "button": button})


func _buy(def: UpgradeDef) -> void:
	if _player and _player.can_buy(def):
		_player.request_buy(def)
		_refresh()


func _refresh() -> void:
	if _player == null:
		return
	_coins_label.text = str(_player.coins)
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
