shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D roof_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roof_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roof_roughness_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roof_ao_map : filter_linear_mipmap_anisotropic, repeat_enable;

uniform vec3 roof_tint : source_color = vec3(1.0);
uniform float roof_normal_strength = 0.65;
uniform float roof_scale = 0.25;
uniform float roof_roughness = 0.85;
uniform float roof_metallic = 0.0;
uniform float roof_ao_strength = 0.65;
uniform float anti_tile_rotate = 1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 uv_a = p * roof_scale;
	vec2 uv_rot = mat2(vec2(0.7986, 0.6018), vec2(-0.6018, 0.7986)) * (uv_a * 0.83) + vec2(17.3, 41.7);
	vec2 uv_shift = uv_a + vec2(13.7, 29.3);
	vec2 uv_b = mix(uv_shift, uv_rot, anti_tile_rotate);

	float anti_tile = smoothstep(0.22, 0.78, 0.5 + 0.5 * sin(p.x * 0.041 + p.y * 0.037) * cos(p.x * 0.023 - p.y * 0.051));
	float exposure = 0.5 + 0.27 * sin(p.x * 0.019 + p.y * 0.029)
		+ 0.23 * sin(p.x * 0.052 - p.y * 0.022);

	vec3 alb_a = texture(roof_albedo, uv_a).rgb;
	vec3 alb_b = texture(roof_albedo, uv_b).rgb;
	vec3 texture_color = mix(alb_a, alb_b, anti_tile) * roof_tint;

	vec2 nor_a = texture(roof_normal, uv_a).rg * 2.0 - 1.0;
	vec2 nor_b = texture(roof_normal, uv_b).rg * 2.0 - 1.0;
	vec2 relief = mix(nor_a, nor_b, anti_tile);

	float r_a = texture(roof_roughness_map, uv_a).r;
	float r_b = texture(roof_roughness_map, uv_b).r;
	float r_map = mix(r_a, r_b, anti_tile);

	float ao_a = texture(roof_ao_map, uv_a).r;
	float ao_b = texture(roof_ao_map, uv_b).r;
	float ao_map = mix(ao_a, ao_b, anti_tile);

	ALBEDO = texture_color * mix(vec3(0.80, 0.82, 0.85), vec3(1.14, 1.10, 1.03), exposure);
	ROUGHNESS = clamp(roof_roughness + (r_map - 0.5) * 0.40 + (exposure - 0.5) * 0.08, 0.25, 0.96);
	METALLIC = roof_metallic;
	SPECULAR = mix(0.32, 0.55, roof_metallic);
	AO = mix(1.0, ao_map, roof_ao_strength);
	AO_LIGHT_AFFECT = 0.35;

	if (roof_normal_strength > 0.0) {
		NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(relief.x, 0.0, -relief.y, 0.0)).xyz * roof_normal_strength);
	}
}
