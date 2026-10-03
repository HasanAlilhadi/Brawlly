shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, blend_mix;

uniform vec4 paint_color : source_color = vec4(0.94, 0.72, 0.35, 1.0);
uniform vec4 earth_color : source_color = vec4(0.39, 0.23, 0.10, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform float active : hint_range(0.0, 1.0) = 0.0;

float line_distance(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	return length(p - a - ab * clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0));
}

// A simple painted arrow: wooden shaft, broad point and two feather strokes.
float arrow(vec2 p, float width, float aa) {
	float shaft = line_distance(p, vec2(0.0, -0.13), vec2(0.0, 0.105));
	float feathers = min(line_distance(p, vec2(-0.035, -0.14), vec2(0.0, -0.105)),
			line_distance(p, vec2(0.035, -0.14), vec2(0.0, -0.105)));
	float strokes = 1.0 - smoothstep(width - aa, width + aa, min(shaft, feathers));
	float point = (1.0 - smoothstep(-aa, aa, abs(p.x) - (0.17 - p.y) * 0.65))
			* smoothstep(0.105 - aa, 0.105 + aa, p.y)
			* (1.0 - smoothstep(0.17 - aa, 0.17 + aa, p.y));
	return max(strokes, point);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	float aa = max(fwidth(radius), 0.002);
	float inside = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, radius);
	float angle = atan(p.y, p.x);

	// Slightly uneven brush edges stay within the real circular footprint.
	float brush = sin(angle * 11.0 + 0.8) * 0.0025 + sin(angle * 23.0) * 0.0015;
	float stroke_distance = abs(radius - (0.976 + brush));
	float outline = 1.0 - smoothstep(0.019 - aa, 0.019 + aa, stroke_distance);
	float paint = 1.0 - smoothstep(0.011 - aa, 0.011 + aa, stroke_distance);
	float worn = 0.82 + 0.18 * sin(angle * 17.0 + radius * 130.0);

	// Crossed arrows match the game's simple wooden weapons and warm UI.
	vec2 left_arrow = vec2(p.x + p.y, p.y - p.x) * 0.70710678;
	vec2 right_arrow = vec2(p.x - p.y, p.y + p.x) * 0.70710678;
	float emblem_outline = max(arrow(left_arrow, 0.013, aa), arrow(right_arrow, 0.013, aa));
	float emblem = max(arrow(left_arrow, 0.007, aa), arrow(right_arrow, 0.007, aa));
	float dark = max(outline * 0.65, emblem_outline * 0.5);
	float light = max(paint * worn * 0.9, emblem * 0.65);
	float fill = inside * 0.025;
	float alpha = max(dark, light) + fill;
	ALBEDO = mix(earth_color.rgb, paint_color.rgb, clamp((light + fill) / max(alpha, 0.001), 0.0, 1.0));
	ALPHA = min(alpha, 0.9) * opacity * inside * (1.0 - active * 0.025 * (1.0 + sin(TIME * 2.0)));
}
