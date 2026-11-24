shader_type sky;

uniform sampler2D panorama : filter_linear_mipmap, repeat_enable;
uniform float energy = 1.0;
uniform float contrast = 1.0;
uniform float pivot = 0.1;
uniform float saturation = 1.0;
uniform float ceiling = 1000.0;
uniform float light_energy = 0.0;
uniform vec4 ground : source_color = vec4(0.0);
uniform float blur = 0.0;

const vec3 LUM = vec3(0.2126, 0.7152, 0.0722);

vec3 grade(vec3 c) {
	c = pivot * pow(max(c, vec3(0.0)) / pivot, vec3(contrast));
	c /= 1.0 + dot(c, LUM) / ceiling;
	return max(mix(vec3(dot(c, LUM)), c, saturation), vec3(0.0)) * energy;
}

void sky() {
	vec3 c = textureLod(panorama, SKY_COORDS, blur).rgb;
	if (AT_CUBEMAP_PASS && light_energy > 0.0) {
		COLOR = c * light_energy;
	} else {
		COLOR = grade(c);
		if (ground.a > 0.0 && EYEDIR.y < 0.0) {
			vec3 h = grade(textureLod(panorama, vec2(SKY_COORDS.x, 0.499), blur).rgb) * ground.rgb;
			COLOR = mix(COLOR, h, ground.a * smoothstep(0.0, -0.04, EYEDIR.y));
		}
	}
}
