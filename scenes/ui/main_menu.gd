extends Node
## Main menu: game title (from Project Settings → Application → Name), your name ("Playing as", saved in the
## profile), Find Game (server browser), Host Game (host screen), Training Field, Controls and Quit.
## Quit is hidden on iOS / web, where apps shouldn't quit themselves.
## When a game dropped you (`Net.leave_reason`: host left, removed from the game), a notice says why.
## Portrait (phones): title on top, menu at the bottom. Landscape (desktop): title and menu on the left,
## the backdrop camp shifted to the right.

const BROWSER_SCENE := "res://scenes/ui/server_browser.tscn"
const HOST_SCENE := "res://scenes/ui/host_menu.tscn"
const CONTROLS_SCENE := "res://scenes/ui/controls_menu.tscn"

@onready var _title: Label = %Title
@onready var _name_edit: LineEdit = %NameEdit
@onready var _find_button: Button = %FindButton
@onready var _host_button: Button = %HostButton
@onready var _training_button: Button = %TrainingButton
@onready var _controls_button: Button = %ControlsButton
@onready var _quit_button: Button = %QuitButton
@onready var _menu: Control = $UI/Root/Menu
@onready var _backdrop: Node3D = $Backdrop

var _notice: Dictionary = {}
var _leaving: bool = false


func _ready() -> void:
	get_tree().paused = false
	_title.text = ProjectSettings.get_setting("application/config/name", "Game")
	_name_edit.text = Net.profile.name
	_name_edit.text_changed.connect(func(text: String) -> void: Net.set_profile(text))
	_name_edit.text_submitted.connect(func(_text: String) -> void: _find_button.grab_focus())
	_find_button.pressed.connect(_go_to.bind(BROWSER_SCENE))
	_host_button.pressed.connect(_go_to.bind(HOST_SCENE))
	_training_button.pressed.connect(_start_training)
	_controls_button.pressed.connect(_go_to.bind(CONTROLS_SCENE))
	_quit_button.pressed.connect(get_tree().quit)
	_quit_button.visible = not (OS.has_feature("ios") or OS.has_feature("web"))
	get_viewport().size_changed.connect(_layout)
	_layout()
	if Net.leave_reason != "":
		_show_notice(Net.leave_reason)
		Net.leave_reason = ""
	elif not OS.has_feature("mobile"):
		_find_button.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _notice.is_empty():
		get_viewport().set_input_as_handled()
		_close_notice()


func _go_to(path: String) -> void:
	if _leaving or not is_inside_tree():
		return
	_leaving = true
	get_tree().change_scene_to_file(path)


func _start_training() -> void:
	if _leaving:
		return
	_leaving = true
	Net.open_offline_lobby()
	Net.settings.training = true
	Net.settings.camp_count = 0
	Net.settings.events = false
	Net.start_game(false)


func _show_notice(reason: String) -> void:
	_notice = MenuKit.dialog($UI, "Disconnected")
	var text := MenuKit.label(reason, &"", 30)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	(_notice.body as Control).add_child(text)
	var ok := MenuKit.button("OK", true)
	ok.name = "NoticeOkButton"
	ok.pressed.connect(_close_notice)
	(_notice.buttons as Control).add_child(ok)
	ok.grab_focus.call_deferred()


func _close_notice() -> void:
	MenuKit.close_dialog(_notice)
	_notice = {}
	if not OS.has_feature("mobile"):
		_find_button.grab_focus.call_deferred()


func _layout() -> void:
	var size := get_viewport().get_visible_rect().size
	var landscape := size.x > size.y
	var column := 0.27 if landscape else 0.5
	_title.anchor_left = column - 0.25 if landscape else 0.0
	_title.anchor_right = column + 0.25 if landscape else 1.0
	_menu.anchor_left = column
	_menu.anchor_right = column
	# Landscape: menu under the title, centered in the lower part of the screen.
	_menu.anchor_top = 0.6 if landscape else 1.0
	_menu.anchor_bottom = _menu.anchor_top
	_menu.offset_top = -360.0 if landscape else -800.0
	_menu.offset_bottom = 360.0 if landscape else -60.0
	_title.offset_top = 50.0 if landscape else 110.0
	_title.offset_bottom = _title.offset_top + 140.0
	_backdrop.set("view_shift", -2.6 if landscape else 0.0)
