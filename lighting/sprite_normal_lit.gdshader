shader_type canvas_item;
render_mode blend_mix;
// ============================================================================
// sprite_normal_lit.gdshader —— 真法线贴图光照（AnimatedSprite2D 图集版）
//
// 【它负责什么 / 滤镜负责什么】
//   本 shader = 光照细节（N·L 明暗、高光、轮廓光）
//   滤镜      = 压暗、加颗粒、暗角、整体氛围
//   两者职责不重叠：没有本 shader，人物是「平的」；没有滤镜，人物太亮不融进夜景。
//
// 【为什么不能直接对 TEXTURE 采样法线】
//   AnimatedSprite2D 每次只把「当前帧区域」映射成 UV 0~1。
//   整个 6000x6000 法线图集不能直接用 UV 采样 —— 那会取到左上角那一帧。
//   必须重映射：normal_uv = normal_atlas_offset + UV * normal_atlas_scale
//   这两个参数由 sprite_normal_lighting.gd 在每次换帧时算好注入。
//
// 【坐标坑（非常重要）】
//   UV 的 v 轴向下（屏幕习惯），法线贴图的 g 轴向上（OpenGL 约定）。
//   所以光方向的 y 分量必须取反，否则会变成「光从右来、左边亮」。
//   如果凹凸感看起来反了，把 normal_flip_y 打开。
// ============================================================================

// ---------------- 法线贴图 ----------------
uniform sampler2D normal_tex : filter_linear, repeat_disable;
uniform vec2  normal_atlas_offset = vec2(0.0, 0.0);
uniform vec2  normal_atlas_scale  = vec2(0.3333, 0.4342);
uniform float normal_strength : hint_range(0.0, 3.0) = 1.0;
uniform bool  normal_flip_y = false;

// ---------------- 主光（烛火）----------------
uniform vec2  light_screen_uv = vec2(0.891, 0.532);
uniform vec3  light_color : source_color = vec3(1.0, 0.66, 0.36);
uniform float light_energy : hint_range(0.0, 8.0) = 2.6;
uniform float light_range : hint_range(0.05, 2.0) = 0.44;
uniform float light_height : hint_range(0.05, 3.0) = 0.55;
uniform float falloff_power : hint_range(0.5, 4.0) = 2.2;

// ---------------- 高光 ----------------
uniform float spec_strength : hint_range(0.0, 3.0) = 0.20;
uniform float spec_power : hint_range(2.0, 128.0) = 28.0;

// ---------------- 环境光（半球）----------------
uniform vec3  ambient_sky : source_color = vec3(0.34, 0.40, 0.56);
uniform vec3  ambient_ground : source_color = vec3(0.09, 0.08, 0.10);
uniform float ambient_level : hint_range(0.0, 2.0) = 0.75;
uniform float ambient_tint : hint_range(0.0, 1.0) = 0.28;

// ---------------- 轮廓光 ----------------
uniform float rim_strength : hint_range(0.0, 3.0) = 0.40;

// ---------------- 逆光模式（跳吓定格帧）----------------
// 头部凑近镜头时，烛火在人头身后。此时角色应变成剪影：
// 正面几乎全暗，只有轮廓被暖光镀亮 —— 恐怖片最经典的压迫感镜头。
uniform float backlight_mix : hint_range(0.0, 1.0) = 0.0;

// ---------------- 收尾 ----------------
uniform float brightness : hint_range(0.0, 2.0) = 1.20;
uniform float saturation : hint_range(0.0, 2.0) = 1.35;

// ---------------------------------------------------------------------------
// 【默认值说明】
//   下面这些默认值 = 工程里实测调好的那一组（不是随手写的）。
//   尤其 ambient_level 不要超过 1.2：albedo 本身很暗（亮度均值约 88/255），
//   环境光放太大会把暗部整体抬到过曝，表现为动画循环闪白。
// ---------------------------------------------------------------------------

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a < 0.02) {
		discard;
	}

	// ============ 1. 采样当前帧对应的法线 ============
	//
	// 【踩过的坑：alpha 边缘闪白】
	//   这套法线贴图的「背景」不是标准平坦法线 (0.5,0.5,1.0)，
	//   实测是 (0.285,0.285,0.57) —— 相当于一个极度倾斜的表面。
	//   角色轮廓的软边处，albedo 的 alpha 还在 0.1~0.5，
	//   于是采样到了这块背景法线，算出 ndl 很小的假光照，
	//   在特定帧近距离处直接爆成纯白，表现为循环闪白。
	//
	//   修法：用 albedo 的 alpha 当可信度。alpha 越低，越不信任法线，
	//   平滑过渡回「正对镜头」的中性法线 (0,0,1)。
	vec2 n_uv = normal_atlas_offset + UV * normal_atlas_scale;
	vec3 nrgb = texture(normal_tex, n_uv).rgb;
	vec2 nxy = nrgb.xy * 2.0 - 1.0;
	if (normal_flip_y) {
		nxy.y = -nxy.y;
	}

	// 法线可信度：alpha 从 0.35 到 0.85 之间平滑过渡
	float trust = smoothstep(0.35, 0.85, tex.a);
	// 不信任时退回中性法线，避免背景法线参与光照
	nxy = mix(vec2(0.0), nxy, trust);
	nxy *= normal_strength;
	float nz = mix(1.0, max(nrgb.z, 0.35), trust);
	vec3 n = normalize(vec3(nxy, nz));

	// ============ 2. 入射方向 ============
	vec2 to_light = light_screen_uv - SCREEN_UV;
	float dist = length(to_light);
	vec2 dir2d = (dist > 0.0001) ? (to_light / dist) : vec2(0.0);
	// y 取反：UV 向下，法线向上
	vec3 L = normalize(vec3(dir2d.x, -dir2d.y, light_height));

	float ndl = max(dot(n, L), 0.0);

	// ============ 3. 距离衰减 ============
	float t = clamp(1.0 - dist / light_range, 0.0, 1.0);
	float atten = pow(t, falloff_power);

	// ============ 4. 半球环境光 ============
	// 【这里曾经写错导致画面发灰】
	// 旧公式把环境色乘到 albedo 上再整体压暗，结果是
	// 「albedo × 0.3 左右」——角色被均匀压成灰片，法线的明暗全被冲掉。
	// 正确做法：环境光是「加法项」，用 albedo 调制它的颜色，
	// 再叠加漫反射。这样暗部有底光、亮部由 n·L 决定，层次才出得来。
	float hemi = n.y * 0.5 + 0.5;
	vec3 amb_color = mix(ambient_ground, ambient_sky, hemi);
	// 环境色只做轻微的色偏，不能吃掉原色
	vec3 amb_light = mix(vec3(1.0), amb_color * 2.0, ambient_tint);
	vec3 ambient_term = tex.rgb * amb_light * ambient_level * mix(0.55, 1.25, hemi);

	// ============ 5. 漫反射（主角）============
	// 【为什么这里要压高光】
	//   材质本身含接近纯白的像素（实测 albedo = 0.99/0.92/0.76 的暖白，
	//   应该是烛台金属的反光）。这类像素乘 light_energy*ndl 后必然 >1，
	//   直接截断就会出现"某些帧整片白斑"的闪烁。
	//   做法：对漫反射做软限幅（soft clamp），高能量时逐渐压缩，
	//   保证不超过 1.0，同时保留明暗层次。
	float diff_gain = ndl * atten * light_energy;
	vec3 raw = tex.rgb * light_color * diff_gain;
	// 有界软限幅：x/(1+x) 严格小于 1，单调递增，不会反弹
	// （之前写成 x/(0.62+1.6x) 会在大值处反向爬升，反而更亮）
	// 【严格有界】用 x/(k+x)，k 越大压得越狠；这里 k=1.8
	//   必须满足 分母 = k + x（x 系数为 1），否则大值处会反向爬升
	vec3 diffuse = raw / (vec3(1.8) + raw);

	vec3 lit = ambient_term + diffuse;

	// ============ 6. 高光 ============
	vec3 V = vec3(0.0, 0.0, 1.0);
	vec3 H = normalize(L + V);
	float spec = pow(max(dot(n, H), 0.0), spec_power);
	lit += light_color * spec * atten * spec_strength;

	// ============ 7. 轮廓光 ============
	float rim = pow(1.0 - clamp(n.z, 0.0, 1.0), 2.0);
	lit += light_color * rim * atten * rim_strength;

	// ============ 7.5 逆光剪影 ============
	// 【为什么不能用「法线 z 小」当轮廓判据】
	//   实测跳吓第4帧的法线 z 均值是 0.954（几乎正对镜头），
	//   pow(1-z, 4) 会趋近 0，轮廓光算不出来，整帧变成全黑。
	//
	// 【正确判据：背光程度】
	//   逆光的本质是「光在物体背后」，也就是 n·L 很小。
	//   用 (1 - ndl) 当遮罩：正对光的面（ndl≈1）保持暗，
	//   背光/侧光的面反而亮起来 —— 这才是真正的轮廓逆光。
	if (backlight_mix > 0.001) {
		// 背光程度：ndl 越小，越接近剪影边缘
		float faced = clamp(ndl, 0.0, 1.0);
		float rim_b = pow(1.0 - faced, 1.6);
		// 剪影底色：极暗
		vec3 silhouette = tex.rgb * amb_light * 0.05;
		// 轮廓暖光：按背光程度发光，不受距离衰减过度压制
		float back_atten = mix(0.45, 1.0, clamp(atten * 2.5, 0.0, 1.0));
		// 降低基线和增益：实测 1.1 会让背光面整片烧白
		vec3 edge = light_color * (0.02 + rim_b * 0.28) * clamp(rim_strength, 0.0, 2.0) * back_atten;
		vec3 back = silhouette + edge;
		lit = mix(lit, back, backlight_mix);
	}

	// ============ 8. 收尾 ============
	lit *= brightness;
	float g = dot(lit, vec3(0.2126, 0.7152, 0.0722));
	lit = mix(vec3(g), lit, saturation);

	COLOR = vec4(clamp(lit, vec3(0.0), vec3(1.0)), tex.a);
}
