shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D facade_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D facade_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D facade_occlusion : filter_linear_mipmap, repeat_disable;
uniform sampler2D glazing : filter_linear_mipmap, repeat_disable;
uniform float wall_roughness = 0.84;
uniform float wall_normal_strength = 0.47;
uniform vec3 wall_tint : source_color = vec3(1.0);
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float pane = texture(glazing, UV).r;
	vec3 facade = texture(facade_albedo, UV).rgb;
	float patina = 0.5 + 0.25 * sin(world_pos.x * 0.073 + world_pos.z * 0.064)
		+ 0.25 * sin(world_pos.x * 0.038 - world_pos.z * 0.093);
	facade *= wall_tint * mix(vec3(0.84, 0.85, 0.86), vec3(1.08, 1.04, 0.99), patina);
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, 4.0);
	vec3 blue_glass = mix(vec3(0.045, 0.077, 0.097), vec3(0.09, 0.14, 0.19), fresnel);
	ALBEDO = mix(facade, blue_glass, pane);
	ROUGHNESS = mix(wall_roughness, mix(0.16, 0.23, patina), pane);
	METALLIC = 0.0;
	SPECULAR = mix(0.32, 0.77, pane);
	NORMAL_MAP = mix(texture(facade_normal, UV).rgb, vec3(0.5, 0.5, 1.0), pane);
	NORMAL_MAP_DEPTH = wall_normal_strength;
	AO = mix(texture(facade_occlusion, UV).r, 1.0, pane);
	AO_LIGHT_AFFECT = 0.18;
}
