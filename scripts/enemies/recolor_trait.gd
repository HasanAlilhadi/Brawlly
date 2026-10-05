class_name RecolorTrait
extends EnemyComponent
## Repaints one hue of the model's palette (assets/shaders/palette_recolor.gdshader) on every peer, so one
## model makes several creatures: the vampire's red cape turns purple for the Necromancer. Items in hand keep
## their colors.

const RECOLOR_SHADER := preload("res://assets/shaders/palette_recolor.gdshader")

@export var color: Color = Color(0.5, 0.2, 0.8)
@export_range(0.0, 1.0) var key_hue: float = 0.0
@export var hue_range: float = 0.04
@export var min_saturation: float = 0.35
@export var reference_value: float = 0.8

static var _materials: Dictionary = {}


func setup(owner_enemy: Enemy) -> void:
	super(owner_enemy)
	for node in enemy.model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if enemy._in_hand(mesh_instance):
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.mesh.surface_get_material(surface) as StandardMaterial3D
			if source and source.albedo_texture:
				mesh_instance.set_surface_override_material(surface, _material(source.albedo_texture))


func _material(texture: Texture2D) -> ShaderMaterial:
	var key := "%s|%s|%.3f" % [texture.get_rid(), color.to_html(false), key_hue]
	if not _materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = RECOLOR_SHADER
		material.set_shader_parameter("albedo_tex", texture)
		material.set_shader_parameter("target_color", Vector3(color.r, color.g, color.b))
		material.set_shader_parameter("key_hue", key_hue)
		material.set_shader_parameter("hue_range", hue_range)
		material.set_shader_parameter("min_saturation", min_saturation)
		material.set_shader_parameter("reference_value", reference_value)
		_materials[key] = material
	return _materials[key]
