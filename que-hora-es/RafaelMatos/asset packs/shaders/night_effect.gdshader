shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

uniform float strength : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float brightness : hint_range(0.0, 1.0, 0.01) = 0.45;
uniform float saturation : hint_range(0.0, 1.0, 0.01) = 0.65;
uniform vec4 night_tint : source_color = vec4(0.58, 0.68, 1.0, 1.0);

uniform float vignette_strength : hint_range(0.0, 1.0, 0.01) = 0.45;
uniform float vignette_radius : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform float vignette_softness : hint_range(0.01, 1.0, 0.01) = 0.85;

void fragment() {
	vec3 scene_color = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
	float luminance = dot(scene_color, vec3(0.2126, 0.7152, 0.0722));
	vec3 muted_color = mix(vec3(luminance), scene_color, saturation);
	vec3 night_color = muted_color * night_tint.rgb * brightness;
	vec2 centered_uv = (SCREEN_UV - vec2(0.5)) * 2.0;
	float vignette = smoothstep(vignette_radius,
		vignette_radius + vignette_softness, length(centered_uv));
	night_color *= 1.0 - vignette * vignette_strength;

	COLOR = vec4(mix(scene_color, night_color, strength), 1.0);
}
