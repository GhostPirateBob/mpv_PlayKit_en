// 文档 https://github.com/hooke007/mpv_PlayKit/wiki/4_GLSL

/*

LICENSE:
  --- Paper ver.
  https://johncostella.com/magic/

*/


//!HOOK MAIN
//!BIND HOOKED
<<<<<<< HEAD
<<<<<<< HEAD
//!SAVE MKC_H
//!DESC [Magic_Kernel_Classic] (Horizontal)
//!WIDTH OUTPUT.w
//!HEIGHT HOOKED.h
=======
//!DESC [Magic_Kernel_Classic]
//!WIDTH OUTPUT.w
//!HEIGHT OUTPUT.h
>>>>>>> 2078e47 (着色器： 新增 Magic Kernel 族)
=======
//!SAVE MKC_H
//!DESC [Magic_Kernel_Classic] (Horizontal)
//!WIDTH OUTPUT.w
//!HEIGHT HOOKED.h
>>>>>>> 87e324e (Shaders: Disassembling the Magic Kernel into a Dual-Pass Interface)
//!WHEN OUTPUT.w HOOKED.w = ! OUTPUT.h HOOKED.h = ! +

const float KERNEL_RADIUS = 1.5;
const int UPSCALE_RADIUS = 2;

float magic_kernel_classic(float x) {
	x = abs(x);
	if (x <= 0.5) return 0.75 - x * x;
	if (x < KERNEL_RADIUS) return 0.5 * (x - 1.5) * (x - 1.5);
	return 0.0;
}

vec4 hook() {

<<<<<<< HEAD
<<<<<<< HEAD
	float src_w = HOOKED_size.x;
	float dst_w = target_size.x;

	float ratio = src_w / dst_w;
	float scale = max(ratio, 1.0);
	int radius = (ratio > 1.0) ? int(ceil(KERNEL_RADIUS * scale)) : UPSCALE_RADIUS;

	float src_x = HOOKED_pos.x * src_w - 0.5;
	int src_base = int(floor(src_x));
	float frac_x = src_x - float(src_base);
	int cur_y = int(floor(HOOKED_pos.y * HOOKED_size.y));
=======
	vec2 src_size = HOOKED_size;
	vec2 dst_size = target_size;
=======
	float src_w = HOOKED_size.x;
	float dst_w = target_size.x;
>>>>>>> 87e324e (Shaders: Disassembling the Magic Kernel into a Dual-Pass Interface)

	float ratio = src_w / dst_w;
	float scale = max(ratio, 1.0);
	int radius = (ratio > 1.0) ? int(ceil(KERNEL_RADIUS * scale)) : UPSCALE_RADIUS;

<<<<<<< HEAD
	vec2 src_pos = HOOKED_pos * src_size - 0.5;
	ivec2 src_base = ivec2(floor(src_pos));
	vec2 frac_pos = src_pos - vec2(src_base);
>>>>>>> 2078e47 (着色器： 新增 Magic Kernel 族)
=======
	float src_x = HOOKED_pos.x * src_w - 0.5;
	int src_base = int(floor(src_x));
	float frac_x = src_x - float(src_base);
	int cur_y = int(floor(HOOKED_pos.y * HOOKED_size.y));
>>>>>>> 87e324e (Shaders: Disassembling the Magic Kernel into a Dual-Pass Interface)

	vec4 sum_color = vec4(0.0);
	float wsum = 0.0;

<<<<<<< HEAD
<<<<<<< HEAD
	for (int kx = -radius; kx <= radius; kx++) {
		int sx = src_base + kx;
		if (sx < 0 || sx >= int(src_w)) continue;

		float dx_dist = abs(frac_x - float(kx)) / scale;
		if (dx_dist >= KERNEL_RADIUS) continue;
		float w = magic_kernel_classic(dx_dist);

		vec4 sample_color = texelFetch(HOOKED_raw, ivec2(sx, cur_y), 0);
		sample_color = linearize(sample_color);
		sum_color += sample_color * w;
		wsum += w;
	}

	if (wsum > 0.0) {
		sum_color /= wsum;
	}
	return sum_color;

}

//!HOOK MAIN
//!BIND HOOKED
//!BIND MKC_H
//!DESC [Magic_Kernel_Classic] (Vertical)
//!WIDTH OUTPUT.w
//!HEIGHT OUTPUT.h

const float KERNEL_RADIUS = 1.5;
const int UPSCALE_RADIUS = 2;

float magic_kernel_classic_v(float x) {
	x = abs(x);
	if (x <= 0.5) return 0.75 - x * x;
	if (x < KERNEL_RADIUS) return 0.5 * (x - 1.5) * (x - 1.5);
	return 0.0;
}

vec4 hook() {

	float src_h = MKC_H_size.y;
	float dst_h = target_size.y;

	float ratio = src_h / dst_h;
	float scale = max(ratio, 1.0);
	int radius = (ratio > 1.0) ? int(ceil(KERNEL_RADIUS * scale)) : UPSCALE_RADIUS;

	float src_y = MKC_H_pos.y * src_h - 0.5;
	int src_base = int(floor(src_y));
	float frac_y = src_y - float(src_base);
	int cur_x = int(floor(MKC_H_pos.x * MKC_H_size.x));

	vec4 sum_color = vec4(0.0);
	float wsum = 0.0;

	for (int ky = -radius; ky <= radius; ky++) {
		int sy = src_base + ky;
		if (sy < 0 || sy >= int(src_h)) continue;

		float dy_dist = abs(frac_y - float(ky)) / scale;
		if (dy_dist >= KERNEL_RADIUS) continue;
		float w = magic_kernel_classic_v(dy_dist);

		vec4 sample_color = texelFetch(MKC_H_raw, ivec2(cur_x, sy), 0);
		sum_color += sample_color * w;
		wsum += w;
=======
	for (int ky = -radius.y; ky <= radius.y; ky++) {
		int sy = src_base.y + ky;
		if (sy < 0 || sy >= int(src_size.y)) continue;
=======
	for (int kx = -radius; kx <= radius; kx++) {
		int sx = src_base + kx;
		if (sx < 0 || sx >= int(src_w)) continue;
>>>>>>> 87e324e (Shaders: Disassembling the Magic Kernel into a Dual-Pass Interface)

		float dx_dist = abs(frac_x - float(kx)) / scale;
		if (dx_dist >= KERNEL_RADIUS) continue;
		float w = magic_kernel_classic(dx_dist);

		vec4 sample_color = texelFetch(HOOKED_raw, ivec2(sx, cur_y), 0);
		sample_color = linearize(sample_color);
		sum_color += sample_color * w;
		wsum += w;
	}

	if (wsum > 0.0) {
		sum_color /= wsum;
	}
	return sum_color;

}

//!HOOK MAIN
//!BIND HOOKED
//!BIND MKC_H
//!DESC [Magic_Kernel_Classic] (Vertical)
//!WIDTH OUTPUT.w
//!HEIGHT OUTPUT.h

const float KERNEL_RADIUS = 1.5;
const int UPSCALE_RADIUS = 2;

float magic_kernel_classic_v(float x) {
	x = abs(x);
	if (x <= 0.5) return 0.75 - x * x;
	if (x < KERNEL_RADIUS) return 0.5 * (x - 1.5) * (x - 1.5);
	return 0.0;
}

vec4 hook() {

	float src_h = MKC_H_size.y;
	float dst_h = target_size.y;

	float ratio = src_h / dst_h;
	float scale = max(ratio, 1.0);
	int radius = (ratio > 1.0) ? int(ceil(KERNEL_RADIUS * scale)) : UPSCALE_RADIUS;

	float src_y = MKC_H_pos.y * src_h - 0.5;
	int src_base = int(floor(src_y));
	float frac_y = src_y - float(src_base);
	int cur_x = int(floor(MKC_H_pos.x * MKC_H_size.x));

	vec4 sum_color = vec4(0.0);
	float wsum = 0.0;

	for (int ky = -radius; ky <= radius; ky++) {
		int sy = src_base + ky;
		if (sy < 0 || sy >= int(src_h)) continue;

		float dy_dist = abs(frac_y - float(ky)) / scale;
		if (dy_dist >= KERNEL_RADIUS) continue;
		float w = magic_kernel_classic_v(dy_dist);

<<<<<<< HEAD
		for (int kx = -radius.x; kx <= radius.x; kx++) {
			int sx = src_base.x + kx;
			if (sx < 0 || sx >= int(src_size.x)) continue;

			float dx_dist = abs(frac_pos.x - float(kx)) / scale.x;
			if (dx_dist >= KERNEL_RADIUS) continue;
			float wx = magic_kernel_classic(dx_dist);

			float w = wx * wy;
			vec4 sample_color = texelFetch(HOOKED_raw, ivec2(sx, sy), 0);
			sample_color = linearize(sample_color);
			sum_color += sample_color * w;
			wsum += w;
		}
>>>>>>> 2078e47 (着色器： 新增 Magic Kernel 族)
=======
		vec4 sample_color = texelFetch(MKC_H_raw, ivec2(cur_x, sy), 0);
		sum_color += sample_color * w;
		wsum += w;
>>>>>>> 87e324e (Shaders: Disassembling the Magic Kernel into a Dual-Pass Interface)
	}

	if (wsum > 0.0) {
		sum_color /= wsum;
	}

	vec4 orig = HOOKED_texOff(0);
	sum_color = delinearize(sum_color);
	sum_color.a = orig.a;
	return sum_color;

}

