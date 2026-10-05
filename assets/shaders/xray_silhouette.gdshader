shader_type spatial;
// Hero silhouette where walls / cover hide them: drawn only behind other geometry (inverted depth test), flat
// color, no depth write, never over the hero's own visible pixels. Used as the next pass of a hero's overlay (Unit.enable_xray()).
render_mode unshaded, depth_draw_never, depth_test_inverted, cull_back, blend_mix, shadows_disabled;
// Skip pixels where the hero itself is visible (its overlay wrote 1): no tint over its own body.
stencil_mode read, compare_not_equal, 1;

uniform vec4 color : source_color = vec4(0.35, 0.65, 1.0, 0.55);

// Pushed a little out along the normals: in front of the hero's own surface, so it never wins the depth test
// there (no tint over the visible body, whatever the depth precision).
uniform float push = 0.01;

void vertex() {
	VERTEX += NORMAL * push;
}

void fragment() {
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
