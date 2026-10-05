class_name KitProps
## Places Kenney kit models (GLB) as level pieces: scaled, turned, optionally solid (a box StaticBody3D on
## the world layer from the model's bounds, at least GameConfig.HIT_HEIGHT tall so shots stop at it and the
## AI steers around it). Used by WorldBuilder (graveyards) and the map tools (tools/build_map_*.gd).

static var _scenes: Dictionary = {}  # path -> PackedScene
static var _boxes: Dictionary = {}  # path -> AABB (unscaled)


## Adds `path` under `parent` at local `at`, turned `yaw`, scaled `scale`. `owner`: set for saved scenes.
static func place(parent: Node3D, path: String, at: Vector3, yaw: float = 0.0, scale: float = 1.0,
		solid: bool = false, owner: Node = null) -> Node3D:
	if not _scenes.has(path):
		_scenes[path] = load(path)
		var probe := (_scenes[path] as PackedScene).instantiate() as Node3D
		_boxes[path] = bounds(probe)
		probe.free()
	var instance := (_scenes[path] as PackedScene).instantiate() as Node3D
	instance.position = at
	instance.rotation.y = yaw
	instance.scale = Vector3.ONE * scale
	parent.add_child(instance)
	if owner:
		instance.owner = owner
	if solid:
		add_box(instance, _boxes[path], scale, owner)
	return instance


## A world-layer box over `box` (in `node`'s space, scaled by `scale`), at least HIT_HEIGHT tall.
static func add_box(node: Node3D, box: AABB, scale: float = 1.0, owner: Node = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Solid"
	body.collision_layer = GameConfig.LAYER_WORLD
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(box.size.x, 0.2), maxf(box.size.y, GameConfig.HIT_HEIGHT / scale), maxf(box.size.z, 0.2))
	var collision := CollisionShape3D.new()
	collision.name = "Shape"
	collision.shape = shape
	collision.position = box.get_center() if box.size.y * scale >= GameConfig.HIT_HEIGHT \
			else Vector3(box.get_center().x, shape.size.y * 0.5, box.get_center().z)
	body.add_child(collision)
	node.add_child(body)
	if owner:
		body.owner = owner
		collision.owner = owner
	return body


## Bounds of every mesh in a model, in the model's own space.
static func bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mesh as MeshInstance3D
		var transform := Transform3D()
		var walker: Node = mesh_instance
		while walker != node:
			transform = (walker as Node3D).transform * transform
			walker = walker.get_parent()
		var part := transform * mesh_instance.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box
