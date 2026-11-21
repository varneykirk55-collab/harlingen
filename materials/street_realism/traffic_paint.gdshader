shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wear_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ao_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 paint_color : source_color = vec3(0.90, 0.89, 0.83);
uniform float texture_scale = 0.65;
varying vec2 pavement;

void vertex() {
	pavement = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 uv = pavement * texture_scale;
	float aggregate = texture(wear_map, pavement * 1.4).r;
	float streaks = texture(wear_map, pavement * vec2(0.35, 1.1)).r;
	float wearing = smoothstep(0.18, 0.68, 0.75 * aggregate + 0.25 * streaks);

	vec3 grain_tex = texture(albedo_map, uv).rgb;
	float grain_luma = dot(grain_tex, vec3(0.299, 0.587, 0.114));
	ALBEDO = paint_color * mix(0.46, 1.0, wearing) * mix(0.86, 1.08, grain_luma);
	AO = mix(1.0, texture(ao_map, uv).r, 0.35);
	ROUGHNESS = clamp(mix(0.76, 0.94, aggregate), 0.72, 0.96);
	METALLIC = 0.0;
	SPECULAR = 0.18;

	vec2 n = texture(normal_map, uv).rg * 2.0 - 1.0;
	NORMAL = normalize(NORMAL + mat3(VIEW_MATRIX) * vec3(n.x, 0.0, -n.y) * 0.30);
}
