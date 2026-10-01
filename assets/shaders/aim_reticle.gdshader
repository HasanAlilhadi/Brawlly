shader_type spatial;
// Ranged aim reticle: a broken ring with four inward ticks and a center dot, gently breathing, with a dark rim.
// Drawn on a flat 1 × 1 quad (XZ) scaled to the reticle size.
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, blend_mix;

uniform vec4 color : source_color = vec4(1.0, 0.96, 0.86, 1.0);
uniform vec4 rim_color : source_color = vec4(0.12, 0.08, 0.05, 0.55);

varying vec2 local;

void vertex() {
	local = VERTEX.xz;
}

float band(float d, float half_width, float aa) {
	return 1.0 - smoothstep(half_width - aa, half_width + aa, abs(d));
}

void fragment() {
	vec2 p = local * 2.0;  // -1..1
	float r = length(p);
	float ang = atan(p.y, p.x) + TIME * 0.6;
	float aa = fwidth(r) * 1.2;
	float breathe = 1.0 + sin(TIME * 4.0) * 0.04;
	float radius = 0.7 * breathe;
	// Ring broken into four arcs.
	float gaps = smoothstep(0.16, 0.26, abs(sin(ang * 2.0)));
	float ring = band(r - radius, 0.055, aa) * gaps;
	float ring_rim = band(r - radius, 0.055 + 0.07, aa) * smoothstep(0.08, 0.18, abs(sin(ang * 2.0)));
	// Ticks pointing in, in the gaps.
	float tick_ang = abs(cos(ang * 2.0));
	float on_tick = smoothstep(0.985, 0.995, tick_ang);
	float tick_rad = band(r - radius * 0.72, 0.13, aa);
	float tick = on_tick * tick_rad;
	float tick_rim = smoothstep(0.96, 0.975, tick_ang) * band(r - radius * 0.72, 0.13 + 0.07, aa);
	float dot = 1.0 - smoothstep(0.08 - aa, 0.08 + aa, r);
	float dot_rim = 1.0 - smoothstep(0.15 - aa, 0.15 + aa, r);
	float core = max(max(ring, tick), dot);
	float halo = max(max(ring_rim, tick_rim), dot_rim);
	ALBEDO = mix(rim_color.rgb, color.rgb, core);
	ALPHA = max(core * color.a, halo * rim_color.a);
}
