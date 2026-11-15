shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, fog_disabled;

uniform vec4 glow_color : source_color = vec4(1.0, 0.72, 0.25, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.93, 0.70, 1.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.0;

uniform vec3 bounds_min = vec3(0.0);
uniform vec3 bounds_size = vec3(1.0);

uniform float border_width = 0.07;
uniform float border_strength = 2.4;
uniform float fill_strength = 0.08;
uniform float fresnel_power = 2.0;
uniform float fresnel_strength = 1.6;
uniform float sweep_speed = 0.5;
uniform float sweep_width = 0.09;
uniform float sweep_strength = 1.1;
uniform float pulse_speed = 2.6;
uniform float pulse_amount = 0.2;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec3 uvw = (local_pos - bounds_min) / max(bounds_size, vec3(0.0001));

	vec2 d = min(uvw.xy, 1.0 - uvw.xy) * bounds_size.xy;
	float edge_dist = min(d.x, d.y);
	float border = pow(1.0 - smoothstep(0.0, border_width, edge_dist), 1.5);

	float diag = uvw.x * 0.6 + uvw.y * 0.4;
	float pos = fract(TIME * sweep_speed) * (1.0 + sweep_width * 4.0) - sweep_width * 2.0;
	float sweep = exp(-pow((diag - pos) / sweep_width, 2.0));

	float scan = 0.75 + 0.25 * sin(uvw.y * bounds_size.y * 45.0 - TIME * 2.5);

	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), fresnel_power);

	float pulse = 1.0 + sin(TIME * pulse_speed) * pulse_amount;

	vec3 col = glow_color.rgb * (fill_strength * scan + fres * fresnel_strength + border * border_strength) * pulse;
	col += core_color.rgb * (sweep * sweep_strength * (0.35 + border) + border * 0.5);

	ALBEDO = col * intensity;
}
