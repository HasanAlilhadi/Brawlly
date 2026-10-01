extends Node3D
## Showcase: every demo station (ShowcaseDemo children of `Demos`) in one world to fly around.
## Fly with FlyCamera3D (right mouse: look, WASD, E / Q up / down, Shift fast, wheel: speed);
## 1–9 fly to a station, Esc goes back to the main menu. New demo = a ShowcaseDemo scene added under Demos
## (they are laid out in a row, `SPACING` apart).
## Run: open scenes/showcase/showcase.tscn and press F6, or "$G" --path . res://scenes/showcase/showcase.tscn

const SPACING := 8.0

@onready var camera: FlyCamera3D = $FlyCamera
@onready var demos: Node3D = $Demos
@onready var help: Label = %Help

var _stations: Array[ShowcaseDemo] = []


func _ready() -> void:
	var x := 0.0
	for child in demos.get_children():
		if child is ShowcaseDemo:
			var demo := child as ShowcaseDemo
			x += demo.area.x * 0.5
			demo.position = Vector3(x, 0, 0)
			x += demo.area.x * 0.5 + SPACING
			_stations.append(demo)
			_add_sign(demo, _stations.size())
	_help_text()
	if not _stations.is_empty():
		_go_to(0, 0.0)


func _add_sign(demo: ShowcaseDemo, number: int) -> void:
	var patch := MeshInstance3D.new()
	patch.mesh = BoxMesh.new()
	(patch.mesh as BoxMesh).size = Vector3(demo.area.x, 0.04, demo.area.y)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.74, 0.4)
	patch.material_override = mat
	patch.position = Vector3(0, 0.01, 0)
	demo.add_child(patch)
	var sign := Label3D.new()
	sign.text = "%d. %s" % [number, demo.title]
	sign.pixel_size = 0.03
	sign.outline_size = 16
	sign.position = Vector3(0, 6.2, -demo.area.y * 0.5)
	demo.add_child(sign)
	if demo.description != "":
		var sub := Label3D.new()
		sub.text = demo.description
		sub.pixel_size = 0.014
		sub.outline_size = 10
		sub.width = 1400
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.position = Vector3(0, 5.2, -demo.area.y * 0.5)
		demo.add_child(sub)


func _help_text() -> void:
	var lines: PackedStringArray = ["Right mouse: look   WASD: fly   E / Q: up / down   Shift: fast   Wheel: speed   Esc: menu"]
	for i in _stations.size():
		lines.append("%d  %s" % [i + 1, _stations[i].title])
	help.text = "\n".join(lines)


func _go_to(index: int, duration: float = 0.8) -> void:
	var demo := _stations[index]
	var at := demo.global_position + demo.view_offset
	var target := demo.global_position + demo.look_offset
	if duration <= 0.0:
		camera.global_transform = Transform3D(Basis.looking_at(target - at), at)
		camera.sync_angles()
	else:
		camera.fly_to(at, target, duration)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key >= KEY_1 and key <= KEY_9 and key - KEY_1 < _stations.size():
			_go_to(key - KEY_1)
		elif key == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			Transition.change_scene("res://scenes/ui/main_menu.tscn")
