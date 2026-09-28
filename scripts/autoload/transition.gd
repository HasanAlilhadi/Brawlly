extends CanvasLayer
## Screen fades between scenes (autoload "Transition").
##   await Transition.fade_out()            # to black
##   Transition.fade_in()                   # back from black
##   Transition.change_scene(path)          # fade out, switch scene, fade in
##   Transition.change_scene(path, false)   # stay black; the new scene calls fade_in() when ready

@export var color: Color = Color(0.05, 0.03, 0.02)

var _rect: ColorRect
var _tween: Tween


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.color = color
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.modulate.a = 0.0
	add_child(_rect)


func is_black() -> bool:
	return _rect.modulate.a >= 0.99


## Fades to black (blocks input while covered). Await it to continue once the screen is black.
func fade_out(duration: float = 0.35) -> void:
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	await _fade_to(1.0, duration)


## Fades back in from black.
func fade_in(duration: float = 0.45) -> void:
	await _fade_to(0.0, duration)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Fade out, change scene, then fade in (unless `auto_fade_in` is false — the new scene fades in itself).
func change_scene(path: String, auto_fade_in: bool = true, duration: float = 0.35) -> void:
	await fade_out(duration)
	get_tree().change_scene_to_file(path)
	if auto_fade_in:
		# Let the new scene build its first frames before revealing it.
		await get_tree().process_frame
		await get_tree().process_frame
		fade_in()


func _fade_to(alpha: float, duration: float) -> void:
	if _tween:
		_tween.kill()
	if duration <= 0.0:
		_rect.modulate.a = alpha
		return
	_tween = create_tween()
	_tween.tween_property(_rect, "modulate:a", alpha, duration * absf(_rect.modulate.a - alpha))
	await _tween.finished
