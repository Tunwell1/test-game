shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, fog_disabled;

uniform vec4 line_color : source_color = vec4(1.0, 0.80, 0.42, 1.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.0;

uniform vec3 bounds_min = vec3(0.0);
uniform vec3 bounds_size = vec3(1.0);

// Все размеры в локальных единицах меша (на сцене он масштабирован на 0.6).
uniform float inset = 0.12;
uniform float line_width = 0.03;
uniform float arm_length = 0.55;
uniform float diamond_size = 0.07;
uniform float glow_width = 0.45;
// Значения > 1.0 дают свечение через Environment glow.
uniform float line_energy = 3.0;
uniform float glow_energy = 0.30;
uniform float breathe_amount = 0.12;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float t = smoothstep(0.0, 1.0, intensity);

	// Координаты на створке (плоскость XY), в локальных единицах.
	vec2 p = local_pos.xy - bounds_min.xy;
	vec2 dist_edge = min(p, bounds_size.xy - p);
	vec2 q = dist_edge - vec2(inset);
	float aa = max(length(fwidth(p)), 0.0001);

	float arm = arm_length * t;

	// Вертикальные и горизонтальные плечи скобок у каждого угла.
	float vx = 1.0 - smoothstep(line_width - aa, line_width + aa, abs(q.x));
	float vy = 1.0 - smoothstep(line_width - aa, line_width + aa, abs(q.y));
	float cap_x = smoothstep(-aa, aa, q.x) * (1.0 - smoothstep(arm - aa, arm + aa, q.x));
	float cap_y = smoothstep(-aa, aa, q.y) * (1.0 - smoothstep(arm - aa, arm + aa, q.y));
	float bracket = max(vx * cap_y, vy * cap_x);

	// Ромбик в вершине угла, как в HUD.
	float dia = 1.0 - smoothstep(diamond_size - aa, diamond_size + aa, abs(q.x) + abs(q.y));

	// Очень мягкое свечение у краёв створки.
	float edge = min(dist_edge.x, dist_edge.y);
	float glow = exp(-edge / glow_width);

	float breathe = 1.0 + sin(TIME * 2.0) * breathe_amount;

	vec3 col = line_color.rgb * ((bracket + dia) * line_energy + glow * glow_energy);
	ALBEDO = col * breathe * t;
}
