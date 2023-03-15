package launcher

import "core:mem"
import "core:fmt"
import "core:math"
import "core:time"
import "vendor:sdl2"
import mu "vendor:microui"

import "dynamic_text"

WindowSettings :: struct {
	w:            i32,
	h:            i32,
	refresh_rate: i32,
}

UiDisplay :: struct {
	index:     i32,
	checked:   bool,
	label_buf: [1]u8, // for example '0'
}

// Get label as string without allocating
ui_display_label :: proc(ui_display: ^UiDisplay) -> string {
	return fmt.bprintf(ui_display.label_buf[:], "%d", ui_display.index)
}

UiRes :: struct {
	w:         i32,
	h:         i32,
	checked:   bool,
	label_buf: [9]u8, // for example 1920x1880
}

// Get label as string without allocating
ui_res_label :: proc(ui_res: ^UiRes) -> string {
	return fmt.bprintf(ui_res.label_buf[:], "%dx%d", ui_res.w, ui_res.h)
}

UiResOptions :: struct {
	display_index: i32,
	sel:           i32,
	values:        [dynamic]UiRes,
	prev_checked:  [dynamic]bool,
}

create_ui_res_options :: proc(display_index: i32) -> UiResOptions {
	display_mode_count := get_display_mode_count(display_index)
	values := make([dynamic]UiRes, 0, 32)
	ui_res_prev_checked := make([dynamic]bool, 0, 32)
	mode: sdl2.DisplayMode
	for i: i32 = 0; i < display_mode_count; i += 1 {
		last_w: i32 = 0
		last_h: i32 = 0
		if len(values) > 0 {
			res_i := len(values) - 1
			last_w = values[res_i].w
			last_h = values[res_i].h
		}
		err := sdl2.GetDisplayMode(display_index, i, &mode)
		if err != 0 {
			fmt.printf(
				"GetDisplayMode(%d, %d, &mode) failed %s",
				display_index,
				i,
				sdl2.GetErrorString(),
			)
			continue
		}
		if last_h != mode.h && last_w != mode.w {
			append(&values, UiRes{w = mode.w, h = mode.h, checked = false})
			append(&ui_res_prev_checked, false)
		}
	}
	if len(ui_res_prev_checked) > 0 {
		ui_res_prev_checked[0] = true
	}
	return UiResOptions{display_index, 0, values, ui_res_prev_checked}
}

change_display_ui_res_options :: proc(opts: ^UiResOptions, new_display_index: i32) {
	opts.display_index = new_display_index
	opts.sel = 0
	clear_dynamic_array(&opts.values)
	clear_dynamic_array(&opts.prev_checked)
	display_mode_count := get_display_mode_count(new_display_index)
	mode: sdl2.DisplayMode
	for i: i32 = 0; i < display_mode_count; i += 1 {
		last_w: i32 = 0
		last_h: i32 = 0
		if i > 0 {
			res_i := len(opts.values) - 1
			last_w = opts.values[res_i].w
			last_h = opts.values[res_i].h
		}
		err := sdl2.GetDisplayMode(new_display_index, i, &mode)
		if err != 0 {
			fmt.printf(
				"GetDisplayMode(%d, %d, &mode) failed %s",
				new_display_index,
				i,
				sdl2.GetErrorString(),
			)
			continue
		}
		if last_h != mode.h && last_w != mode.w {
			checked := i == 0
			append(&opts.values, UiRes{w = mode.w, h = mode.h, checked = checked})
			append(&opts.prev_checked, checked)
		}
	}
}

update_ui_res_options :: proc(opts: ^UiResOptions) {
	prev_idx: i32 = opts.sel
	new_idx: i32 = prev_idx
	for prev, i in opts.prev_checked {
		new := opts.values[i].checked
		if new != prev {
			fmt.printf("UiRes checkbox %d edited: %t->%t\n", i, prev, new)
			if new {
				new_idx = i32(i)
			}
		}
	}
	for _, i in opts.prev_checked {
		checked := i32(i) == new_idx
		opts.values[i].checked = checked
		opts.prev_checked[i] = checked
	}
	opts.sel = new_idx
}

destroy_ui_res_options :: proc(opts: ^UiResOptions) {
	delete(opts.values)
	delete(opts.prev_checked)
}

State :: struct {
	display_count:          i32,
	selected_display_index: i32,
	ui_displays:            [dynamic]UiDisplay,
	ui_res_options:         ^UiResOptions,
}


_main :: proc() {
	assert(sdl2.Init({.VIDEO}) == 0, sdl2.GetErrorString())
	defer sdl2.Quit()

	// log_display_modes()

	display_count := sdl2.GetNumVideoDisplays()
	ui_displays := make([dynamic]UiDisplay, display_count, display_count)
	defer delete(ui_displays)
	prev_checked := make([dynamic]bool, display_count, display_count)
	defer delete(prev_checked)
	for i: i32 = 0; i < display_count; i += 1 {
		ui_displays[i].index = i
		checked := i == 0
		ui_displays[i].checked = checked
		prev_checked[i] = checked
	}
	display_index: i32 = 0
	ui_res_options := create_ui_res_options(display_index)
	defer destroy_ui_res_options(&ui_res_options)

	state := State{display_count, display_index, ui_displays, &ui_res_options}
	// TODO: properly free state (not really needed since by then the program
	//       is exiting, but it would be a good learning exercise)
	// state := create_state(display_count)
	// defer free_state(state)

	win := WindowSettings {
		w            = 640,
		h            = 480,
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
	defer delete(pixels)
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

		// resolve checkbox arrays
		{
			prev_sel: i32 = state.selected_display_index
			new_sel: i32 = prev_sel
			for prev, i in prev_checked {
				new := state.ui_displays[i].checked
				if new != prev {
					fmt.printf("checkbox %d changed from %t to %t\n", i, prev, new)
					if new {
						new_sel = i32(i)
						change_display_ui_res_options(state.ui_res_options, new_sel)
					}
				}
			}
			for _, i in prev_checked {
				checked := i32(i) == new_sel
				state.ui_displays[i].checked = checked
				prev_checked[i] = checked
			}
			state.selected_display_index = new_sel
		}
		update_ui_res_options(state.ui_res_options)

		mu.begin(&mu_ctx)
		mu_update(&mu_ctx, &win, &state)
		mu.end(&mu_ctx)

		render(&mu_ctx, renderer, atlas_texture)

		free_all(context.temp_allocator)
		end = get_time()
		to_sleep := time.Duration((target_dt - (end - start)) * f64(time.Millisecond))
		time.accurate_sleep(to_sleep)
	}
}

main :: proc() {
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
}

get_time :: proc() -> f64 {
	return f64(sdl2.GetPerformanceCounter()) * 1000 / f64(sdl2.GetPerformanceFrequency())
}

mu_update :: proc(ctx: ^mu.Context, win: ^WindowSettings, state: ^State) {
	@(static)
	opts := mu.Options{.NO_CLOSE, .NO_TITLE, .NO_RESIZE, .ALIGN_CENTER}
	if mu.window(ctx, "Launcher", {0, 0, win.w, win.h}, opts) {
		mu.layout_row(ctx, {-1})
		if .SUBMIT in mu.button(ctx, "Dynamic Text") {
			launch()
		}
		mu.layout_row(ctx, {75, 40, 40, 40, 40})
		mu.label(ctx, "Displays:")
		for _, i in state.ui_displays {
			mu.checkbox(
				ctx,
				ui_display_label(&state.ui_displays[i]),
				&state.ui_displays[i].checked,
			)
		}
		mu.layout_row(ctx, {75, 85, 85, 85, 85, 85})
		mu.label(ctx, "Resolution:")
		for _, i in state.ui_res_options.values {
			if i % 5 == 0 && i != 0 {
				mu.layout_row(ctx, {75, 85, 85, 85, 85, 85})
				mu.label(ctx, "")
			}
			mu.checkbox(
				ctx,
				ui_res_label(&state.ui_res_options.values[i]),
				&state.ui_res_options.values[i].checked,
			)
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

get_display_mode_count :: proc(index: i32) -> i32 {
	display_mode_count := sdl2.GetNumDisplayModes(index)
	if display_mode_count < 1 {
		fmt.eprintln("Display mode count:", display_mode_count)
		return 0
	}
	return display_mode_count
}

log_display_modes :: proc() {
	display_count := sdl2.GetNumVideoDisplays()
	fmt.println("Display count:", display_count)
	for display_index: i32 = 0; display_index < display_count; display_index += 1 {
		display_mode_count := get_display_mode_count(display_index)
		fmt.printf("%d: %d\n", display_index, display_mode_count)
		if display_mode_count < 1 {
			continue
		}
		for i: i32 = 0; i < display_mode_count; i += 1 {
			mode: sdl2.DisplayMode
			err := sdl2.GetDisplayMode(display_index, i, &mode)
			if err != 0 {
				fmt.printf(
					"GetDisplayMode(%d, %d, &mode) failed %s",
					display_index,
					i,
					sdl2.GetErrorString(),
				)
				continue
			}
			f := mode.format
			fmt.printf(
				"Mode: %2d %d format: %s %4dx%4d refresh: %d\n",
				i,
				f,
				sdl2.GetPixelFormatName(f),
				mode.w,
				mode.h,
				mode.refresh_rate,
			)
		}
	}
}
