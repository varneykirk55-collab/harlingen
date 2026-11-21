shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D roof_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roof_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float roof_normal_strength = 0.0;
uniform float roof_scale = 0.44;
uniform float roof_roughness = 0.85;
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float exposure = 0.5 + 0.27 * sin(p.x * 0.019 + p.y * 0.029)
		+ 0.23 * sin(p.x * 0.052 - p.y * 0.022);
	vec3 texture_color = texture(roof_albedo, p * roof_scale).rgb;
	ALBEDO = texture_color * mix(vec3(0.70, 0.73, 0.78), vec3(1.24, 1.16, 1.05), exposure);
	ROUGHNESS = clamp(roof_roughness + (exposure - 0.5) * 0.08, 0.53, 0.92);
	SPECULAR = 0.31;
	if (roof_normal_strength > 0.0) {
		vec2 relief = texture(roof_normal, p * roof_scale).rg * 2.0 - 1.0;
		NORMAL = normalize(NORMAL + mat3(VIEW_MATRIX) * vec3(relief.x, 0.0, -relief.y) * roof_normal_strength);
	}
}
