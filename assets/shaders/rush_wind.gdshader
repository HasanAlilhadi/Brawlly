shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform float age = 0.0;
uniform float strength = 1.0;

void vertex() {
	// The head stretches and flickers independently of the streaming wake.
	float head = 1.0 - smoothstep(0.15, 0.65, UV.x);
	float breath = sin(age * 21.0) * 0.22 + sin(age * 34.0) * 0.12;
	VERTEX.x *= 1.0 + breath * head;
	VERTEX.z += (sin(age * 18.0) * 0.045 + sin(age * 29.0) * 0.02) * head;
	float wake = smoothstep(0.12, 0.9, UV.x);
	float wave = sin(UV.x * 17.0 - age * 23.0);
	float flutter = sin(UV.x * 31.0 - age * 37.0);
	VERTEX.x += (wave * 0.035 + flutter * 0.012) * wake;
	VERTEX.y += cos(UV.x * 19.0 - age * 26.0) * 0.022 * wake;
	VERTEX.z -= (0.5 + 0.5 * sin(age * 15.0)) * 0.09 * wake;
}

void fragment() {
	// Soft ribbon edges, tapered tips, and fast pulses flowing toward the wake.
	float head = 1.0 - smoothstep(0.15, 0.65, UV.x);
	float ripple = sin(UV.x * 36.0 - age * 32.0) * 0.09
		+ sin(UV.x * 57.0 - age * 43.0) * 0.045;
	float edge_uv = clamp(UV.y + ripple * head, 0.0, 1.0);
	float edge = pow(max(sin(edge_uv * 3.141593), 0.0), 0.7);
	float taper = smoothstep(0.0, 0.12, UV.x) * (1.0 - smoothstep(0.75, 1.0, UV.x));
	float pulse = 0.5 + 0.5 * sin(UV.x * 25.0 - age * 30.0);
	float flow = mix(1.0, 0.35 + 0.65 * pulse, smoothstep(0.15, 0.8, UV.x));
	// Moving bright fragments break up the solid white cap at the spear point.
	float flicker = 0.55 + 0.45 * (0.5 + 0.5 * sin(UV.x * 42.0 - age * 35.0));
	flow *= mix(1.0, flicker, head);
	ALBEDO = vec3(1.0);
	ALPHA = edge * taper * flow * COLOR.a * strength * (1.0 - UV.x * 0.7);
}
