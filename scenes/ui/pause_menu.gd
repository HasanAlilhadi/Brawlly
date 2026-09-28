class_name PauseMenu
extends CanvasLayer
## Pause overlay: Resume / Restart / Main menu. Pauses the whole tree while open.
## Opens with `open()` (e.g. a HUD pause button), Esc / Android back, and automatically
## when the app goes to the background on mobile. Set `can_pause = false` on game over.

signal paused
signal resumed

@export_file("*.tscn") var main_menu_scene: String = "res://scenes/ui/main_menu.tscn"

var can_pause: bool = true
## Online matches keep running for everyone: the menu doesn't pause, and offers "Leave game".
var online: bool = false:
	set(value):
		online = value
		if is_node_ready():
			_apply_online()

@onready var _resume_button: Button = %ResumeButton
@onready var _restart_button: Button = %RestartButton
@onready var _menu_button: Button = %MenuButton

var _hint: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	_resume_button.pressed.connect(close)
	_restart_button.pressed.connect(_restart)
	_menu_button.pressed.connect(_to_main_menu)
	_apply_online()


func _apply_online() -> void:
	_restart_button.visible = not online
	_menu_button.text = "Leave Game" if online else "Main Menu"


## Small text under the buttons (e.g. the desktop controls). Empty hides it.
func set_hint(text: String) -> void:
	if _hint == null:
		_hint = Label.new()
		_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_hint.add_theme_font_size_override("font_size", 20)
		_hint.custom_minimum_size.x = 520.0
		_menu_button.get_parent().add_child(_hint)
	_hint.text = text
	_hint.visible = text != ""


func open() -> void:
	if not can_pause or visible:
		return
	if not online:
		get_tree().paused = true
	show()
	if not OS.has_feature("mobile"):
		_resume_button.grab_focus.call_deferred()  # keyboard / gamepad navigation
	paused.emit()


func close() -> void:
	if not visible:
		return
	hide()
	if not online:
		get_tree().paused = false
	resumed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (InputMap.has_action("pause") and event.is_action_pressed("pause")):
		toggle()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			toggle()
		NOTIFICATION_APPLICATION_PAUSED:
			open()
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			if OS.has_feature("mobile"):
				open()


func _restart() -> void:
	get_tree().paused = false
	var net := get_node_or_null("/root/Net")
	if net:
		net.call("start_game", false)
	else:
		get_tree().reload_current_scene()


func _to_main_menu() -> void:
	get_tree().paused = false
	var net := get_node_or_null("/root/Net")
	if net:
		net.call("leave")
	else:
		get_tree().change_scene_to_file(main_menu_scene)
