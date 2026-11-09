shader_type canvas_item;

uniform vec2 near_points[256];
uniform vec2 far_points[256];
uniform int near_count = 0;
uniform int far_count = 0;
uniform vec4 fog_color : source_color = vec4(0.0, 0.015, 0.03, 1.0);

bool inside_near(vec2 p) {
	bool inside = false;
	int previous = near_count - 1;
	for (int i = 0; i < 256; i++) {
		if (i >= near_count) { break; }
		vec2 a = near_points[i];
		vec2 b = near_points[previous];
		if ((a.y > p.y) != (b.y > p.y) && p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x) { inside = !inside; }
		previous = i;
	}
	return inside;
}
bool inside_far(vec2 p) {
	bool inside = false;
	int previous = far_count - 1;
	for (int i = 0; i < 256; i++) {
		if (i >= far_count) { break; }
		vec2 a = far_points[i];
		vec2 b = far_points[previous];
		if ((a.y > p.y) != (b.y > p.y) && p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x) { inside = !inside; }
		previous = i;
	}
	return inside;
}
void fragment() {
	COLOR = inside_near(FRAGCOORD.xy) || inside_far(FRAGCOORD.xy) ? vec4(0.0) : fog_color;
}
