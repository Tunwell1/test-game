// Cartoon wooden plank lining - flat colours, ZERO textures, ZERO painted detail.
//
// The mesh (Tools/generate_wall_lining.py v3) packs FOUR different board
// layouts into ONE GLB, stacked along Y in 7 m steps. Each layout is real
// low-poly geometry: straight edges and flush board faces. GAP=0 and CH=0,
// so neighbouring boards share an edge; there are no visible grooves or gaps.
// The backing flag is kept only as a hidden safety net behind the faces.
//   COLOR.r = board tone tier (0..1, six tiers)
//   COLOR.g = 0 face / 0.5 chamfer / 0.6 backing
//   COLOR.b = packed layout index (0..1)
//
// The vertex shader picks ONE layout per placed module from its WORLD position
// and collapses the stacked layouts back into y = 0..6. Adjacent walls get
// different picks, so identical GLBs no longer look copied. No second asset.
shader_type spatial;
render_mode cull_disabled;

uniform float groove_shade : hint_range(0.0, 1.0, 0.05) = 0.62;
uniform float tone_contrast : hint_range(0.0, 0.4, 0.05) = 0.18;

const vec3 OAK    = vec3(0.1954, 0.0865, 0.0296);
const vec3 GROOVE = vec3(0.0420, 0.0200, 0.0080);
const float LAYOUT_STEP = 7.0;

varying float v_variant;
varying float v_pick;
varying float v_slot;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	v_variant = hash13(origin);
	// Neighbouring modules of the closed ring get 0,1,2,3,0,1,2,3,...
	v_pick = floor(mod(floor(origin.x * 0.1 + 0.5)
	                 + floor(origin.z * 0.2 + 0.5) + 3.0, 4.0));
	v_slot = floor(VERTEX.y / LAYOUT_STEP);
	// Remove the other layouts in the VERTEX stage: collapsing them to one
	// point off-screen means they never rasterise at all. A fragment discard
	// alone still lets all four packed meshes write overlapping depth.
	if (abs(v_slot - v_pick) > 0.5) {
		VERTEX = vec3(0.0, -1000.0, 0.0);
	} else {
		VERTEX.y -= v_slot * LAYOUT_STEP;
	}
}

void fragment() {
	// Safety net only; normally the unwanted layouts never reach this stage.
	if (abs(v_slot - v_pick) > 0.5) {
		discard;
	}

	const float TIERS = 6.0;
	float tier = clamp(floor(COLOR.r * TIERS + 0.5), 0.0, TIERS - 1.0);
	float shifted = mod(tier + floor(v_variant * TIERS), TIERS);
	vec3 col = OAK * mix(1.0 - tone_contrast, 1.0 + tone_contrast,
	                     shifted / (TIERS - 1.0));
	col *= mix(vec3(1.02, 1.0, 0.98), vec3(0.98, 1.0, 1.02), v_variant);

	float groove = clamp((COLOR.g - 0.10) * 2.5, 0.0, 1.0);
	col = mix(col, GROOVE, groove * groove_shade);
	if (COLOR.g > 0.55) {
		col = mix(col, GROOVE, 0.72);
	}

	ALBEDO = col;
	ROUGHNESS = mix(0.86, 0.92, v_variant);
}
