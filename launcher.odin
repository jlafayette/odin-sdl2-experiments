package launcher

import "core:fmt"
import "core:time"
import "vendor:sdl2"
import mu "vendor:microui"

WindowSettings :: struct {
	w: i32,
	h: i32,
}
win := WindowSettings {
	w = 1280,
	h = 960,
}
TARGET_DT: f64 = 1000 / 60


main :: proc() {
	assert(sdl2.Init({.VIDEO}) == 0, sdl2.GetErrorString())
	defer sdl2.Quit()

	window := sdl2.CreateWindow(
		"Laucher",
		sdl2.WINDOWPOS_UNDEFINED,
		sdl2.WINDOWPOS_UNDEFINED,
		win.w,
		win.h,
		{.SHOWN},
	)
	assert(window != nil, sdl2.GetErrorString())
	defer sdl2.DestroyWindow(window)

	renderer := sdl2.CreateRenderer(window, -1, sdl2.RENDERER_ACCELERATED)
	assert(renderer != nil, sdl2.GetErrorString())
	defer sdl2.DestroyRenderer(renderer)

	// Init microui
	atlas_texture := sdl2.CreateTexture(
		renderer,
		u32(sdl2.PixelFormatEnum.RGBA32),
		.TARGET,
		mu.DEFAULT_ATLAS_WIDTH,
		mu.DEFAULT_ATLAS_HEIGHT,
	)
	assert(atlas_texture != nil, sdl2.GetErrorString())
	err := sdl2.SetTextureBlendMode(atlas_texture, .BLEND)
	assert(err == 0, sdl2.GetErrorString())
	atlas_size := mu.DEFAULT_ATLAS_WIDTH * mu.DEFAULT_ATLAS_HEIGHT
	pixels := make([][4]u8, atlas_size)
	for alpha, i in mu.default_atlas_alpha {
		pixels[i].rgb = 0xff
		pixels[i].a = alpha
	}
	err = sdl2.UpdateTexture(atlas_texture, nil, raw_data(pixels), 4 * mu.DEFAULT_ATLAS_WIDTH)
	assert(err == 0, sdl2.GetErrorString())
	mu_ctx: mu.Context
	mu.init(&mu_ctx)

	mu_ctx.text_width = mu.default_atlas_text_width
	mu_ctx.text_height = mu.default_atlas_text_height

	start: f64
	end: f64

	game_loop: for {
		start = get_time()

		event: sdl2.Event
		for sdl2.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				break game_loop
			}
		}

		free_all(context.temp_allocator)
		end = get_time()
		to_sleep := time.Duration((TARGET_DT - (end - start)) * f64(time.Millisecond))
		time.accurate_sleep(to_sleep)
	}

}

get_time :: proc() -> f64 {
	return f64(sdl2.GetPerformanceCounter()) * 1000 / f64(sdl2.GetPerformanceFrequency())
}
