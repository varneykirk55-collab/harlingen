shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D facade_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D facade_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D facade_occlusion : filter_linear_mipmap, repeat_disable;
uniform sampler2D glazing : filter_linear_mipmap, repeat_disable;

uniform sampler2D detail_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_ao : filter_linear_mipmap_anisotropic, repeat_enable;

uniform float wall_roughness = 0.84;
uniform float wall_normal_strength = 0.47;
uniform vec3 wall_tint : source_color = vec3(1.0);
uniform float detail_scale = 0.42;
uniform float detail_albedo_strength = 0.38;
uniform float detail_normal_strength = 0.45;
uniform float detail_roughness_strength = 0.42;
uniform float detail_ao_strength = 0.55;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 triplanar_blend_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / max(w.x + w.y + w.z, 1e-5);
}

vec4 sample_triplanar(sampler2D tex, vec3 pos, vec3 w, float scale) {
	vec4 cx = texture(tex, pos.zy * scale);
	vec4 cy = texture(tex, pos.xz * scale);
	vec4 cz = texture(tex, pos.xy * scale);
	return cx * w.x + cy * w.y + cz * w.z;
}

vec3 sample_triplanar_world_normal_delta(sampler2D tex, vec3 pos, vec3 w, float scale) {
	vec2 nx = texture(tex, pos.zy * scale).rg * 2.0 - 1.0;
	vec2 ny = texture(tex, pos.xz * scale).rg * 2.0 - 1.0;
	vec2 nz = texture(tex, pos.xy * scale).rg * 2.0 - 1.0;
	return vec3(0.0, nx.y, nx.x) * w.x + vec3(ny.x, 0.0, -ny.y) * w.y + vec3(nz.x, nz.y, 0.0) * w.z;
}

void fragment() {
	float pane = texture(glazing, UV).r;
	vec3 facade = texture(facade_albedo, UV).rgb;
	float patina = 0.5 + 0.25 * sin(world_pos.x * 0.073 + world_pos.z * 0.064)
		+ 0.25 * sin(world_pos.x * 0.038 - world_pos.z * 0.093);

	vec3 w = triplanar_blend_weights(world_normal);
	vec3 d_alb = sample_triplanar(detail_albedo, world_pos, w, detail_scale).rgb;
	float d_rough = sample_triplanar(detail_roughness, world_pos, w, detail_scale).r;
	float d_ao = sample_triplanar(detail_ao, world_pos, w, detail_scale).r;
	vec3 d_norm_world = sample_triplanar_world_normal_delta(detail_normal, world_pos, w, detail_scale);

	vec3 detail_mod = mix(vec3(1.0), clamp(vec3(0.75) + d_alb * 1.15, vec3(0.72), vec3(1.22)), detail_albedo_strength);
	facade *= wall_tint * detail_mod * mix(vec3(0.88, 0.89, 0.90), vec3(1.07, 1.04, 0.99), patina);

	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, 4.0);
	vec3 blue_glass = mix(vec3(0.045, 0.077, 0.097), vec3(0.09, 0.14, 0.19), fresnel);

	ALBEDO = mix(facade, blue_glass, pane);
	float wall_r = clamp(wall_roughness + (d_rough - 0.5) * detail_roughness_strength, 0.35, 0.98);
	ROUGHNESS = mix(wall_r, mix(0.14, 0.21, patina), pane);
	METALLIC = 0.0;
	SPECULAR = mix(0.32, 0.78, pane);

	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(d_norm_world, 0.0)).xyz * detail_normal_strength * (1.0 - pane));
	NORMAL_MAP = mix(texture(facade_normal, UV).rgb, vec3(0.5, 0.5, 1.0), pane);
	NORMAL_MAP_DEPTH = wall_normal_strength;

	float wall_ao = texture(facade_occlusion, UV).r * mix(1.0, d_ao, detail_ao_strength);
	AO = mix(wall_ao, 1.0, pane);
	AO_LIGHT_AFFECT = 0.24;
}
