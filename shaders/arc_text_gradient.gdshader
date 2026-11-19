shader_type canvas_item;

// 弧线文字的渐变色（呼应主界面「接住」封面的上实下虚）
// 用 SCREEN_UV 做屏幕空间渐变，band 由脚本按文字所在高度设置
uniform vec3 top_color : source_color = vec3(0.97, 0.95, 0.90);
uniform vec3 bottom_color : source_color = vec3(0.80, 0.86, 0.76);
uniform float alpha_top : hint_range(0.0, 1.0) = 1.0;
uniform float alpha_bottom : hint_range(0.0, 1.0) = 0.52;
uniform float band_top = 0.10;
uniform float band_bottom = 0.34;

void fragment() {
	float t = clamp((SCREEN_UV.y - band_top) / max(band_bottom - band_top, 0.001), 0.0, 1.0);
	t = t * t * (3.0 - 2.0 * t);
	vec4 tex = texture(TEXTURE, UV);
	vec3 col = mix(top_color, bottom_color, t);
	float a = mix(alpha_top, alpha_bottom, t);
	COLOR = vec4(col, a) * tex.a * COLOR;
}
