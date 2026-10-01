class_name AimCursor
extends RefCounted
## Mouse cursor for aiming, drawn in code: `Input.set_custom_mouse_cursor(AimCursor.make(), …, size / 2)`.

## Small crosshair for ranged aiming: a center dot and four short strokes, white with a soft dark rim.
## Drawn here (anti-aliased) at the screen's scale so it stays crisp and small on high-DPI screens.
static func make() -> ImageTexture:
	var k := clampf(DisplayServer.screen_get_scale(), 1.0, 3.0)
	var size := int(ceil(25.0 * k)) | 1
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var p := Vector2(x - c, y - c) / k
			# Distance to the shape: the dot, or the nearest stroke (along an axis, from 5.5 to 10 out).
			var d := p.length() - 1.5
			var along := maxf(absf(p.x), absf(p.y))
			var across := minf(absf(p.x), absf(p.y))
			var stroke := Vector2(maxf(maxf(5.5 - along, along - 10.0), 0.0), across).length() - 0.9
			d = minf(d, stroke)
			var core := clampf(0.5 - d * k, 0.0, 1.0)
			var rim := clampf(0.5 - (d - 1.0) * k, 0.0, 1.0) * 0.6
			var alpha := maxf(core, rim)
			if alpha <= 0.0:
				continue
			var shade := lerpf(0.08, 1.0, core / alpha)
			image.set_pixel(x, y, Color(shade, shade, shade * 0.96, alpha))
	return ImageTexture.create_from_image(image)
