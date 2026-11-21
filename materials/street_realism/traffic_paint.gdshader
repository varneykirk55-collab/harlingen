shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D wear_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 paint_color : source_color = vec3(0.90, 0.89, 0.83);
varying vec2 pavement;

void vertex() {
	pavement = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float aggregate = texture(wear_map, pavement * 2.9).r;
	float streaks = texture(wear_map, pavement * vec2(0.52, 1.8)).r;
	float wearing = smoothstep(0.22, 0.66, 0.77 * aggregate + 0.23 * streaks);
	ALBEDO = paint_color * mix(0.43, 1.0, wearing);
	ROUGHNESS = 0.84;
	SPECULAR = 0.17;
}
