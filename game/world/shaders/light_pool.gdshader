shader_type spatial;
// CITY-02 F: пятно натриевого света на дороге за краем карты — без источника света (дёшево): плоский квад, мягкий
// круг, сложение с фоном. Туман сцены действует — дальние пятна тают в дымке, как фонари арены.
// COLOR экземпляра: rgb — цвет, a — яркость.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float k = 1.0 - smoothstep(0.0, 1.0, d);
	ALBEDO = COLOR.rgb * COLOR.a * k * k;
}
