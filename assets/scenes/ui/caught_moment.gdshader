shader_type canvas_item;

// Drains colour, darkens the corners and tints the frame red as `amount` rises.
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 scene = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
	float grey = dot(scene, vec3(0.299, 0.587, 0.114));
	vec3 drained = mix(scene, vec3(grey) * vec3(1.0, 0.82, 0.82), amount);
	float edge = distance(UV, vec2(0.5)) * 1.4142;
	float vignette = smoothstep(0.25, 1.0, edge) * amount;
	COLOR = vec4(mix(drained, vec3(0.25, 0.0, 0.02), vignette * 0.85), 1.0);
}
