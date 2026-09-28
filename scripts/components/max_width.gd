class_name MaxWidth
extends Control
## Attach to a full-width Control (e.g. a menu PanelContainer anchored left/right with side margins):
## on wide screens it stays centered and at most `max_width` wide; on narrow ones (phones) it keeps
## `margin` on each side. Top / bottom anchors and offsets are left as they are in the scene.

@export var max_width: float = 1000.0
@export var margin: float = 24.0


func _ready() -> void:
	get_viewport().size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	var parent_width := get_parent_area_size().x
	var width := minf(max_width, parent_width - margin * 2.0)
	anchor_left = 0.5
	anchor_right = 0.5
	offset_left = -width * 0.5
	offset_right = width * 0.5
