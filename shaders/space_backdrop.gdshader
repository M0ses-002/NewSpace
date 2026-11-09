shader_type canvas_item;
render_mode unshaded;

// 太空背景：一次全屏绘制搞定「星云 + 两层星点 + 暗角」。
//
// 时间（time）与两层视差偏移（far_offset / near_offset）都由 space_backdrop.gd 传进来，
// 故意不用内建 TIME：暂停、关闭动效、调强度时才能精确冻住，测试也可复现同一帧。
// 星点是程序化哈希生成的，不依赖贴图，缩放窗口不会糊，也不会出现纹理重复接缝。

uniform vec2 resolution = vec2(1200.0, 720.0);
uniform float time = 0.0;
uniform vec2 far_offset = vec2(0.0);
uniform vec2 near_offset = vec2(0.0);
uniform float intensity : hint_range(0.0, 1.0) = 1.0;

uniform vec3 base_color : source_color = vec3(0.008, 0.011, 0.024);
uniform vec3 nebula_color_a : source_color = vec3(0.06, 0.15, 0.36);
uniform vec3 nebula_color_b : source_color = vec3(0.22, 0.08, 0.28);
uniform float nebula_strength : hint_range(0.0, 1.5) = 0.6;
uniform float nebula_scale : hint_range(0.5, 6.0) = 4.2;

uniform float star_density : hint_range(0.0, 1.0) = 0.5;
uniform float star_brightness : hint_range(0.0, 3.0) = 1.0;
uniform float far_cell : hint_range(12.0, 200.0) = 34.0;
uniform float near_cell : hint_range(20.0, 300.0) = 82.0;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.55;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 三层倍频：再多一层在 1200×720 上肉眼几乎看不出，却要多算 4 次噪声采样。
float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 3; i++) {
		value += amplitude * value_noise(p);
		p *= 2.03;
		amplitude *= 0.5;
	}
	return value;
}

// 一层星点：按像素切格，每格最多一颗星，位置在格内抖动。
// 好处是密度只跟格子大小挂钩，与分辨率无关；缺点是格边可能看出规律，所以两层用不同格宽与种子互相打散。
// 半径与光晕一律按「像素」算：早先按格子比例算，近景层 104px 的格子会把星点吹成 20px 的大光斑。
vec3 star_layer(vec2 pixel, float cell, float seed, float radius_px) {
	vec2 grid = pixel / cell;
	vec2 id = floor(grid);
	vec2 local = (fract(grid) - 0.5) * cell;

	// 只有一部分格子有星，密度调的是这个比例。
	float present = step(1.0 - star_density * 0.55, hash12(id + seed + 41.7));

	vec2 jitter = (vec2(hash12(id + seed + 11.3), hash12(id + seed + 27.7)) - 0.5) * cell * 0.78;
	float distance_to_star = length(local - jitter);

	// 绝大多数星星是 1px 左右的点，少数按哈希放大 1.6 倍，形成「有明有暗」的层次。
	float size_jitter = 0.65 + 0.55 * hash12(id + seed + 5.1);
	float radius = radius_px * size_jitter;
	float core = smoothstep(radius, 0.0, distance_to_star);
	float halo = exp(-distance_to_star * distance_to_star * 0.22) * 0.32;

	// 闪烁幅度受 intensity 控制：intensity=0 时星点完全静止。
	float phase = hash12(id + seed + 9.7) * 6.2831;
	float flicker = mix(1.0, 0.62 + 0.38 * sin(time * (0.5 + 1.8 * hash12(id + seed + 13.9)) + phase), intensity);

	float brightness = (core + halo) * flicker * (0.3 + 0.9 * hash12(id + seed + 3.3));
	vec3 tint = mix(vec3(0.72, 0.8, 1.0), vec3(1.0, 0.9, 0.74), hash12(id + seed + 7.7));
	return tint * brightness * present;
}

void fragment() {
	vec2 uv = UV;
	vec2 pixel = uv * resolution;

	// 星云：先域扭曲再取样，缓慢漂移，看起来像在流动而不是在平移。
	vec2 drift = vec2(time * 0.0045, time * 0.0026) * intensity;
	vec2 aspect = vec2(resolution.x / max(resolution.y, 1.0), 1.0);
	vec2 q = uv * aspect * nebula_scale + drift;
	vec2 warp = vec2(fbm(q * 0.65 + 4.3), fbm(q * 0.65 - 2.1));
	float cloud = fbm(q + warp * 0.85);
	cloud = smoothstep(0.36, 0.78, cloud);

	vec3 color = base_color;
	color = mix(color, nebula_color_a, cloud * nebula_strength * 0.9);
	color = mix(color, nebula_color_b, cloud * cloud * nebula_strength * 0.55);

	// 斜向银河带：给画面一条不居中的亮带，避免星云均匀铺满显得平。
	float band = smoothstep(0.42, 0.0, abs(uv.y - uv.x * 0.42 - 0.34));
	color += nebula_color_a * band * nebula_strength * 0.5;

	// 两层星点：远层小而暗、移动慢；近层大而亮、移动快。
	color += star_layer(pixel + far_offset, far_cell, 0.0, 1.1) * star_brightness;
	color += star_layer(pixel + near_offset, near_cell, 100.0, 1.9) * star_brightness * 1.15;

	// 暗角：把注意力压回屏幕中心，也让 HUD 边缘的文字更好读。
	vec2 centered = uv - 0.5;
	float vignette = 1.0 - smoothstep(0.34, 0.92, length(centered * vec2(1.12, 1.0))) * vignette_strength;
	color *= vignette;

	// 固定 dither：深色渐变不做抖动会在 8bit 输出上出现色带。
	float dither = (hash12(pixel) - 0.5) / 255.0;
	COLOR = vec4(max(color + dither, vec3(0.0)), 1.0);
}
