shader_type spatial;
// Recolors one hue of a palette-textured model (e.g. a soldier's red crest) to a player's color,
// keeping each pixel's brightness so the shading stays. Used by Unit._apply_color().

uniform sampler2D albedo_tex : filter_linear_mipmap, repeat_enable;
// Target color in sRGB (no source_color hint: we do the hue math in sRGB like the artist's palette).
uniform vec3 target_color = vec3(0.24, 0.56, 0.91);
// Hue to replace (0..1), how far around it, and the minimum saturation (skips skin / wood tones).
uniform float key_hue = 0.0;
uniform float hue_range = 0.03;
uniform float min_saturation = 0.6;
// Typical brightness of the replaced swatches; darker/brighter pixels keep their relative shade.
uniform float reference_value = 0.95;

vec3 rgb_to_hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	vec3 color = texture(albedo_tex, UV).rgb;
	vec3 hsv = rgb_to_hsv(color);
	float hue_distance = abs(fract(hsv.x - key_hue + 0.5) - 0.5);
	if (hue_distance < hue_range && hsv.y > min_saturation) {
		vec3 target = rgb_to_hsv(target_color);
		color = hsv_to_rgb(vec3(target.x, target.y, clamp(hsv.z * target.z / reference_value, 0.0, 1.0)));
	}
	ALBEDO = srgb_to_linear(color);
	ROUGHNESS = 1.0;
}
