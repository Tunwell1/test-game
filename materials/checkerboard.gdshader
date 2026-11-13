shader_type spatial;

uniform vec4 color_light : source_color = vec4(0.85, 0.87, 0.9, 1.0);
uniform vec4 color_dark : source_color = vec4(0.25, 0.27, 0.3, 1.0);
uniform float grid_scale : hint_range(0.1, 10.0, 0.1) = 1.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.7;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 abs_norm = abs(world_normal);
	vec2 uv_coords;

	if (abs_norm.y >= abs_norm.x && abs_norm.y >= abs_norm.z) {
		uv_coords = world_pos.xz;
	} else if (abs_norm.x >= abs_norm.z) {
		uv_coords = world_pos.yz;
	} else {
		uv_coords = world_pos.xy;
	}

	vec2 check_grid = floor(uv_coords * grid_scale);
	float checker = mod(check_grid.x + check_grid.y, 2.0);

	ALBEDO = mix(color_light.rgb, color_dark.rgb, checker);
	ROUGHNESS = roughness;
}
