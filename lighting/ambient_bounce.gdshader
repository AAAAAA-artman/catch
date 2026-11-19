shader_type canvas_item;
// ============================================================================
// ambient_bounce.gdshader —— 烛光在墙面/地板上的漫反射
//
// 【它解决什么】
//   纯黑背景让画面很"平"：人物被烛光照亮，但周围什么都没有，
//   看不出"这个房间被这支蜡烛照着"。
//   这个 shader 模拟「烛光打到墙/地板后反射回来的柔光」——
//   不需要任何背景贴图，纯解析计算。
//
// 【为什么不是简单的径向渐变】
//   真实的墙面漫反射有三个特征：
//     1. 以烛火为中心向外衰减（但比直射光平缓得多）
//     2. 向上的墙比向下的地板亮（光会打到天花板再反射）
//     3. 中心有轻微的"核心亮斑"（烛火附近最近的墙最亮）
//   这里三者都做了。
// ============================================================================

// 烛火位置（屏幕归一化 UV），由 driver 每帧更新
uniform vec2  light_uv = vec2(0.89, 0.42);
// 漫反射的颜色：暖黄，比直射光淡
uniform vec3  bounce_color : source_color = vec3(1.0, 0.72, 0.42);
// 整体强度
uniform float bounce_strength : hint_range(0.0, 2.0) = 0.16;
// 衰减半径（越大，光扩散越远）
uniform float bounce_radius : hint_range(0.1, 2.0) = 0.85;
// 衰减指数：越小越"平缓"，越接近漫反射
uniform float bounce_falloff : hint_range(0.5, 4.0) = 1.45;
// 核心亮斑强度与半径
uniform float core_strength : hint_range(0.0, 1.0) = 0.22;
uniform float core_radius : hint_range(0.02, 0.6) = 0.13;
// 垂直方向权重：1 = 上方墙更亮，-1 = 下方地板更亮
uniform float vertical_bias : hint_range(-1.0, 1.0) = 0.45;

void fragment() {
	vec2 uv = SCREEN_UV;

	// ---- 1. 径向衰减（漫反射比直射光平缓得多）----
	float d = distance(uv, light_uv);
	float radial = 1.0 / (1.0 + pow(d / bounce_radius, bounce_falloff));

	// ---- 2. 核心亮斑：烛火附近最近的墙最亮 ----
	float core = exp(-d / core_radius) * core_strength;

	// ---- 3. 垂直偏置：光打到墙面的分布不是圆形 ----
	// 烛火在画面中部，上方是墙、下方是地，两者反射率不同
	float v = clamp((light_uv.y - uv.y) * 2.0 + 0.5, 0.0, 1.5);
	float vert = mix(1.0 - vertical_bias, 1.0 + vertical_bias, v);

	// ---- 4. 合成 ----
	float amount = (radial + core) * vert * bounce_strength;

	// 但墙面上还应该有轻微的大尺度明暗变化（不是均匀的雾）
	// 用一个便宜的低频噪声给一点颗粒结构
	float n = sin(uv.x * 9.7) * sin(uv.y * 7.3) * 0.5 + 0.5;
	amount *= (0.88 + n * 0.24);

	// 输出：暖色，alpha 由强度决定（叠加在黑色底上）
	COLOR = vec4(bounce_color * amount, 1.0);
}
