shader_type canvas_item;
uniform vec2 near_points[256];
uniform vec2 far_points[256];
uniform int near_count = 0;
uniform int far_count = 0;
bool in_near(vec2 p) {
	bool hit = false; int j = near_count - 1;
	for (int i = 0; i < 256; i++) {
		if (i >= near_count) break;
		vec2 a = near_points[i]; vec2 b = near_points[j];
		if ((a.y > p.y) != (b.y > p.y) && p.x < (b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x) hit = !hit;
		j = i;
	}
	return hit;
}
bool in_far(vec2 p) {
	bool hit = false; int j = far_count - 1;
	for (int i = 0; i < 256; i++) {
		if (i >= far_count) break;
		vec2 a = far_points[i]; vec2 b = far_points[j];
		if ((a.y > p.y) != (b.y > p.y) && p.x < (b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x) hit = !hit;
		j = i;
	}
	return hit;
}
void fragment() {
	if (!in_near(FRAGCOORD.xy) && !in_far(FRAGCOORD.xy)) discard;
}
