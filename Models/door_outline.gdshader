shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;

uniform vec4 outline_color : source_color = vec4(1.0, 0.78, 0.28, 1.0);
// Screen-space width keeps the border even and avoids spikes from hard mesh normals.
uniform float outline_pixels = 1.5;

void vertex() {
	vec4 view_vertex = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 view_normal = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec4 clip_vertex = PROJECTION_MATRIX * view_vertex;
	vec4 clip_normal = PROJECTION_MATRIX * vec4(view_normal, 0.0);
	vec2 screen_normal = clip_normal.xy / max(length(clip_normal.xy), 0.0001);
	clip_vertex.xy += screen_normal * (outline_pixels * 2.0 / VIEWPORT_SIZE) * clip_vertex.w;
	POSITION = clip_vertex;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	EMISSION = outline_color.rgb * 0.8;
}
