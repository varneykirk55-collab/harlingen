shader_type sky;
render_mode disable_fog;

uniform vec3 zenith : source_color = vec3(0.075, 0.34, 0.75);
uniform vec3 mid_sky : source_color = vec3(0.16, 0.51, 0.87);
uniform vec3 horizon : source_color = vec3(0.68, 0.82, 0.94);
uniform vec3 lower_sky : source_color = vec3(0.57, 0.57, 0.50);
uniform vec3 cirrus_color : source_color = vec3(0.91, 0.95, 0.99);

float cirrus(vec3 direction, float azimuth, float elevation, float length_scale, float phase) {
	float angle = atan(direction.z, direction.x) - azimuth;
	float x = atan(sin(angle), cos(angle)) / length_scale;
	float y = (direction.y - elevation + 0.045 * x) / 0.041;
	float envelope = exp(-1.8 * x * x - 0.85 * y * y);
	float warp = y + 0.28 * sin(x * 5.4 + phase) + 0.19 * sin(x * 12.0);
	float strands = 0.54 + 0.28 * sin(warp * 6.7 + x * 3.1)
		+ 0.13 * sin(warp * 13.0 - x * 6.2);
	return smoothstep(0.25, 0.78, envelope * strands);
}

void sky() {
	vec3 direction = normalize(EYEDIR);
	float altitude = max(direction.y, 0.0);
	vec3 base = mix(horizon, mid_sky, smoothstep(0.0, 0.46, pow(altitude, 0.60)));
	base = mix(base, zenith, smoothstep(0.26, 1.0, altitude));
	base = mix(base, lower_sky, smoothstep(0.0, 0.30, -direction.y));

	if (direction.y > 0.07) {
		float wisps = cirrus(direction, 0.24, 0.28, 0.24, 0.6) * 0.62;
		wisps += cirrus(direction, -2.12, 0.36, 0.18, 1.9) * 0.47;
		wisps += cirrus(direction, 2.63, 0.21, 0.16, 3.4) * 0.39;
		wisps += cirrus(direction, -0.38, 0.29, 0.21, 2.6) * 0.58;
		wisps += cirrus(direction, -0.98, 0.19, 0.17, 4.4) * 0.44;
		wisps += cirrus(direction, 1.35, 0.34, 0.20, 1.1) * 0.50;
		base = mix(base, cirrus_color, wisps * 0.50);
	}

	if (LIGHT0_ENABLED) {
		float alignment = dot(direction, LIGHT0_DIRECTION);
		float glow = smoothstep(0.980, 1.0, alignment);
		base += LIGHT0_COLOR * glow * glow * 0.12;
		if (!AT_CUBEMAP_PASS) {
			float disk = smoothstep(0.999985, 0.999991, alignment);
			base = mix(base, vec3(1.0, 0.98, 0.88) * 2.6, disk);
		}
	}
	COLOR = base;
}
