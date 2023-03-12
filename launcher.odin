package launcher

import "core:fmt"
import "core:time"
import "vendor:sdl2"
import mu "vendor:microui"

import "dynamic_text"

WindowSettings :: struct {
	w: i32,
	h: i32,
	refresh_rate: i32,
}


main :: proc() {
	assert(sdl2.Init({.VIDEO}) == 0, sdl2.GetErrorString())
	defer sdl2.Quit()

	win := WindowSettings {
		w = 640,
		h = 480,
		refresh_rate = 60,
	}
	target_dt: f64 = 1000 / f64(win.refresh_rate)

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
			ctx := &mu_ctx
			#partial switch event.type {
			case .QUIT:
				break game_loop
			case .MOUSEMOTION:
				mu.input_mouse_move(ctx, event.motion.x, event.motion.y)
			case .MOUSEWHEEL:
				mu.input_scroll(ctx, event.wheel.x * 30, event.wheel.y * 30)
			case .MOUSEBUTTONDOWN, .MOUSEBUTTONUP:
				fn := mu.input_mouse_down if event.type == .MOUSEBUTTONDOWN else mu.input_mouse_up
				switch event.button.button {
				case sdl2.BUTTON_LEFT:
					fn(ctx, event.button.x, event.button.y, .LEFT)
				case sdl2.BUTTON_MIDDLE:
					fn(ctx, event.button.x, event.button.y, .MIDDLE)
				case sdl2.BUTTON_RIGHT:
					fn(ctx, event.button.x, event.button.y, .RIGHT)
				}
			case .KEYDOWN, .KEYUP:
				if event.type == .KEYUP && event.key.keysym.sym == .ESCAPE {
					sdl2.PushEvent(&sdl2.Event{type = .QUIT})
				}
				fn := mu.input_key_down if event.type == .KEYDOWN else mu.input_key_up

				#partial switch event.key.keysym.sym {
				case .LSHIFT:
					fn(ctx, .SHIFT)
				case .RSHIFT:
					fn(ctx, .SHIFT)
				case .LCTRL:
					fn(ctx, .CTRL)
				case .RCTRL:
					fn(ctx, .CTRL)
				case .LALT:
					fn(ctx, .ALT)
				case .RALT:
					fn(ctx, .ALT)
				case .RETURN:
					fn(ctx, .RETURN)
				case .KP_ENTER:
					fn(ctx, .RETURN)
				case .BACKSPACE:
					fn(ctx, .BACKSPACE)
				}
			}
		}

		mu.begin(&mu_ctx)
		mu_update(&mu_ctx)
		mu.end(&mu_ctx)

		render(&mu_ctx, renderer, atlas_texture)

		free_all(context.temp_allocator)
		end = get_time()
		to_sleep := time.Duration((target_dt - (end - start)) * f64(time.Millisecond))
		time.accurate_sleep(to_sleep)
	}
}

get_time :: proc() -> f64 {
	return f64(sdl2.GetPerformanceCounter()) * 1000 / f64(sdl2.GetPerformanceFrequency())
}

mu_update :: proc(ctx: ^mu.Context) {
	@(static)
	opts := mu.Options{.NO_CLOSE, .NO_TITLE, .NO_RESIZE, .ALIGN_CENTER}
	if mu.window(ctx, "Launcher", {0, 0, win.w, win.h}, opts) {
		mu.layout_row(ctx, {-1})
		if .SUBMIT in mu.button(ctx, "Dynamic Text") {
			launch()
		}
	}
}

_r :: #force_inline proc(r: mu.Rect) -> sdl2.Rect {
	return sdl2.Rect{r.x, r.y, r.w, r.h}
}

render_texture :: proc(
	renderer: ^sdl2.Renderer,
	atlas_texture: ^sdl2.Texture,
	src: mu.Rect,
	dst: ^sdl2.Rect,
	color: mu.Color,
) {
	dst.w = src.w
	dst.h = src.h
	sdl2.SetTextureAlphaMod(atlas_texture, color.a)
	sdl2.SetTextureColorMod(atlas_texture, color.r, color.g, color.b)
	r := _r(src)
	sdl2.RenderCopy(renderer, atlas_texture, &r, dst)
}

render :: proc(ctx: ^mu.Context, renderer: ^sdl2.Renderer, atlas_texture: ^sdl2.Texture) {
	viewport_rect := sdl2.Rect{}
	sdl2.GetRendererOutputSize(renderer, &viewport_rect.w, &viewport_rect.h)
	sdl2.RenderSetViewport(renderer, &viewport_rect)
	sdl2.RenderSetClipRect(renderer, &viewport_rect)
	sdl2.SetRenderDrawColor(renderer, 5, 10, 45, 255)
	sdl2.RenderClear(renderer)

	command_backing: ^mu.Command
	for varient in mu.next_command_iterator(ctx, &command_backing) {
		switch cmd in varient {
		case ^mu.Command_Text:
			dst := sdl2.Rect{cmd.pos.x, cmd.pos.y, 0, 0}
			for ch in cmd.str do if ch & 0xc0 != 0x80 {
					r := min(int(ch), 127)
					src := mu.default_atlas[mu.DEFAULT_ATLAS_FONT + r]
					render_texture(renderer, atlas_texture, src, &dst, cmd.color)
					dst.x += dst.w
				}
		case ^mu.Command_Rect:
			sdl2.SetRenderDrawColor(renderer, cmd.color.r, cmd.color.g, cmd.color.b, cmd.color.a)
			r := _r(cmd.rect)
			sdl2.RenderFillRect(renderer, &r)
		case ^mu.Command_Icon:
			src := mu.default_atlas[cmd.id]
			x := cmd.rect.x + (cmd.rect.w - src.w) / 2
			y := cmd.rect.y + (cmd.rect.h - src.h) / 2
			render_texture(renderer, atlas_texture, src, &sdl2.Rect{x, y, 0, 0}, cmd.color)
		case ^mu.Command_Clip:
			r := _r(cmd.rect)
			sdl2.RenderSetClipRect(renderer, &r)
		case ^mu.Command_Jump:
			unreachable()
		}
	}
	sdl2.RenderPresent(renderer)
}

launch :: proc() {
	win := WindowSettings {
		w = 1200,
		h = 800,
	}
	window := sdl2.CreateWindow(
		"Dynamic Text",
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

	dynamic_text.run(win.w, win.h, renderer, 60)

	// discard any events from the launched window
	event: sdl2.Event
	for sdl2.PollEvent(&event) do continue
}
