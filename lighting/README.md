# 烛光法线光照系统（从「测试动画」项目原样保留）

这是**昨天在动画测试项目里做的光照系统**，作为独立模块保留在《接住》工程内，不依赖接住任何脚本，
可以单独运行：

- 演示场景：`res://lighting/lighting_demo.tscn`（编辑器里打开后按 **F6**）
- 目录内文件：
  - `sprite_normal_lit.gdshader` / `sprite_normal_lighting.gd` —— 角色法线光照（①）
  - `ambient_bounce.gdshader` —— 背景漫反射（②）
  - `candle_film.gdshader` / `candle_film.gd` —— 全屏滤镜（③）
  - `albedo/*.png` —— 三套动画贴图（常态 / 大幅度 / 跳吓）
  - `normal/*.png` —— 与三套动画一一对应的法线贴图
  - `flame_pos.json` —— 烛火核心位置的分析数据（供调参参考）

相对原项目的改动只有路径：`res://png_fix/` → `res://lighting/albedo/`、
`res://法线_fix/` → `res://lighting/normal/`，脚本/着色器都在同目录，逻辑一行未改。

> 注意：《接住》工程用的是 **gl_compatibility** 渲染器（原动画测试项目是 Forward+）。
> 实测三套着色器在本工程下都能正常出图（都只用到 `hint_screen_texture` / `SCREEN_UV`）。

---

# 测试动画 · 烛光法线光照系统

一个 Godot 4.7 的 2D 角色技术原型：**用真实法线贴图驱动光照**，配合全屏滤镜和背景漫反射，把 2D 立绘压进「昏暗房间 + 单一烛火」的氛围里。

---

## 一、项目概览

| 项 | 值 |
| --- | --- |
| 引擎 | Godot 4.7.2 |
| 渲染器 | Forward+ |
| 窗口 | 由 `display/window/stretch` 自适应（截图按 1152×648 记录） |
| 主场景 | `lighting_demo.tscn` |
| 动画 | 3 套：常态 5 帧 / 大幅度 5 帧 / 跳吓 6 帧 |

### 场景节点结构

```
Node2D
├── BounceLayer          CanvasLayer (layer = -10)   背景漫反射
│   └── BounceRect       ColorRect  套 ambient_bounce.gdshader
├── FilmLayer            CanvasLayer (layer = 10)    全屏滤镜
│                        script = candle_film.gd
├── AnimatedSprite2D     角色本体，套 sprite_normal_lit.gdshader
└── NormalLightDriver    驱动器，script = sprite_normal_lighting.gd
```

**图层顺序很关键**：`BounceLayer(-10)` < 角色(0) < `FilmLayer(10)`。
滤镜必须在角色之上才能读到已画好的画面；背景漫反射必须在角色之下才不会被滤镜重复处理。

---

## 二、三个功能模块

整个系统分三层，各管一件事，互不重叠：

| 模块 | 文件 | 负责 |
| --- | --- | --- |
| **① 角色法线光照** | `sprite_normal_lit.gdshader` | 人物身上的明暗、高光、轮廓 |
| **② 背景漫反射** | `ambient_bounce.gdshader` | 烛光打在墙面/地板上的柔光 |
| **③ 全屏滤镜** | `candle_film.gdshader` + `candle_film.gd` | 整体压暗、暗角、颗粒、光晕 |

---

## 三、① 角色法线光照

### 核心原理

用真实法线贴图做 **N·L 光照**：法线决定表面朝向，光照方向决定明暗。

```glsl
// 1. 采样本帧对应的法线
vec2 n_uv = normal_atlas_offset + UV * normal_atlas_scale;
vec3 nrgb = texture(normal_tex, n_uv).rgb;
vec3 n = normalize(vec3(nrgb.xy * 2.0 - 1.0, nrgb.z));

// 2. 光源方向（从当前像素指向烛火）
vec2 to_light = light_screen_uv - SCREEN_UV;
vec3 L = normalize(vec3(dir2d.x, -dir2d.y, light_height));

// 3. 漫反射
float ndl = max(dot(n, L), 0.0);
```

### 三个关键设计决策

#### 1. 光源用「屏幕空间」，不用「贴图空间」

角色在屏幕上移动时，明暗会随之变化，而不是像贴纸一样粘在贴图上。

```glsl
vec2 to_light = light_screen_uv - SCREEN_UV;   // 屏幕坐标
```

如果把光源固定在贴图 UV 上，人物一移动高光就跟着脸走 —— 一眼假。

#### 2. y 轴要取反

```
UV 的 v 轴向下（屏幕习惯）
法线的 g 轴向上（OpenGL 约定）
```

所以光方向的 y 分量必须取反，否则会变成「烛光在右、左脸反而更亮」：

```glsl
vec3 L = normalize(vec3(dir2d.x, -dir2d.y, light_height));
```

如果凹凸方向看起来反了，把 `normal_flip_y` 打开。

#### 3. 漫反射做「严格有界软限幅」

材质里含接近纯白的像素（实测 albedo = `0.99 / 0.92 / 0.76` 的暖白，应该是烛台金属反光）。这类像素乘 `light_energy × ndl` 后必然超过 1.0，直接截断会爆成白斑。

```glsl
vec3 diffuse = raw / (vec3(1.8) + raw);
```

**必须写成 `k + x`（x 的系数为 1）**。曾经写成 `x / (0.62 + 1.6x)`，分母 x 系数大于 1，结果在大值处**反向爬升**，比不压还亮。

### 跳吓逆光模式

跳吓第 3、4 帧是头部凑近镜头的惊吓帧，此时烛火在人头**背后**，应该变成剪影。

```glsl
if (backlight_mix > 0.001) {
    float faced = clamp(ndl, 0.0, 1.0);
    float rim_b = pow(1.0 - faced, 1.6);   // 越背光越亮
    vec3 silhouette = tex.rgb * amb_light * 0.05;
    vec3 edge = light_color * (0.02 + rim_b * 0.28) * rim_strength * back_atten;
    lit = mix(lit, silhouette + edge, backlight_mix);
}
```

**判据用「背光程度 (1 − n·L)」，不能用「法线 z 小」**。
实测跳吓帧的法线 z 均值是 0.954（几乎正对镜头），`pow(1-z, 4)` 会趋近 0，轮廓光算不出来，整帧全黑。

### 可调参数

选中 `AnimatedSprite2D`，材质面板里调：

| 参数 | 当前值 | 作用 |
| --- | --- | --- |
| `light_screen_uv` | (0.89, 0.42) | 烛火屏幕位置，**人物移动时要改** |
| `light_energy` | 3.0 | 烛光强度 |
| `light_range` | 0.38 | 光照半径 |
| `falloff_power` | 2.3 | 衰减指数，越大越聚光 |
| `ambient_level` | 0.55 | 环境底光，**超过 1.2 会过曝** |
| `ambient_tint` | 0.34 | 环境色参与度 |
| `normal_strength` | 1.0 | 凹凸强度 |
| `spec_strength` | 0.16 | 高光，调高容易出爆点 |

---

## 四、② 背景漫反射

**不依赖任何背景贴图**，纯解析计算烛光打在墙面后的反弹光。

```glsl
// 1. 径向衰减（比直射光平缓得多）
float radial = 1.0 / (1.0 + pow(d / bounce_radius, bounce_falloff));

// 2. 核心亮斑：烛火附近最近的墙最亮
float core = exp(-d / core_radius) * core_strength;

// 3. 垂直偏置：上方是墙、下方是地，反射率不同
float vert = mix(1.0 - vertical_bias, 1.0 + vertical_bias, v);
```

三个特征都做了，所以看起来像「房间被这支蜡烛照着」，而不是均匀的雾。

| 参数 | 当前值 | 作用 |
| --- | --- | --- |
| `bounce_strength` | 0.13 | 整体强度，**再高会盖过人物** |
| `bounce_radius` | 0.85 | 扩散范围 |
| `vertical_bias` | 0.5 | 上墙亮还是下地亮 |

---

## 五、③ 全屏滤镜

### 处理链（顺序与真实摄影机一致）

```
曝光 → 烛光 bloom → 空气雾 → 黑场/对比 →
亮暖暗冷分离 → 饱和度 → 暗角 → 胶片颗粒
```

### 两个易错点

#### 1. `midtone_lift` 的方向

```glsl
col = pow(col, vec3(1.0 / midtone_lift));
```

- `midtone_lift < 1` → 指数 > 1 → **压暗**中间调
- `midtone_lift > 1` → 指数 < 1 → **提亮**暗部

想压暗背景就设 0.8 左右，设成 1.35 反而更亮。

#### 2. 雾要随亮度减弱

无差别加雾会把角色一起糊掉：

```glsl
float keep = smoothstep(0.02, 0.22, lh);   // 越亮越不受雾影响
col = mix(col, haze_color, haze_amount * band * (1.0 - keep * 0.9));
```

### 图层与 UI

`candle_film.gd` 里 `layer = film_layer`（默认 10）。

- 游戏内容在 layer 0
- 滤镜在 layer 10
- **想让 UI 不被调色，放 layer 20+**

---

## 六、驱动器：NormalLightDriver

`sprite_normal_lighting.gd` 每帧做四件事：

### 1. 帧 → 法线格子映射

```gdscript
var reg := _current_region()   # 当前帧的 AtlasTexture.region
offset = reg.position / sheet_px
nscale = reg.size / sheet_px
```

**直接从 `AtlasTexture.region` 读真实像素矩形**，不按 `frame % 列数` 手算 —— 手算会错帧。

### 2. 换动画时换法线图集

```gdscript
if want != _bound_normal_name and normal_sheets.has(want):
    _mat.set_shader_parameter("normal_tex", load(normal_sheets[want]))
```

不换会导致：播「跳吓」却采样「常态」的法线，光照完全错位（表现为整帧发黑）。

### 3. 火光位置跟随

每帧火焰在帧内的位置写死在 `FLAME_UV` 表里（由图像分析得出）：

```gdscript
const FLAME_UV := {
    "default": [Vector2(0.712, 0.548), ...],   # 常态
    "大幅度":  [Vector2(0.712, 0.547), ...],
    "跳吓":   [Vector2(0.712, 0.547), ...],
}
```

**坐标换算公式（这里踩过两次坑）**：

```
AnimatedSprite2D + AtlasTexture 的行为是：
  AtlasTexture 把 region 裁成独立纹理，当普通贴图画
所以 shader 里的 UV 就是「这一帧内部的 0~1」

屏幕像素 = global_position + (帧内UV - 0.5) × 帧尺寸 × global_scale
```

一开始按「整张 6000×6000 图集」算，坐标跑到 y = −108 画面外，光晕位置全错。

### 4. 光源平滑

```gdscript
_smooth_uv = _smooth_uv.lerp(fuv, 1.0 - light_smoothing)   # 默认 0.75
```

火焰逐帧位置有微小抖动，不平滑会让受光区域忽大忽小，看起来像闪烁。

### 同步给滤镜和背景

光源位置同时推给三层，保证光晕、漫反射、角色受光**指向同一个点**：

```gdscript
_mat.set_shader_parameter("light_screen_uv", fuv)   # 角色
film.set("light_uv", fuv)                            # 滤镜
_bounce_mat.set_shader_parameter("light_uv", fuv)    # 背景
```

---

## 七、素材组织

### 目录说明

| 目录 | 内容 | 用途 |
| --- | --- | --- |
| `png/` `法线/` | 6000×6000 原始图集 | **源文件，不要动** |
| `png_fix/` `法线_fix/` | 3000×2604 重切图集 | **游戏实际使用** |
| `png_half/` `法线_half/` | 3000×3000 旧版均分图集 | 已废弃，可删 |

### 为什么需要 `_fix`

原图集的**行边界不均匀**（用空白带测出来）：

| 位置 | y 范围 | 高度 |
| --- | --- | --- |
| 顶部空白 | 0 – 755 | 755 |
| 第 1 行角色 | 755 – 2619 | 1864 |
| 中间空白 | 2619 – 3376 | 757 |
| 第 2 行角色 | 3376 – 5230 | 1854 |
| 底部空白 | 5230 – 6000 | 770 |

如果按均分 2605 切格子，第 2 行会切进角色中间，把上下都裁掉 —— 表现为「靠后的帧显示不完整、亮度异常」。

`_fix` 图集按真实边界重切，并把每帧角色统一缩放到相同高度（931px），底部对齐。

### 当前图集规格

```
尺寸：3000 × 2604
布局：3 列 × 2 行，每格 1000 × 1302
      帧 0 1 2  →  y = 0
      帧 3 4 5  →  y = 1302
```

### 火焰位置数据

`flame_pos.json` 存了每帧烛火核心的帧内归一化坐标（由图像分析得出，取质心）。

---

## 八、常见问题

### 画面整体发灰、背景不是黑的

检查 `BounceLayer` 是否存在且 `layer = -10`。
背景发灰也可能是 Godot 默认清屏色，加纯黑底层可以盖掉。

### 某些帧突然变白

按这个顺序排查：

1. `ambient_level` 是否超过 1.2
2. 漫反射软限幅公式是否是 `k + x` 形式
3. 图集是否用了均分切分（应该用 `_fix`）

### 光晕没跟到烛火上

- 检查 `FLAME_UV` 表的坐标
- 检查 `_flame_screen_uv()` 是否按「帧内 UV」而不是「图集 UV」计算
- 检查滤镜的 `light_uv` 是否被 driver 覆盖（`candle_film.gd` 里有硬编码默认值）

### 切换动画后光照全错

`normal_sheets` 字典里必须有该动画名，且路径指向 `法线_fix`。

### 显存不足

三套动画 × 2 种贴图 × 6000×6000 = 824MB。
必须用 3000 尺寸（206MB），否则 GTX 1650 这类 4GB 卡会报：

```
Can't create buffer of size: 268435456
```

### 采样到重命名后的旧贴图

Godot 的 `ext_resource` 里如果带 `uid=`，会**优先按 uid 解析**，而不是 path。
改名后必须删掉 uid 那一行，否则永远加载旧文件。

---

## 九、性能

| 项 | 说明 |
| --- | --- |
| 法线采样 | 每像素 2 次 texture（albedo + normal） |
| bloom | 9 抽头模糊，是最大开销 |
| 漫反射 | 纯解析，几乎零成本 |

**降负载顺序**：
1. `bloom_strength = 0`（跳过整个 bloom 分支）
2. 把 `tap_blur` 的 9 次采样减到 5 次
3. `glow_strength = 0`

---

## 十、文件清单

| 文件 | 作用 |
| --- | --- |
| `lighting_demo.tscn` | 主场景 |
| `sprite_normal_lit.gdshader` | 角色法线光照 |
| `sprite_normal_lighting.gd` | 光照驱动器 |
| `ambient_bounce.gdshader` | 背景漫反射 |
| `candle_film.gdshader` | 全屏滤镜 |
| `candle_film.gd` | 滤镜控制器 |
| `flame_pos.json` | 逐帧火焰位置数据 |
| `png_fix/` `法线_fix/` | 游戏用图集（3000） |
| `png/` `法线/` | 原始图集（6000，源文件） |
