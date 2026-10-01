extends Node
## Main menu: game title (from Project Settings → Application → Name), Training, Multiplayer,
## Controls and Quit.
## Quit is hidden on iOS / web, where apps shouldn't quit themselves.
## Portrait (phones): title on top, menu at the bottom. Landscape (desktop): title and menu on the left,
## the backdrop camp shifted to the right.

const MULTIPLAYER_SCENE := "res://scenes/ui/multiplayer_menu.tscn"
const CONTROLS_SCENE := "res://scenes/ui/controls_menu.tscn"

@onready var _title: Label = %Title
@onready var _training_button: Button = %TrainingButton
@onready var _multiplayer_button: Button = %MultiplayerButton
@onready var _controls_button: Button = %ControlsButton
@onready var _quit_button: Button = %QuitButton
@onready var _menu: Control = $UI/Root/Menu
@onready var _backdrop: Node3D = $Backdrop


func _ready() -> void:
	get_tree().paused = false
	_title.text = ProjectSettings.get_setting("application/config/name", "Game")
	_training_button.pressed.connect(_start_training)
	_multiplayer_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(MULTIPLAYER_SCENE))
	_controls_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(CONTROLS_SCENE))
	_quit_button.pressed.connect(get_tree().quit)
	_quit_button.visible = not (OS.has_feature("ios") or OS.has_feature("web"))
	get_viewport().size_changed.connect(_layout)
	_layout()
	if not OS.has_feature("mobile"):
		_training_button.grab_focus.call_deferred()  # new players can start learning right away


func _start_training() -> void:
	Net.open_offline_lobby()
	Net.settings.training = true
	Net.settings.camp_count = 0
	Net.settings.events = false
	Net.start_game(false)


func _layout() -> void:
	var size := get_viewport().get_visible_rect().size
	var landscape := size.x > size.y
	var column := 0.27 if landscape else 0.5
	_title.anchor_left = column - 0.25 if landscape else 0.0
	_title.anchor_right = column + 0.25 if landscape else 1.0
	_menu.anchor_left = column
	_menu.anchor_right = column
	# Landscape: menu under the title, vertically centered in the lower part of the screen.
	_menu.anchor_top = 0.62 if landscape else 1.0
	_menu.anchor_bottom = _menu.anchor_top
	_menu.offset_top = -320.0 if landscape else -730.0
	_menu.offset_bottom = 320.0 if landscape else -70.0
	_title.offset_top = 90.0 if landscape else 110.0
	_title.offset_bottom = _title.offset_top + 140.0
	_backdrop.set("view_shift", -2.6 if landscape else 0.0)
