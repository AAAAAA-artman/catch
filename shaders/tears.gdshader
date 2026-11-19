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
// 模糊/水珠的额外倍率（第三阶段「逐渐流泪」用，默认 1 = 不影响负面句效果）
uniform float blur_boost : hint_range(0.5, 5.0) = 1.0;

// ---------------- 颜色 ----------------
// 饱和度降低程度
uniform float desaturate : hint_range(0.0, 1.0) = 0.28;
// 泛蓝染色（泪水的冷感）
uniform vec3 tear_tint : source_color = vec3(0.78, 0.86, 1.00);
uniform float tint_amount : hint_range(0.0, 0.5) = 0.08;

// ---------------- 暗角 ----------------
uniform float vignette : hint_range(0.0, 1.5) = 0.34;
uniform float vignette_softness : hint_range(0.1, 1.0) = 0.55;

// ---------------- 水珠 ----------------
// 水珠数量与强度
uniform float droplet_amount : hint_range(0.0, 1.0) = 0.85;
// 每颗水珠的半径（UV 单位）—— 水珠周围这一片会被模糊
uniform float droplet_radius : hint_range(0.02, 0.30) = 0.115;
// 水珠边缘模糊圈的厚度倍率
uniform float droplet_blur_scale : hint_range(1.0, 3.0) = 2.2;
// 水珠内部的高光强度
uniform float droplet_highlight : hint_range(0.0, 1.0) = 0.62;
uniform float droplet_boost : hint_range(0.0, 2.0) = 1.0;

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
		float radius = blur_amount * blur_boost * strength * blur_mask;
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

		// ---- 6. 水珠：每颗水珠模糊它周围一片 ----
		vec3 colorAcc = col;
		float totalBlur = 0.0;
		for (int i = 0; i < 8; i++) {
			float fi = float(i);
			// 水珠位置（归一化），每颗大小略有不同
			vec2 dcenter = vec2(
				hash21(vec2(fi * 3.1, 1.7)) * 0.88 + 0.06,
				hash21(vec2(fi * 7.3, 5.3)) * 0.88 + 0.06
			);
			// 缓慢漂移，让水珠像"挂在镜片上"而不是死点
			dcenter += vec2(sin(time_sec * 0.31 + fi * 1.7),
				cos(time_sec * 0.42 + fi * 2.3)) * 0.020;
			float dr = droplet_radius * (0.65 + hash21(vec2(fi, 9.1)) * 0.7);
			float flick = 0.9 + 0.1 * sin(time_sec * 1.7 + fi * 2.3);

			// 水珠内圈（实心区域，模糊最强）
			float d = length(uv - dcenter);
			float inner = smoothstep(dr, dr * 0.35, d);

			if (inner > 0.001) {
				// 这一片单独再模糊一次，模拟透过水珠折射
				float localBlur = blur_amount * strength * droplet_blur_scale * dr * 18.0;
				vec3 blurred = blur_sample(sample_uv + (uv - dcenter) * 0.06, localBlur);
				// 水珠里的画面：模糊 + 轻微放大 + 提亮
				vec3 dropletCol = mix(colorAcc, blurred * 1.12, inner);
				// 水珠内的高光点（偏左上）
				vec2 hl = dcenter + vec2(-dr * 0.32, -dr * 0.32);
				float hd = length(uv - hl);
				float glow = smoothstep(dr * 0.55, 0.0, hd) * flick;
				dropletCol += vec3(0.85, 0.92, 1.0) * glow * droplet_highlight * strength;
				// 水珠外缘的暗边（模拟表面张力）
				float rim = smoothstep(dr * 1.05, dr * 0.92, d) * smoothstep(dr * 0.85, dr * 0.98, d);
				dropletCol *= 1.0 - rim * 0.18 * strength;

				colorAcc = mix(colorAcc, dropletCol, clamp(inner * droplet_amount * droplet_boost, 0.0, 1.0));
				totalBlur = max(totalBlur, inner);
			}
		}
		col = colorAcc;

		COLOR = vec4(col, 1.0);
	}
}
