shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wear_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ao_map : filter_linear_mipmap_anisotropic, repeat_enable;

uniform vec3 paint_color : source_color = vec3(0.91, 0.90, 0.84);
uniform float texture_scale = 0.75;
uniform float wear_amount : hint_range(0.0, 1.0) = 0.28;

instance uniform vec3 tile_tint = vec3(1.0, 1.0, 1.0);

varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 uv = world_xz * texture_scale;
	float aggregate = texture(wear_map, world_xz * 1.35).r;
	float streaks = texture(wear_map, world_xz * vec2(0.32, 1.05)).r;
	float wearing = smoothstep(0.16, 0.72, 0.72 * aggregate + 0.28 * streaks);
	float paint_mask = mix(1.0, mix(0.54, 1.0, wearing), wear_amount + 0.45);

	vec3 grain_tex = texture(albedo_map, uv).rgb;
	float grain_luma = dot(grain_tex, vec3(0.299, 0.587, 0.114));

	ALBEDO = paint_color * tile_tint * paint_mask * mix(0.88, 1.06, grain_luma);
	AO = mix(1.0, texture(ao_map, uv).r, 0.35);
	ROUGHNESS = clamp(mix(0.76, 0.94, aggregate), 0.72, 0.96);
	METALLIC = 0.0;
	SPECULAR = 0.18;

	vec2 n = texture(normal_map, uv).rg * 2.0 - 1.0;
	NORMAL = normalize(NORMAL + mat3(VIEW_MATRIX) * vec3(n.x, 0.0, -n.y) * 0.30);
}
