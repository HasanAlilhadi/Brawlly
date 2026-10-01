shader_type spatial;
// Ranged aim path: a row of soft chevrons that drift toward the aim point, with a dark rim so they read on
// any ground. The mesh is a flat strip `width` wide and 1 long (along +Z), scaled in Z to `line_length`.
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, blend_mix;

uniform vec4 color : source_color = vec4(1.0, 0.96, 0.86, 1.0);
uniform vec4 rim_color : source_color = vec4(0.12, 0.08, 0.05, 0.55);
uniform float line_length = 5.0;
uniform float width = 0.34;
uniform float spacing = 0.5;
uniform float speed = 1.1;
uniform float thickness = 0.034;
uniform float rim = 0.026;

varying vec2 local;

void vertex() {
	local = VERTEX.xz;
}

void fragment() {
	float along = local.y * line_length;
	float across = abs(local.x);
	// One chevron per cell, tip forward (+Z).
	float cell = fract((along - TIME * speed) / spacing) * spacing - spacing * 0.5;
	float slope = 0.85;
	float d = abs(cell + across * slope) / sqrt(1.0 + slope * slope);
	float arm = width * 0.5 - rim - 0.01;
	float aa = fwidth(d) + 0.002;
	float in_arm = 1.0 - smoothstep(arm - 0.03, arm, across);
	float core = (1.0 - smoothstep(thickness - aa, thickness + aa, d)) * in_arm;
	float halo = (1.0 - smoothstep(thickness + rim - aa, thickness + rim + aa, d))
			* (1.0 - smoothstep(arm - 0.03 + rim, arm + rim, across));
	// Fade in from the hero and out just before the reticle.
	float fade = smoothstep(0.0, 0.7, along) * (1.0 - smoothstep(line_length - 0.35, line_length, along));
	vec3 col = mix(rim_color.rgb, color.rgb, core);
	float alpha = max(core * color.a, halo * rim_color.a) * fade;
	ALBEDO = col;
	ALPHA = alpha;
}
