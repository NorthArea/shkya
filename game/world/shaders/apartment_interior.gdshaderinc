// APARTMENT-01. Metres behind the pane: x across room, y up, z inward.
// Analytic box intersections preserve furniture occlusion and view-dependent parallax;
// no ray marching, scene nodes, textures or additional lights.
float apartment_hash(vec2 cell, float room_seed) {
	vec3 p = fract(vec3(cell.x, cell.y, room_seed) * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

void apartment_box(vec3 eye, vec3 ray, vec3 center, vec3 half_size, vec3 color, inout vec4 hit) {
	// The forward component is 1; clamping only avoids division by zero for axial views.
	vec3 safe_ray = vec3(
		ray.x < 0.0 ? -max(abs(ray.x), 0.00001) : max(abs(ray.x), 0.00001),
		ray.y < 0.0 ? -max(abs(ray.y), 0.00001) : max(abs(ray.y), 0.00001), 1.0);
	vec3 a = (center - half_size - eye) / safe_ray;
	vec3 b = (center + half_size - eye) / safe_ray;
	vec3 near_face = min(a, b);
	vec3 far_face = max(a, b);
	float enter = max(max(near_face.x, near_face.y), near_face.z);
	float leave = min(min(far_face.x, far_face.y), far_face.z);
	if (enter > 0.0 && enter < leave && enter < hit.a) {
		float shade = near_face.y >= max(near_face.x, near_face.z) ? 1.0 : (near_face.x > near_face.z ? 0.68 : 0.86);
		hit = vec4(color * shade * mix(1.05, 0.78, enter / 4.5), enter);
	}
}

vec3 apartment_room(vec2 glass_point, vec2 direction, vec2 cell, float room_seed, vec3 size, vec4 opening, float detail) {
	vec3 eye = vec3(glass_point, 0.0);
	vec3 ray = vec3(-direction, 1.0);
	float tx = direction.x > 0.001 ? glass_point.x / direction.x : (direction.x < -0.001 ? (glass_point.x - size.x) / direction.x : 1e6);
	float ty = direction.y > 0.001 ? glass_point.y / direction.y : (direction.y < -0.001 ? (glass_point.y - size.y) / direction.y : 1e6);
	float room_distance = min(min(tx, ty), size.z);
	vec3 p = eye + ray * room_distance;
	float choice = apartment_hash(cell + 2.2, room_seed);
	float kind = floor(apartment_hash(cell + 13.1, room_seed) * 3.0);
	vec3 paper = mix(vec3(0.82, 0.76, 0.62), vec3(0.66, 0.75, 0.66), step(0.55, choice));
	vec3 wood = mix(vec3(0.31, 0.17, 0.09), vec3(0.52, 0.34, 0.18), choice);
	vec3 fabric = mix(vec3(0.27, 0.38, 0.32), vec3(0.50, 0.24, 0.15), step(0.5, choice));
	vec3 color = paper;
	if (room_distance == ty) {
		if (direction.y > 0.0) {
			color = wood * 0.75;
			// A rug belongs on the floor and foreshortens with it.
			if (kind > 0.5 && abs(p.x - size.x * 0.53) < size.x * 0.32 && p.z > 0.6 && p.z < size.z - 0.5) {
				color = fabric * (0.78 + 0.12 * cos(p.x * 22.0) * cos(p.z * 20.0));
			}
		} else {
			color = vec3(0.91, 0.87, 0.78);
		}
	} else if (room_distance == tx) {
		color *= 0.74;
	} else {
		// Skirting, a framed print and subtle wallpaper remain attached to the wall.
		color *= 0.96 + 0.04 * cos(p.x * 28.0);
		if (p.y < 0.12) color = wood;
		if (kind > 0.5 && abs(p.x - size.x * 0.52) < 0.38 && abs(p.y - 1.85) < 0.29) {
			color = abs(p.x - size.x * 0.52) > 0.33 || abs(p.y - 1.85) > 0.24 ? wood : vec3(0.38, 0.47, 0.41);
		}
	}
	vec4 hit = vec4(color * mix(0.97, 0.76, room_distance / size.z), room_distance);
	// Furniture disappears before it is subpixel; curtains and the room shell remain.
	if (detail > 0.5) {
		float middle = size.x * 0.5;
		float back = size.z - 0.35;
		if (kind < 0.5) {
			// Kitchen: separate worktop, lower/upper cupboards, cooker and refrigerator.
			apartment_box(eye, ray, vec3(middle, 0.43, back), vec3(size.x * 0.32, 0.43, 0.31), vec3(0.55, 0.58, 0.42), hit);
			apartment_box(eye, ray, vec3(middle, 0.89, back - 0.02), vec3(size.x * 0.33, 0.035, 0.34), vec3(0.72, 0.67, 0.53), hit);
			apartment_box(eye, ray, vec3(middle, 1.92, back + 0.04), vec3(size.x * 0.29, 0.35, 0.27), vec3(0.68, 0.67, 0.53), hit);
			// Door divisions are shallow real slabs, rather than a single brown rectangle.
			for (int door = 0; door < 3; door++) {
				float dx = middle + (float(door) - 1.0) * size.x * 0.21;
				apartment_box(eye, ray, vec3(dx, 0.43, back - 0.32), vec3(size.x * 0.1, 0.37, 0.018), vec3(0.62, 0.62, 0.46), hit);
				apartment_box(eye, ray, vec3(dx + 0.1, 0.67, back - 0.345), vec3(0.055, 0.013, 0.014), wood, hit);
			}
			apartment_box(eye, ray, vec3(0.38, 0.99, back - 0.05), vec3(0.29, 0.97, 0.34), vec3(0.78, 0.79, 0.70), hit);
			apartment_box(eye, ray, vec3(0.38, 1.43, back - 0.40), vec3(0.27, 0.014, 0.01), vec3(0.32), hit);
			apartment_box(eye, ray, vec3(size.x * 0.74, 0.89, back - 0.04), vec3(0.26, 0.04, 0.26), vec3(0.18, 0.19, 0.17), hit);
			apartment_box(eye, ray, vec3(size.x * 0.74, 1.02, back - 0.04), vec3(0.10, 0.09, 0.10), vec3(0.52, 0.55, 0.53), hit);
			apartment_box(eye, ray, vec3(middle, 0.77, 1.35), vec3(0.55, 0.045, 0.38), wood * 1.3, hit);
			for (int leg = 0; leg < 4; leg++) {
				vec2 offset = vec2(mod(float(leg), 2.0) * 2.0 - 1.0, floor(float(leg) * 0.5) * 2.0 - 1.0);
				apartment_box(eye, ray, vec3(middle + offset.x * 0.46, 0.36, 1.35 + offset.y * 0.29), vec3(0.035, 0.36, 0.035), wood, hit);
			}
			for (int chair = 0; chair < 2; chair++) {
				float cx = middle + (float(chair) * 2.0 - 1.0) * 0.75;
				apartment_box(eye, ray, vec3(cx, 0.45, 1.45), vec3(0.22, 0.045, 0.23), fabric, hit);
				apartment_box(eye, ray, vec3(cx, 0.73, 1.66), vec3(0.22, 0.28, 0.045), wood, hit);
				apartment_box(eye, ray, vec3(cx, 0.22, 1.6), vec3(0.035, 0.22, 0.035), wood, hit);
			}
			apartment_box(eye, ray, vec3(middle + 0.15, 0.88, 1.3), vec3(0.055, 0.065, 0.055), vec3(0.80, 0.73, 0.55), hit);
		} else if (kind < 1.5) {
			// Living room: sofa, cushions, coffee table, a bookcase and television.
			apartment_box(eye, ray, vec3(middle, 0.42, back - 0.4), vec3(size.x * 0.31, 0.23, 0.40), fabric, hit);
			apartment_box(eye, ray, vec3(middle, 0.81, back - 0.08), vec3(size.x * 0.31, 0.40, 0.12), fabric * 0.84, hit);
			for (int arm = 0; arm < 2; arm++) {
				float side = float(arm) * 2.0 - 1.0;
				apartment_box(eye, ray, vec3(middle + side * size.x * 0.31, 0.63, back - 0.4), vec3(0.12, 0.28, 0.43), fabric * 0.9, hit);
				apartment_box(eye, ray, vec3(middle + side * 0.49, 0.79, back - 0.36), vec3(0.22, 0.18, 0.11), mix(fabric, vec3(0.84, 0.69, 0.41), 0.6), hit);
			}
			apartment_box(eye, ray, vec3(middle, 0.48, 1.55), vec3(0.61, 0.035, 0.34), wood * 1.2, hit);
			apartment_box(eye, ray, vec3(middle - 0.45, 0.23, 1.55), vec3(0.035, 0.23, 0.26), wood, hit);
			apartment_box(eye, ray, vec3(middle + 0.45, 0.23, 1.55), vec3(0.035, 0.23, 0.26), wood, hit);
			apartment_box(eye, ray, vec3(middle - 0.12, 0.54, 1.55), vec3(0.18, 0.025, 0.13), vec3(0.69, 0.65, 0.50), hit);
			apartment_box(eye, ray, vec3(0.29, 1.12, back - 0.1), vec3(0.23, 1.10, 0.27), wood, hit);
			for (int shelf = 0; shelf < 3; shelf++) {
				float sy = 0.65 + float(shelf) * 0.49;
				apartment_box(eye, ray, vec3(0.29, sy, back - 0.39), vec3(0.19, 0.17, 0.02), vec3(0.49, 0.43, 0.32), hit);
				apartment_box(eye, ray, vec3(0.21, sy, back - 0.42), vec3(0.018, 0.17, 0.012), vec3(0.25, 0.30, 0.25), hit);
			}
			apartment_box(eye, ray, vec3(size.x - 0.36, 0.92, 2.14), vec3(0.30, 0.20, 0.19), vec3(0.08, 0.09, 0.08), hit);
			apartment_box(eye, ray, vec3(size.x - 0.36, 0.92, 1.94), vec3(0.25, 0.15, 0.012), vec3(0.20, 0.30, 0.34), hit);
		} else {
			// Bedroom: mattress above its frame, folded cover, two pillows and wardrobe.
			apartment_box(eye, ray, vec3(middle + 0.1, 0.25, back - 0.85), vec3(0.68, 0.20, 1.0), wood, hit);
			apartment_box(eye, ray, vec3(middle + 0.1, 0.53, back - 0.85), vec3(0.68, 0.12, 1.0), vec3(0.80, 0.76, 0.64), hit);
			apartment_box(eye, ray, vec3(middle + 0.1, 0.67, back - 1.12), vec3(0.69, 0.04, 0.72), fabric * 1.35, hit);
			apartment_box(eye, ray, vec3(middle + 0.1, 0.68, back + 0.11), vec3(0.73, 0.49, 0.07), wood, hit);
			for (int pillow = 0; pillow < 2; pillow++) {
				apartment_box(eye, ray, vec3(middle - 0.23 + float(pillow) * 0.64, 0.71, back - 0.15), vec3(0.27, 0.09, 0.22), vec3(0.90, 0.85, 0.70), hit);
			}
			apartment_box(eye, ray, vec3(0.40, 1.10, back - 0.1), vec3(0.31, 1.08, 0.34), wood, hit);
			apartment_box(eye, ray, vec3(0.40, 1.1, back - 0.45), vec3(0.012, 1.04, 0.015), wood * 0.58, hit);
			apartment_box(eye, ray, vec3(size.x - 0.35, 0.30, back - 0.28), vec3(0.28, 0.30, 0.30), wood * 1.25, hit);
			apartment_box(eye, ray, vec3(size.x - 0.35, 0.85, back - 0.28), vec3(0.025, 0.25, 0.025), wood, hit);
			apartment_box(eye, ray, vec3(size.x - 0.35, 1.08, back - 0.28), vec3(0.16, 0.14, 0.16), vec3(0.96, 0.78, 0.50), hit);
		}
		// A hanging shade and its cord are visible when looking up from the street.
		apartment_box(eye, ray, vec3(middle, size.y - 0.21, 1.9), vec3(0.012, 0.21, 0.012), wood, hit);
		apartment_box(eye, ray, vec3(middle, size.y - 0.48, 1.9), vec3(0.23, 0.13, 0.23), vec3(1.0, 0.85, 0.58), hit);
	}
	// Both fabric layers are behind the glass, at different depths from the furniture.
	vec2 sheer_point = glass_point - direction * 0.24;
	float opening_center = opening.x + opening.z * (0.40 + choice * 0.18);
	float sheer_gap = opening.z * (0.035 + 0.12 * apartment_hash(cell + 7.3, room_seed));
	if (abs(sheer_point.x - opening_center) > sheer_gap && sheer_point.y > opening.y - 0.12 && sheer_point.y < opening.y + opening.w + 0.12 && hit.a > 0.24) {
		float fold = 0.5 + 0.5 * cos(sheer_point.x * 39.0);
		hit.rgb = mix(hit.rgb, vec3(0.81, 0.79, 0.68) * (0.84 + 0.16 * fold), 0.16 + 0.13 * fold);
	}
	vec2 curtain_point = glass_point - direction * 0.12;
	float left_width = opening.z * (0.13 + 0.19 * apartment_hash(cell + 6.9, room_seed));
	float right_width = opening.z * (0.13 + 0.19 * apartment_hash(cell + 8.7, room_seed));
	// A few households have nearly closed curtains; most keep an asymmetric opening.
	if (apartment_hash(cell + 3.8, room_seed) < 0.15) {
		left_width = opening.z * 0.46;
		right_width = opening.z * 0.42;
	}
	float wave = cos(curtain_point.x * 34.0 + choice * 5.0);
	bool drape = curtain_point.x < opening.x + left_width + 0.016 * wave || curtain_point.x > opening.x + opening.z - right_width + 0.016 * wave;
	bool valance = curtain_point.y > opening.y + opening.w - 0.10;
	if ((drape || valance) && curtain_point.y > opening.y - 0.15 && hit.a > 0.12) {
		vec3 cloth = mix(vec3(0.43, 0.25, 0.14), vec3(0.25, 0.38, 0.31), step(0.52, choice));
		cloth = mix(cloth, vec3(0.58, 0.44, 0.29), step(0.83, choice));
		hit.rgb = cloth * (0.77 + 0.23 * wave);
	}
	return hit.rgb;
}
