shader_type canvas_item;
render_mode blend_mix, unshaded;

// ============================================================================
// tears.gdshader —— 负面句结算时的「泪水滤镜」
//
// 想要的感觉：眼前突然涌上泪水 —— 视线被水膜扭曲、边缘模糊、颜色被冲淡。
// 不是「哭得很惨」，而是「一瞬间看不清了」。
//
// 处理链：
//   1. 水波扭曲（UV 偏移，模拟透过水膜看东西）
//   2. 纵向流泪痕（沿 Y 轴的轻微拖拽）
//   3. 边缘模糊（径向 -> 越靠边越糊，中心保持可读）
//   4. 饱和度降低 + 轻微泛蓝（泪水的冷感）
//   5. 暗角加重（视野收窄）
//   6. 高光水珠（几处亮点，模拟泪滴反光）
//
// 强度由 strength 统一控制（0 = 完全无效果）。
// ============================================================================

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

// 总强度 0~1（由脚本淡入淡出）
uniform float strength : hint_range(0.0, 1.0) = 0.0;

// ---------------- 水波扭曲 ----------------
// 扭曲幅度（UV 单位，0.01 = 屏幕宽度的 1%）
uniform float distort_amount : hint_range(0.0, 0.05) = 0.0045;
// 波纹密度（越大越细碎）
uniform float wave_freq : hint_range(1.0, 30.0) = 9.0;
// 流动速度
uniform float wave_speed : hint_range(0.0, 5.0) = 1.6;

// ---------------- 纵向泪痕 ----------------
// 沿 Y 方向的拖拽强度
uniform float streak_amount : hint_range(0.0, 0.05) = 0.0018;

// ---------------- 边缘模糊 ----------------
// 模糊半径（UV 单位）。中心不模糊，边缘到这个值
uniform float blur_amount : hint_range(0.0, 0.02) = 0.0028;
// 模糊从哪里开始（0 = 从中心开始，0.5 = 只糊最外围）
uniform float blur_start : hint_range(0.0, 1.0) = 0.52;

// ---------------- 颜色 ----------------
// 饱和度降低程度
uniform float desaturate : hint_range(0.0, 1.0) = 0.28;
// 泛蓝染色（泪水的冷感）
uniform vec3 tear_tint : source_color = vec3(0.78, 0.86, 1.00);
uniform float tint_amount : hint_range(0.0, 0.5) = 0.08;

// ---------------- 暗角 ----------------
uniform float vignette : hint_range(0.0, 1.5) = 0.34;
uniform float vignette_softness : hint_range(0.1, 1.0) = 0.55;

// ---------------- 水珠高光 ----------------
uniform float droplet_amount : hint_range(0.0, 1.0) = 0.20;

// 时间（脚本推进）
uniform float time_sec = 0.0;


float hash21(vec2 p) {
	p = fract(p * vec2(233.34, 851.73));
	p += dot(p, p + 23.45);
	return fract(p.x * p.y);
}

// 简单的 4 采样模糊
vec3 blur_sample(vec2 uv, float radius) {
	vec3 acc = texture(screen_tex, uv).rgb * 0.4;
	acc += texture(screen_tex, uv + vec2(radius, 0.0)).rgb * 0.15;
	acc += texture(screen_tex, uv - vec2(radius, 0.0)).rgb * 0.15;
	acc += texture(screen_tex, uv + vec2(0.0, radius)).rgb * 0.15;
	acc += texture(screen_tex, uv - vec2(0.0, radius)).rgb * 0.15;
	return acc;
}


void fragment() {
	if (strength <= 0.001) {
		COLOR = texture(screen_tex, SCREEN_UV);
	} else {
		vec2 uv = SCREEN_UV;
		vec2 centered = uv - vec2(0.5);
		float dist = length(centered);

		// ---- 1. 水波扭曲 ----
		// 两层不同频率的正弦叠加，避免出现规则的"方格感"
		float w1 = sin(uv.y * wave_freq + time_sec * wave_speed) * 0.5;
		float w2 = cos(uv.x * wave_freq * 0.7 - time_sec * wave_speed * 0.8) * 0.5;
		vec2 wave = vec2(w1, w2) * distort_amount * strength;
		// 边缘扭曲更明显（水膜积在眼睛下缘）
		wave *= (0.4 + dist * 1.6);

		// ---- 2. 纵向泪痕 ----
		// 沿 -Y 拖一点，像泪往下淌
		float streak = sin(uv.x * 28.0 + time_sec * 0.7) * streak_amount * strength;
		vec2 streak_off = vec2(0.0, -streak * (0.3 + uv.y * 0.7));

		vec2 sample_uv = clamp(uv + wave + streak_off, vec2(0.001), vec2(0.999));

		// ---- 3. 边缘模糊 ----
		float blur_mask = smoothstep(blur_start, 1.0, dist * 1.42);
		float radius = blur_amount * strength * blur_mask;
		vec3 col;
		if (radius > 0.0005) {
			col = blur_sample(sample_uv, radius);
		} else {
			col = texture(screen_tex, sample_uv).rgb;
		}

		// ---- 4. 去饱和 + 泛蓝 ----
		float lum = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(col, vec3(lum), desaturate * strength);
		col = mix(col, col * tear_tint * 1.08, tint_amount * strength);

		// ---- 5. 暗角 ----
		float vig = smoothstep(0.5, vignette_softness, dist * 1.42);
		col *= 1.0 - vig * vignette * strength;

		// ---- 6. 水珠高光 ----
		// 几个随机位置的亮点，随时间轻微飘动
		for (int i = 0; i < 5; i++) {
			float fi = float(i);
			vec2 center = vec2(
				hash21(vec2(fi, 1.7)) * 0.9 + 0.05,
				hash21(vec2(fi, 5.3)) * 0.9 + 0.05
			);
			float flick = 0.85 + 0.15 * sin(time_sec * 2.1 + fi * 2.3);
			float d = length(uv - center);
			float glow = smoothstep(0.045, 0.0, d) * flick;
			col += vec3(0.55, 0.65, 0.85) * glow * droplet_amount * strength * 0.35;
		}

		COLOR = vec4(col, 1.0);
	}
}
