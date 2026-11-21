shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D concrete_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_roughness : filter_linear_mipmap, repeat_enable;
uniform float texture_scale = 0.53;
uniform vec3 warm_tint : source_color = vec3(0.93, 0.88, 0.78);
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 sample_uv = world_pos.xz * texture_scale;
	float slab_weathering = texture(concrete_roughness, world_pos.xz * 0.105).r;
	ALBEDO = texture(concrete_albedo, sample_uv).rgb * warm_tint * mix(0.89, 1.05, slab_weathering);
	ROUGHNESS = mix(0.75, 0.87, texture(concrete_roughness, sample_uv).r);
	vec2 normal_detail = texture(concrete_normal, sample_uv).rg * 2.0 - 1.0;
	vec2 shallow_relief = texture(concrete_normal, world_pos.xz * 0.22).rg * 2.0 - 1.0;
	vec2 height_normal = normal_detail * 0.24 + shallow_relief * 0.13;
	NORMAL = normalize(NORMAL + mat3(VIEW_MATRIX) * vec3(height_normal.x, 0.0, -height_normal.y));
	SPECULAR = 0.27;
}
