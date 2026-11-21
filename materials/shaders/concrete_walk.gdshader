shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D concrete_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_ao : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float texture_scale = 0.53;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.42;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.45;
uniform vec3 warm_tint : source_color = vec3(0.80, 0.79, 0.76);
varying vec3 world_pos;

vec2 rotate_uv(vec2 uv) {
	return mat2(vec2(0.891, -0.454), vec2(0.454, 0.891)) * uv;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 sample_uv = world_pos.xz * texture_scale;
	vec2 macro_uv = rotate_uv(sample_uv * 0.21);

	vec3 albedo_fine = texture(concrete_albedo, sample_uv).rgb;
	vec3 albedo_macro = texture(concrete_albedo, macro_uv).rgb;
	float slab_weathering = texture(concrete_roughness, world_pos.xz * 0.045).r;
	ALBEDO = mix(albedo_fine, albedo_macro, 0.30) * warm_tint * mix(0.89, 1.06, slab_weathering);

	float ao_val = texture(concrete_ao, sample_uv).r;
	AO = mix(1.0, ao_val, ao_strength);

	float rough_fine = texture(concrete_roughness, sample_uv).r;
	float rough_macro = texture(concrete_roughness, macro_uv).r;
	ROUGHNESS = clamp(mix(0.74, 0.94, mix(rough_fine, rough_macro, 0.30)), 0.72, 0.96);

	vec2 normal_detail = texture(concrete_normal, sample_uv).rg * 2.0 - 1.0;
	vec2 shallow_relief = texture(concrete_normal, macro_uv).rg * 2.0 - 1.0;
	vec2 height_normal = (normal_detail * 0.72 + shallow_relief * 0.28) * normal_strength;
	NORMAL = normalize(NORMAL + mat3(VIEW_MATRIX) * vec3(height_normal.x, 0.0, -height_normal.y));
	METALLIC = 0.0;
	SPECULAR = 0.25;
}
