shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ao_map : filter_linear_mipmap_anisotropic, repeat_enable;

uniform vec3 tint : source_color = vec3(0.40, 0.41, 0.42);
uniform float texture_scale = 0.45;
uniform float concrete_mode : hint_range(0.0, 1.0) = 0.0;
uniform float roughness_min : hint_range(0.4, 0.95) = 0.76;
uniform float roughness_max : hint_range(0.5, 0.98) = 0.95;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.48;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.45;
uniform float specular_strength : hint_range(0.0, 0.5) = 0.20;

instance uniform vec3 tile_tint = vec3(1.0, 1.0, 1.0);
instance uniform float tile_wear = 0.0;

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
	vec2 macro_uv = rotate_uv(uv * 0.21);

	vec3 base = mix(texture(albedo_map, uv).rgb, texture(albedo_map, macro_uv).rgb, 0.34);
	float fine_rough = mix(texture(roughness_map, uv).r, texture(roughness_map, macro_uv).r, 0.30);
	float macro_var = texture(roughness_map, world_xz * 0.017).r;
	float patch_cell = stable_noise(floor((world_xz + 17.0 * macro_var) / 56.0));

	float aging = mix(
		mix(0.84, 1.09, patch_cell * 0.78 + macro_var * 0.22),
		mix(0.88, 1.06, fine_rough * 0.65 + macro_var * 0.35),
		concrete_mode
	);

	ALBEDO = base * tint * tile_tint * aging;
	AO = mix(1.0, texture(ao_map, uv).r, ao_strength);
	ROUGHNESS = clamp(mix(roughness_min, roughness_max, fine_rough) + tile_wear * 0.04, 0.65, 0.98);
	METALLIC = 0.0;
	SPECULAR = specular_strength;

	vec2 n_fine = texture(normal_map, uv).rg * 2.0 - 1.0;
	vec2 n_macro = texture(normal_map, macro_uv).rg * 2.0 - 1.0;
	vec2 n = (n_fine * 0.72 + n_macro * 0.28) * normal_strength;
	NORMAL = normalize(NORMAL + mat3(VIEW_MATRIX) * vec3(n.x, 0.0, -n.y));
}
