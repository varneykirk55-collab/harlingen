shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wear_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(0.92);
uniform float texture_scale = 0.52;
uniform float concrete = 0.0;
varying vec2 world_xz;

float stable_noise(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 uv = world_xz * texture_scale;
	vec3 base = texture(albedo_map, uv).rgb;
	float fine = texture(wear_map, uv * 1.7).r;
	float macro = texture(wear_map, world_xz * 0.007).r;
	float block = stable_noise(floor((world_xz + 19.0 * macro) / 58.0));
	float tone = mix(mix(0.77, 1.18, block * 0.79 + macro * 0.21), mix(0.83, 1.07, fine), concrete);
	ALBEDO = base * tint * tone;
	ROUGHNESS = mix(mix(0.67, 0.79, fine), mix(0.73, 0.90, fine), concrete);
	SPECULAR = 0.23;
	vec2 detail = texture(detail_normal, uv).rg * 2.0 - 1.0;
	NORMAL = normalize(NORMAL + mat3(VIEW_MATRIX) * vec3(detail.x, 0.0, -detail.y) * 0.22);
}
