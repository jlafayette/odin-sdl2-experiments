package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:time"
import "core:strings"

import "vendor:sdl2"
import mu "vendor:microui"

import "color"


SCREEN_WIDTH: i32 = 1280
SCREEN_HEIGHT: i32 = 960
TARGET_DT: f64 = 1000 / 60
perf_frequency: f64

Game :: struct {
	fps: f64,
}
game := Game{}


main :: proc() {
	debug := slice.contains(os.args[1:], "--debug")

	if debug {
		fmt.println("debug mode on, tracking memory allocations")
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		_main()

		for _, leak in track.allocation_map {
			fmt.printf("%v leaked %v bytes\n", leak.location, leak.size)
		}
		for bad_free in track.bad_free_array {
			fmt.printf("%v allocation %p was freed badly\n", bad_free.location, bad_free.memory)
		}
	} else {
		_main()
	}
}


_main :: proc() {

	assert(sdl2.Init({.VIDEO}) == 0, sdl2.GetErrorString())
	defer sdl2.Quit()

	window := sdl2.CreateWindow(
		"UI Example",
		sdl2.WINDOWPOS_UNDEFINED,
		sdl2.WINDOWPOS_UNDEFINED,
		SCREEN_WIDTH,
		SCREEN_HEIGHT,
		{.SHOWN, .RESIZABLE},
	)
	assert(window != nil, sdl2.GetErrorString())
	defer sdl2.DestroyWindow(window)

	// Init Renderer with OpenGL
	backend_index: i32 = -1
	driver_count := sdl2.GetNumRenderDrivers()
	if driver_count <= 0 {
		fmt.eprintln("No render drivers available")
		return
	}
	for i in 0 ..< driver_count {
		info: sdl2.RendererInfo
		if err := sdl2.GetRenderDriverInfo(i, &info); err == 0 {
			// fmt.println("found driver:", info.name)
			if info.name == "opengl" {
				backend_index = i
			}
		}
	}

	renderer := sdl2.CreateRenderer(window, backend_index, {.ACCELERATED, .PRESENTVSYNC})
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
	if err := sdl2.SetTextureBlendMode(atlas_texture, .BLEND); err != 0 {
		fmt.eprintln("sdl2.SetTextureBlendMode: ", sdl2.GetErrorString())
		return
	}
	pixels := make([][4]u8, mu.DEFAULT_ATLAS_WIDTH * mu.DEFAULT_ATLAS_HEIGHT)
	defer delete(pixels)
	for alpha, i in mu.default_atlas_alpha {
		pixels[i].rgb = 0xff
		pixels[i].a = alpha
	}
	if err := sdl2.UpdateTexture(atlas_texture, nil, raw_data(pixels), 4 * mu.DEFAULT_ATLAS_WIDTH);
	   err != 0 {
		fmt.eprintln("sdl2.UpdateTexture: ", sdl2.GetErrorString())
		return
	}
	mu_ctx: mu.Context
	mu.init(&mu_ctx)

	mu_ctx.text_width = mu.default_atlas_text_width
	mu_ctx.text_height = mu.default_atlas_text_height

	perf_frequency = f64(sdl2.GetPerformanceFrequency())
	start: f64
	end: f64

	// Background color in HSV space
	bg := [3]f32{180, 0.5, 0.5}

	game_loop: for {
		start = get_time()
		// Update
		// Handle input events
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

		// Render
		// Draw UI stuff here
		mu.begin(&mu_ctx)
		mu_update(&mu_ctx, &bg)
		mu.end(&mu_ctx)

		// Timing (avoid looping too fast)
		end = get_time()
		to_sleep := time.Duration((TARGET_DT - (end - start)) * f64(time.Millisecond))
		time.accurate_sleep(to_sleep)
		end = get_time()
		game.fps = 1000 / (end - start)

		c1 := color.hsv_to_rgb(bg)
		c := color.to_u8(c1)
		render(&mu_ctx, renderer, atlas_texture, {c.r, c.g, c.b, 255})

		free_all(context.temp_allocator)
	}
}


get_time :: proc() -> f64 {
	return f64(sdl2.GetPerformanceCounter()) * 1000 / perf_frequency
}


STEP: f32 = 1 / 255

mu_update :: proc(ctx: ^mu.Context, bg: ^[3]f32) {
	@(static)
	opts := mu.Options{}

	if mu.window(ctx, "Demo Window", {40, 40, 300, 450}, opts) {
		mu.layout_row(ctx, {60, -1})
		mu.label(ctx, "First:")
		if .SUBMIT in mu.button(ctx, "Button1") {
			fmt.println("Button1 pressed")
		}
		mu.label(ctx, "Second:")
		if .SUBMIT in mu.button(ctx, "Button2") {
			fmt.println("Button2 pressed")
			mu.open_popup(ctx, "My Popup")
		}
		if mu.popup(ctx, "My Popup") {
			mu.label(ctx, "Hello!")
		}

		mu.layout_row(ctx, {-1})
		mu.slider(ctx, &bg.r, 0, 360, 1)
		mu.slider(ctx, &bg.g, 0, 1, STEP)
		mu.slider(ctx, &bg.b, 0, 1, STEP)
	}
}

mu2sdl_rect :: #force_inline proc(r: mu.Rect) -> sdl2.Rect {
	return sdl2.Rect{r.x, r.y, r.w, r.h}
}

render :: proc(
	ctx: ^mu.Context,
	renderer: ^sdl2.Renderer,
	atlas_texture: ^sdl2.Texture,
	bg: mu.Color,
) {
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
		r := mu2sdl_rect(src)
		sdl2.RenderCopy(renderer, atlas_texture, &r, dst)
	}
	viewport_rect := sdl2.Rect{}
	sdl2.GetRendererOutputSize(renderer, &viewport_rect.w, &viewport_rect.h)
	sdl2.RenderSetViewport(renderer, &viewport_rect)
	sdl2.RenderSetClipRect(renderer, &viewport_rect)
	sdl2.SetRenderDrawColor(renderer, bg.r, bg.g, bg.b, bg.a)
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
			r := mu2sdl_rect(cmd.rect)
			sdl2.RenderFillRect(renderer, &r)
		case ^mu.Command_Icon:
			src := mu.default_atlas[cmd.id]
			x := cmd.rect.x + (cmd.rect.w - src.w) / 2
			y := cmd.rect.y + (cmd.rect.h - src.h) / 2
			render_texture(renderer, atlas_texture, src, &sdl2.Rect{x, y, 0, 0}, cmd.color)
		case ^mu.Command_Clip:
			r := mu2sdl_rect(cmd.rect)
			sdl2.RenderSetClipRect(renderer, &r)
		case ^mu.Command_Jump:
			unreachable()
		}
	}
	sdl2.RenderPresent(renderer)
}
