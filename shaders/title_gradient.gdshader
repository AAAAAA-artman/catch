shader_type canvas_item;

// 主界面标题「接住」的渐变：上实下虚，模仿背景上半部的明暗过渡
uniform vec3 top_color : source_color = vec3(0.97, 0.95, 0.90);
uniform vec3 bottom_color : source_color = vec3(0.62, 0.70, 0.60);
uniform float alpha_top : hint_range(0.0, 1.0) = 1.0;
uniform float alpha_bottom : hint_range(0.0, 1.0) = 0.18;
// 渐变所在的屏幕纵向区间（0 顶部 ~ 1 底部），由脚本按标题位置设置
uniform float band_top = 0.06;
uniform float band_bottom = 0.34;

void fragment() {
	float t = clamp((SCREEN_UV.y - band_top) / max(band_bottom - band_top, 0.001), 0.0, 1.0);
	// 稍微加一点缓动，让过渡更柔和
	t = t * t * (3.0 - 2.0 * t);
	vec4 tex = texture(TEXTURE, UV);
	vec3 col = mix(top_color, bottom_color, t);
	float a = mix(alpha_top, alpha_bottom, t);
	COLOR = vec4(col, a) * tex.a * COLOR;
}
