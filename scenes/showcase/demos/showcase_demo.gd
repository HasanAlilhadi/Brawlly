class_name ShowcaseDemo
extends Node3D
## One station of the showcase (scenes/showcase/showcase.tscn): a title on a sign and the spot the camera
## flies to (`view_offset`, looking at `look_offset`, both relative to the station). Extend it for a new demo.

@export var title: String = "Demo"
@export_multiline var description: String = ""
@export var view_offset: Vector3 = Vector3(0, 9, 14)
@export var look_offset: Vector3 = Vector3.ZERO
## Size of the station's ground patch (x, z).
@export var area: Vector2 = Vector2(20, 14)
