shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D asphalt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D aggregate_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D edge_distance : filter_linear, repeat_disable;
uniform vec2 tile_origin;
uniform float texture_scale = 0.46;
uniform float roughness_value : hint_range(0.65, 0.75) = 0.72;
uniform vec3 tint : source_color = vec3(0.94, 0.92, 0.89);
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 pavement_uv = world_pos.xz * texture_scale;
	vec3 asphalt = texture(asphalt_albedo, pavement_uv).rgb;
	float curb = texture(edge_distance, clamp((world_pos.xz - tile_origin) / 2000.0, vec2(0.0), vec2(1.0))).r;
	ALBEDO = asphalt * tint * (1.0 - 0.17 * curb);
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
	SPECULAR = 0.20;
	vec2 grain = texture(aggregate_normal, pavement_uv).rg * 2.0 - 1.0;
	NORMAL = normalize(NORMAL + mat3(VIEW_MATRIX) * vec3(grain.x, 0.0, -grain.y) * 0.20);
}
