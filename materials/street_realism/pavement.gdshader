shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wear_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ao_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(0.92);
uniform float texture_scale = 0.52;
uniform float concrete = 0.0;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.45;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.45;
varying vec2 world_xz;

float stable_noise(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

vec2 rotate_uv(vec2 uv) {
	return mat2(vec2(0.891, -0.454), vec2(0.454, 0.891)) * uv;
}

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 uv = world_xz * texture_scale;
	vec2 macro_uv = rotate_uv(uv * 0.23);

	vec3 base = mix(texture(albedo_map, uv).rgb, texture(albedo_map, macro_uv).rgb, 0.32);
	float fine = mix(texture(wear_map, uv).r, texture(wear_map, macro_uv).r, 0.28);
	float macro = texture(wear_map, world_xz * 0.007).r;
	float block = stable_noise(floor((world_xz + 19.0 * macro) / 58.0));
	float tone = mix(mix(0.82, 1.10, block * 0.79 + macro * 0.21), mix(0.85, 1.07, fine), concrete);

	ALBEDO = base * tint * tone;
	AO = mix(1.0, texture(ao_map, uv).r, ao_strength);
	ROUGHNESS = clamp(mix(mix(0.78, 0.92, fine), mix(0.76, 0.94, fine), concrete), 0.76, 0.96);
	METALLIC = 0.0;
	SPECULAR = mix(0.18, 0.24, concrete);

	vec2 detail_fine = texture(detail_normal, uv).rg * 2.0 - 1.0;
	vec2 detail_macro = texture(detail_normal, macro_uv).rg * 2.0 - 1.0;
	vec2 detail = (detail_fine * 0.72 + detail_macro * 0.28) * normal_strength;
	NORMAL = normalize(NORMAL + mat3(VIEW_MATRIX) * vec3(detail.x, 0.0, -detail.y));
}
