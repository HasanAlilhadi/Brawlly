shader_type spatial;
// Interaction highlight: use as a MeshInstance3D's material_overlay. Adds a soft, pulsing glow on top of the
// model — a bright rim where faces turn away from the camera plus a light tint over everything — so the
// object itself shows "you can use this" (no ground ring needed). Cheap: one unshaded additive pass.
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 glow_color : source_color = vec4(1.0, 0.82, 0.35, 1.0);
// Rim brightness at grazing angles and its falloff (higher power = thinner rim).
uniform float rim_strength : hint_range(0.0, 2.0) = 0.5;
uniform float rim_power : hint_range(0.5, 8.0) = 2.5;
// Flat tint over the whole surface.
uniform float fill_strength : hint_range(0.0, 1.0) = 0.07;
// Pulses per second (0 = steady) and how deep the pulse dips (0..1).
uniform float pulse_speed = 1.4;
uniform float pulse_depth : hint_range(0.0, 1.0) = 0.55;

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power) * rim_strength;
	float pulse = 1.0 - pulse_depth * (0.5 + 0.5 * sin(TIME * pulse_speed * TAU));
	ALBEDO = glow_color.rgb * (rim + fill_strength) * pulse * glow_color.a;
}
