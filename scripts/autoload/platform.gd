extends Node
## Device setup (autoload `Platform`). Desktop first, mobile still supported.
## - Desktop (Windows / macOS / Linux): landscape UI (`DESKTOP_SIZE`), mouse + keyboard + gamepad,
##   resizable window, F11 / Alt+Enter toggles fullscreen (remembered in `user://display.cfg`).
## - Mobile, or a desktop run with `-- --mobile` (to test the phone layout): phone UI size (720×1280 portrait
##   or 1280×720 landscape, from Project Settings → Display → Window → Handheld → Orientation, which
##   `tools/set_orientation.sh` sets) and touch controls (the mouse emulates touch on desktop).
## - `touch_mode`: show on-screen touch controls. Always on for the mobile layout; on desktop it turns on
##   when a real touchscreen is used and off again on mouse / keyboard / gamepad input.

signal touch_mode_changed(enabled: bool)

const DESKTOP_SIZE := Vector2i(1920, 1080)
const PHONE_PORTRAIT := Vector2i(720, 1280)
## Default desktop window, shrunk to fit smaller screens.
const DESKTOP_WINDOW := Vector2i(1600, 900)
const SETTINGS_PATH := "user://display.cfg"

## True when the UI uses the portrait phone layout.
var mobile_layout: bool = false
var touch_mode: bool = false


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mobile_layout = OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--mobile")
	touch_mode = mobile_layout
	var window := get_window()
	if mobile_layout:
		window.content_scale_size = ui_size()
		if not OS.has_feature("mobile"):
			Input.emulate_touch_from_mouse = true
			_resize_window(ui_size() * 9 / 16)
	else:
		window.content_scale_size = DESKTOP_SIZE
		Input.emulate_touch_from_mouse = false
		if not _is_embedded():
			_resize_window(DESKTOP_WINDOW)
			if _load_fullscreen():
				set_fullscreen(true)


## Viewport size the UI is laid out for (landscape on desktop, the handheld orientation on phones).
func ui_size() -> Vector2i:
	if not mobile_layout:
		return DESKTOP_SIZE
	var orientation := int(ProjectSettings.get_setting("display/window/handheld/orientation", 1))
	var portrait := orientation in [DisplayServer.SCREEN_PORTRAIT, DisplayServer.SCREEN_REVERSE_PORTRAIT, DisplayServer.SCREEN_SENSOR_PORTRAIT]
	return PHONE_PORTRAIT if portrait else Vector2i(PHONE_PORTRAIT.y, PHONE_PORTRAIT.x)


func is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


func set_fullscreen(enabled: bool) -> void:
	if mobile_layout or _is_embedded():
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)
	if not enabled:
		_resize_window(DESKTOP_WINDOW)
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("display", "fullscreen", enabled)
	config.save(SETTINGS_PATH)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen") and not event.is_echo():
		set_fullscreen(not is_fullscreen())
		get_viewport().set_input_as_handled()
		return
	if mobile_layout:
		return
	if event is InputEventScreenTouch:
		_set_touch_mode(true)
	elif event is InputEventKey or event is InputEventJoypadButton \
			or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5) \
			or (event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION):
		_set_touch_mode(false)


func _set_touch_mode(enabled: bool) -> void:
	if touch_mode != enabled:
		touch_mode = enabled
		touch_mode_changed.emit(enabled)


func _load_fullscreen() -> bool:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return false
	return bool(config.get_value("display", "fullscreen", false))


## Sets the window size (at most 85% of the screen) and centers it.
func _resize_window(size: Vector2i) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var fit := minf(1.0, minf(screen.size.x * 0.85 / size.x, screen.size.y * 0.85 / size.y))
	var window := get_window()
	window.size = Vector2i(Vector2(size) * fit)
	window.position = screen.position + (screen.size - window.size) / 2


## Running inside the editor's Game view: the editor owns the window.
func _is_embedded() -> bool:
	return Engine.is_embedded_in_editor() or DisplayServer.get_name() == "headless"
