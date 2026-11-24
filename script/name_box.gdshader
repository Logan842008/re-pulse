shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;

uniform vec4 color : source_color = vec4(1.0);
uniform float fill = 1.0;
uniform vec2 size = vec2(1.0, 0.3);
uniform float thick = 0.03;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 p = UV * size;
	vec2 q = size - p;
	float d = min(min(p.x, q.x), min(p.y, q.y));
	if (d > thick) {
		discard;
	}
	float per = 2.0 * (size.x + size.y);
	float hx = size.x * 0.5;
	float t;
	if (d == p.y) {
		t = p.x >= hx ? p.x - hx : per - (hx - p.x);
	} else if (d == q.x) {
		t = hx + p.y;
	} else if (d == q.y) {
		t = hx + size.y + q.x;
	} else {
		t = hx + size.y + size.x + q.y;
	}
	bool on = t <= fill * per;
	ALBEDO = on ? color.rgb : vec3(0.08);
	ALPHA = on ? 1.0 : 0.4;
}
