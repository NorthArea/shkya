shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform bool frozen = false;
varying vec3 world_position;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1)), f.x), f.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (!frozen) {
		VERTEX.y += noise(world_position.xz * 14.0) * 0.018;
	}
}

void fragment() {
	vec2 p = world_position.xz;
	float coarse = noise(p * 3.5);
	vec2 edge = abs(UV - vec2(0.5)) * 2.0;
	float rim = length(edge * vec2(0.92, 1.0)) + (coarse - 0.5) * 0.32;
	if (rim > 0.93 || noise(p * 13.0) < smoothstep(0.65, 0.96, rim) * 0.3) {
		discard;
	}
	float grain = noise(p * 40.0);
	if (frozen) {
		float frost = smoothstep(0.58, 0.95, rim) * 0.65 + smoothstep(0.68, 0.9, coarse) * 0.4;
		float fracture = pow(1.0 - abs(sin(p.x * 8.0 + noise(p * 0.8) * 6.0)), 35.0);
		ALBEDO = mix(vec3(0.13, 0.15, 0.16), vec3(0.39, 0.41, 0.40), frost + fracture * 0.15);
		ROUGHNESS = mix(0.24, 0.74, frost);
		SPECULAR = 0.5;
	} else {
		float salt = smoothstep(0.67, 0.83, grain) * (0.5 + 0.5 * coarse);
		ALBEDO = mix(vec3(0.25, 0.24, 0.21), vec3(0.47, 0.45, 0.40), coarse);
		ALBEDO = mix(ALBEDO, vec3(0.65, 0.64, 0.59), salt * 0.6);
		ROUGHNESS = 0.88;
		SPECULAR = 0.2;
	}
	NORMAL = normalize(NORMAL + vec3((grain - 0.5) * 0.22, 0.0, (coarse - 0.5) * 0.12));
}
