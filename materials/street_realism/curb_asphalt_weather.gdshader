shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D asphalt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D aggregate_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_ao : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D edge_distance : filter_linear, repeat_disable;
uniform vec2 tile_origin;
uniform float texture_scale = 0.46;
uniform float roughness_value : hint_range(0.55, 0.95) = 0.84;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.50;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.45;
uniform vec3 tint : source_color = vec3(0.38, 0.39, 0.41);
varying vec3 world_pos;

vec2 rotate_uv(vec2 uv) {
	return mat2(vec2(0.891, -0.454), vec2(0.454, 0.891)) * uv;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 pavement_uv = world_pos.xz * texture_scale;
	vec2 macro_uv = rotate_uv(pavement_uv * 0.23);

	vec3 albedo_fine = texture(asphalt_albedo, pavement_uv).rgb;
	vec3 albedo_macro = texture(asphalt_albedo, macro_uv).rgb;
	vec3 asphalt = mix(albedo_fine, albedo_macro, 0.34);

	float curb = texture(edge_distance, clamp((world_pos.xz - tile_origin) / 2000.0, vec2(0.0), vec2(1.0))).r;
	float macro = texture(asphalt_albedo, world_pos.xz * 0.018).r;
	float block = fract(sin(dot(floor((world_pos.xz + 17.0 * macro) / 56.0), vec2(127.1, 311.7))) * 43758.5453123);
	float aging = mix(0.82, 1.10, block * 0.8 + macro * 0.2);

	float ao_val = texture(asphalt_ao, pavement_uv).r;
	ALBEDO = asphalt * tint * aging * (1.0 - 0.17 * curb);
	AO = mix(1.0, ao_val, ao_strength);

	float rough_fine = texture(asphalt_roughness, pavement_uv).r;
	float rough_macro = texture(asphalt_roughness, macro_uv).r;
	ROUGHNESS = clamp(mix(rough_fine, rough_macro, 0.30) * (roughness_value / 0.72), 0.78, 0.96);
	METALLIC = 0.0;
	SPECULAR = 0.18;

	vec2 grain_fine = texture(aggregate_normal, pavement_uv).rg * 2.0 - 1.0;
	vec2 grain_macro = texture(aggregate_normal, macro_uv).rg * 2.0 - 1.0;
	vec2 grain = grain_fine * 0.72 + grain_macro * 0.28;
	NORMAL = normalize(NORMAL + mat3(VIEW_MATRIX) * vec3(grain.x, 0.0, -grain.y) * normal_strength);
}
