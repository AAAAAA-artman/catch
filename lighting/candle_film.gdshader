shader_type canvas_item;
render_mode blend_mix;
// ============================================================================
// candle_film.gdshader —— 烛光电影感全屏滤镜
//
// 目标：把「贴图感」的 2D 立绘压进「昏暗房间 + 单只蜡烛」的实拍感里。
// 参考图的客观特征（用脚本量化过，见 analysis/hue_compare.py）：
//   · 整体极暗：lum 中位数 0.130，p95 仅 0.298（没有大片死白）
//   · 对比被压缩：p5=0.035 / p95=0.298，暗部不死、亮部不过曝
//   · 亮部偏暖 R-B=+0.044，暗部偏冷 R-B=-0.010（经典 warm-highlight / cool-shadow）
//   · 饱和度中等 0.143，且暗部近灰（床单区域 sat=0.009）
//
// 处理链（顺序很重要，和真实摄影机一致）：
//   1. 曝光 → 2. 高光 bloom（烛火溢出）→ 3. 色温分离（亮暖暗冷）
//      4. 哈希雾（体积感/廉价空气散射）→ 5. 暗角 → 6. 颗粒 → 7. 发光抖动
// ============================================================================

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

// ---------------- 画面基准 ----------------
// 【注意】这里的默认值刻意与 candle_film.gd 的 base_* 保持一致。
//   脚本每帧都会用 base_* 覆盖这些 uniform，但如果有人只拷走这个 shader
//   单独使用（不挂 candle_film.gd），默认值就是它最终的样子。
//   两边不一致会导致"单独用 shader 时画面发白"这种难查的问题。
uniform float exposure : hint_range(0.2, 2.0) = 0.95;
uniform float contrast : hint_range(0.5, 2.0) = 0.98;
uniform float black_point : hint_range(0.0, 0.2) = 0.010;
uniform float saturation : hint_range(0.0, 2.0) = 0.74;
// 中间调抬升（gamma）：<1 提亮暗部、>1 压暗中间调。
// 用来避免一味压曝光导致死黑（参考图 p25 是 0.075，不是 0）。
uniform float midtone_lift : hint_range(0.3, 1.8) = 0.95;

// ---------------- 色温分离 ----------------
uniform vec3  highlight_tint : source_color = vec3(1.00, 0.91, 0.80);
uniform vec3  shadow_tint    : source_color = vec3(0.82, 0.87, 0.97);
uniform float split_amount  : hint_range(0.0, 1.0) = 0.38;

// ---------------- 烛光 bloom ----------------
uniform vec2  light_uv = vec2(0.744, 0.397);
uniform vec3  light_color : source_color = vec3(1.00, 0.58, 0.26);
uniform float bloom_threshold : hint_range(0.0, 1.0) = 0.56;
uniform float bloom_strength : hint_range(0.0, 3.0) = 0.30;
uniform float bloom_radius : hint_range(0.0, 0.25) = 0.040;
uniform float glow_strength : hint_range(0.0, 2.0) = 0.13;
uniform float glow_radius : hint_range(0.02, 0.9) = 0.20;
// 光晕只作用于亮点周围，不整屏铺开（否则门洞会被照白，失去深度）
uniform float glow_falloff : hint_range(1.0, 8.0) = 3.4;

// ---------------- 雾 / 空气感 ----------------
uniform float haze_amount : hint_range(0.0, 0.5) = 0.030;
uniform vec3  haze_color : source_color = vec3(0.20, 0.19, 0.20);
uniform float haze_vertical : hint_range(-1.0, 1.0) = 0.35;

// ---------------- 暗角 ----------------
uniform float vignette_strength : hint_range(0.0, 1.5) = 0.42;
uniform float vignette_inner : hint_range(0.0, 1.5) = 0.58;

// ---------------- 颗粒 / 扫描 ----------------
uniform float grain_amount : hint_range(0.0, 0.2) = 0.024;
uniform float grain_speed = 1.0;

// ---------------- 整体淡入（呼吸/受击用）----------------
uniform float tint_mix : hint_range(0.0, 1.0) = 1.0;

const vec2 VIGNETTE_CENTER = vec2(0.5, 0.46);

// 便宜的哈希噪声：不需要贴图
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// 9 抽头圆形模糊（bloom 用；GL Compatibility 下 screen texture 无 mipmap 也能用）
vec3 tap_blur(vec2 uv, float radius) {
	vec3 acc = vec3(0.0);
	float wsum = 0.0;
	for (int i = 0; i < 9; i++) {
		float a = float(i) * 0.6981317;   // 2π/9
		float r = (i == 0) ? 0.0 : radius;
		vec2 o = vec2(cos(a), sin(a)) * r;
		float w = (i == 0) ? 1.6 : 1.0;
		acc += texture(screen_tex, uv + o).rgb * w;
		wsum += w;
	}
	return acc / wsum;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 col = texture(screen_tex, uv).rgb;

	// ============ 1. 曝光 ============
	col *= exposure;

	// ============ 2. 烛光 bloom ============
	// 亮部提取后做宽模糊再叠回来；只有蜡烛和它照亮的墙面会亮到阈值以上
	if (bloom_strength > 0.001) {
		vec3 blurred = tap_blur(uv, bloom_radius);
		vec3 bright = max(blurred - vec3(bloom_threshold), vec3(0.0));
		bright /= max(1.0 - bloom_threshold, 0.001);
		col += bright * light_color * bloom_strength;
	}
	// 烛火的近距离圆形光溢出：不依赖画面内容，保证"光源本身在发光"
	// 用高次幂让光只贴在烛火附近，不会把整个门洞/墙面照白
	if (glow_strength > 0.001) {
		float d = distance(uv, light_uv);
		float g = exp(-pow(d / glow_radius, glow_falloff));
		col += light_color * g * glow_strength;
	}

	// ============ 3. 哈希雾（空气散射）============
	// 越靠下越厚，模拟地面附近的浮尘。
	// 【为什么雾要随亮度减弱】无差别加雾会把角色（尤其靠下的身体）
	// 一起糊掉，导致看不见 Boss。真实空气散射对亮物的影响小得多，
	// 所以这里用亮度做衰减，主要糊暗部 —— 既保留空间感，又保住角色轮廓。
	if (haze_amount > 0.001) {
		float band = mix(1.0 - haze_vertical, 1.0 + haze_vertical, uv.y);
		float lh = dot(col, vec3(0.2126, 0.7152, 0.0722));
		float keep = smoothstep(0.02, 0.22, lh);
		col = mix(col, haze_color, haze_amount * clamp(band, 0.0, 1.5) * (1.0 - keep * 0.9));
	}

	// ============ 4. 对比 / 黑场 ============
	col = max(col - vec3(black_point), vec3(0.0)) / max(1.0 - black_point, 0.001);
	// 中间调抬升：gamma < 1 会提亮暗部。用 1/midtone_lift 作指数。
	col = pow(max(col, vec3(0.0)), vec3(1.0 / max(midtone_lift, 0.05)));
	col = (col - vec3(0.5)) * contrast + vec3(0.5);

	// ============ 5. 亮暖暗冷 ============
	// 用亮度当遮罩：这是电影调色里最有效的"贵感"技巧
	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	float hi_mask = smoothstep(0.22, 0.85, lum);
	float lo_mask = 1.0 - smoothstep(0.04, 0.30, lum);
	vec3 tinted = col;
	tinted = mix(tinted, tinted * highlight_tint * 1.06, hi_mask * split_amount);
	tinted = mix(tinted, tinted * shadow_tint, lo_mask * split_amount * 0.80);
	col = mix(col, tinted, tint_mix);

	// ============ 6. 饱和度 ============
	// 暗部额外去色：参考图里暗区几乎无彩（sat 0.009）
	float lum2 = dot(col, vec3(0.2126, 0.7152, 0.0722));
	float sat_here = saturation * mix(0.55, 1.0, smoothstep(0.02, 0.35, lum2));
	col = mix(vec3(lum2), col, sat_here);

	// ============ 7. 暗角 ============
	if (vignette_strength > 0.001) {
		vec2 v = (uv - VIGNETTE_CENTER) * vec2(1.0, 0.86);
		float d = length(v) * 1.63;
		float vig = smoothstep(vignette_inner, 1.18, d);
		col *= 1.0 - vig * vignette_strength;
	}

	// ============ 8. 颗粒 ============
	if (grain_amount > 0.001) {
		float n = hash12(uv * vec2(1920.0, 1080.0) + vec2(TIME * 91.7 * grain_speed, TIME * 47.3 * grain_speed));
		// 颗粒在中间调最明显，暗部与亮部收敛（真实胶片特性）
		float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
		float w = 1.0 - abs(l * 2.0 - 1.0);
		col += (n - 0.5) * grain_amount * (0.35 + w * 0.65) * 2.0;
	}

	COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), 1.0);
}
