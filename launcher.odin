package launcher

import "core:c"
import "core:mem"
import "core:fmt"
import "core:math"
import "core:time"
import "vendor:sdl2"
import mu "vendor:microui"

import "dynamic_text"
import "shader"
import "triangulation"

when ODIN_OS == .Windows {
	import win32 "core:sys/windows"
}

rect_overlap_area :: proc(a, b: ^sdl2.Rect) -> int {
	if sdl2.HasIntersection(a, b) {
		result: sdl2.Rect
		sdl2.IntersectRect(a, b, &result)
		return int(result.w * result.h)
	}
	return 0
}

get_active_display_index :: proc() -> c.int {
	mf_win := sdl2.GetMouseFocus()
	fmt.println("mouse focus:", mf_win)
	kf_win := sdl2.GetKeyboardFocus()
	fmt.println("keyboard focus:", kf_win)
	// These are both <nil> :(

	foreground_rect_found := false
	foreground_rect: sdl2.Rect
	when ODIN_OS == .Windows {
		fmt.println("running on windows")
		rect: win32.RECT
		handle := win32.GetForegroundWindow()
		err := win32.GetWindowRect(handle, &rect)
		fmt.println("handle:", handle, "rect:", rect, "error:", err)
		if err {
			// It errors with 6 (The handle is invalid), but the rect gets the
			// right values, so it seems to have worked?
			fmt.println("Error getting window rect", win32.GetLastError())
		}
		foreground_rect_found = true
		foreground_rect.x = rect.left
		foreground_rect.y = rect.top
		foreground_rect.w = rect.right - rect.left
		foreground_rect.h = rect.bottom - rect.top
	}
	if !foreground_rect_found {
		return 0
	}
	fmt.println("foreground rect:", foreground_rect)

	// Check which display contains the window with focus
	display_count := sdl2.GetNumVideoDisplays()
	active: c.int = 0
	max_overlap := 0
	for i: c.int = 0; i < display_count; i += 1 {
		rect: sdl2.Rect
		err := sdl2.GetDisplayBounds(i, &rect)
		if err != 0 do continue
		fmt.println(i, rect)
		overlap_area := rect_overlap_area(&rect, &foreground_rect)
		fmt.printf("monitor %d has overlap of %d\n", i, overlap_area)
		if overlap_area > max_overlap {
			active = i
			max_overlap = overlap_area
		}
	}
	return active
}


WindowSettings :: struct {
	w:             i32,
	h:             i32,
	refresh_rate:  i32,
	display_index: i32,
}

window_settings_get_matching_display_mode :: proc(
	win: WindowSettings,
	mode: ^sdl2.DisplayMode,
) -> bool {
	display_mode_count := get_display_mode_count(win.display_index)
	for i: i32 = 0; i < display_mode_count; i += 1 {
		err := sdl2.GetDisplayMode(win.display_index, i, mode)
		if err != 0 {
			fmt.println("sdl2.GetDisplayMode error:", err)
			continue
		}
		if mode.w == win.w && mode.h == win.h && mode.refresh_rate == win.refresh_rate {
			return true
		}
	}
	return false
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

UiDisplayOptions :: struct {
	sel:          i32,
	values:       [dynamic]UiDisplay,
	prev_checked: [dynamic]bool,
}

init_ui_display_options :: proc(opts: ^UiDisplayOptions, display_count: i32) {
	opts.sel = 0
	reserve_dynamic_array(&opts.values, int(display_count))
	reserve_dynamic_array(&opts.prev_checked, int(display_count))
	for i: i32 = 0; i < display_count; i += 1 {
		checked := i == 0
		append(&opts.values, UiDisplay{index = i, checked = checked})
		append(&opts.prev_checked, checked)
	}
}

destroy_ui_display_options :: proc(opts: ^UiDisplayOptions) {
	delete(opts.values)
	delete(opts.prev_checked)
}

update_ui_display_options :: proc(opts: ^UiDisplayOptions) -> (i32, bool) {
	// resolve checkbox arrays
	updated := false
	prev_sel: i32 = opts.sel
	new_sel: i32 = prev_sel
	for prev, i in opts.prev_checked {
		new := opts.values[i].checked
		if new != prev {
			fmt.printf("checkbox %d changed from %t to %t\n", i, prev, new)
			if new {
				new_sel = i32(i)
				updated = true
			}
		}
	}
	for _, i in opts.prev_checked {
		checked := i32(i) == new_sel
		opts.values[i].checked = checked
		opts.prev_checked[i] = checked
	}
	opts.sel = new_sel
	return new_sel, updated
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

init_ui_res_options :: proc(opts: ^UiResOptions, display_index: i32) {
	opts.sel = 0
	display_mode_count := get_display_mode_count(display_index)
	reserve_dynamic_array(&opts.values, 32)
	reserve_dynamic_array(&opts.prev_checked, 32)
	mode: sdl2.DisplayMode
	for i: i32 = 0; i < display_mode_count; i += 1 {
		last_w: i32 = 0
		last_h: i32 = 0
		if len(opts.values) > 0 {
			res_i := len(opts.values) - 1
			last_w = opts.values[res_i].w
			last_h = opts.values[res_i].h
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
			append(&opts.values, UiRes{w = mode.w, h = mode.h, checked = false})
			append(&opts.prev_checked, false)
		}
	}
	if len(&opts.prev_checked) > 0 {
		opts.prev_checked[0] = true
	}
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

update_ui_res_options :: proc(opts: ^UiResOptions) -> (UiRes, bool) {
	changed := false
	prev_idx: i32 = opts.sel
	new_idx: i32 = prev_idx
	for prev, i in opts.prev_checked {
		new := opts.values[i].checked
		if new != prev {
			fmt.printf("UiRes checkbox %d edited: %t->%t\n", i, prev, new)
			if new {
				new_idx = i32(i)
				changed = true
			}
		}
	}
	for _, i in opts.prev_checked {
		checked := i32(i) == new_idx
		opts.values[i].checked = checked
		opts.prev_checked[i] = checked
	}
	opts.sel = new_idx
	return opts.values[opts.sel], changed
}

destroy_ui_res_options :: proc(opts: ^UiResOptions) {
	delete(opts.values)
	delete(opts.prev_checked)
}

UiRefresh :: struct {
	v:         i32,
	checked:   bool,
	label_buf: [3]u8, // for example '60'
}

// Get label as string without allocating
ui_refresh_label :: proc(ui_refresh: ^UiRefresh) -> string {
	return fmt.bprintf(ui_refresh.label_buf[:], "%d", ui_refresh.v)
}

UiRefreshOptions :: struct {
	sel:          int,
	values:       [dynamic]UiRefresh,
	prev_checked: [dynamic]bool,
}

init_ui_refresh_options :: proc(opts: ^UiRefreshOptions, display_index: i32, res: UiRes) {
	opts.sel = 0
	display_mode_count := get_display_mode_count(display_index)
	reserve_dynamic_array(&opts.values, 16)
	reserve_dynamic_array(&opts.prev_checked, 16)
	mode: sdl2.DisplayMode
	for i: i32 = 0; i < display_mode_count; i += 1 {
		err := sdl2.GetDisplayMode(display_index, i, &mode)
		if err != 0 {
			fmt.println("sdl2.GetDisplayMode error:", err)
			continue
		}
		if mode.w != res.w || mode.h != res.h {
			continue
		}

		first := len(opts.values) == 0
		last_refresh: i32 = -1
		if len(opts.values) > 0 {
			last_refresh = opts.values[len(opts.values) - 1].v
		}
		checked := first
		if last_refresh != mode.refresh_rate {
			append(&opts.values, UiRefresh{v = mode.refresh_rate, checked = checked})
			append(&opts.prev_checked, checked)
		}
	}
}

change_ui_refresh_options :: proc(opts: ^UiRefreshOptions, display_index: i32, res: UiRes) {
	opts.sel = 0
	clear_dynamic_array(&opts.values)
	clear_dynamic_array(&opts.prev_checked)
	display_mode_count := get_display_mode_count(display_index)
	mode: sdl2.DisplayMode
	for i: i32 = 0; i < display_mode_count; i += 1 {
		err := sdl2.GetDisplayMode(display_index, i, &mode)
		if err != 0 {
			continue
		}
		if mode.w != res.w || mode.h != res.h {
			continue
		}

		first := len(opts.values) == 0
		last_refresh: i32 = -1
		if len(opts.values) > 0 {
			last_refresh = opts.values[len(opts.values) - 1].v
		}
		checked := first
		if last_refresh != mode.refresh_rate {
			append(&opts.values, UiRefresh{v = mode.refresh_rate, checked = checked})
			append(&opts.prev_checked, checked)
		}
	}
}

update_ui_refresh_options :: proc(opts: ^UiRefreshOptions) {
	prev_idx: int = opts.sel
	new_idx: int = prev_idx
	for prev, i in opts.prev_checked {
		new := opts.values[i].checked
		if new != prev {
			fmt.printf("UiRefresh checkbox %d edited %t-> %t\n", i, prev, new)
			if new {
				new_idx = i
			}
		}
	}
	for _, i in opts.prev_checked {
		checked := i == new_idx
		opts.values[i].checked = checked
		opts.prev_checked[i] = checked
	}
	opts.sel = new_idx
}

destroy_ui_refresh_options :: proc(opts: ^UiRefreshOptions) {
	delete(opts.values)
	delete(opts.prev_checked)
}

State :: struct {
	display_count:      i32,
	ui_display_options: UiDisplayOptions,
	ui_res_options:     UiResOptions,
	ui_refresh_options: UiRefreshOptions,
}

init_state :: proc(state: ^State, display_count: i32) {
	init_ui_display_options(&state.ui_display_options, display_count)
	init_ui_res_options(&state.ui_res_options, 0)
	ui_res := state.ui_res_options.values[state.ui_res_options.sel]
	init_ui_refresh_options(&state.ui_refresh_options, 0, ui_res)
}

destroy_state :: proc(state: ^State) {
	destroy_ui_display_options(&state.ui_display_options)
	destroy_ui_res_options(&state.ui_res_options)
	destroy_ui_refresh_options(&state.ui_refresh_options)
}

update_state :: proc(state: ^State) {
	new_display_index, changed1 := update_ui_display_options(&state.ui_display_options)
	if changed1 {
		change_display_ui_res_options(&state.ui_res_options, new_display_index)
	}
	new_ui_res, changed2 := update_ui_res_options(&state.ui_res_options)
	if changed1 || changed2 {
		change_ui_refresh_options(&state.ui_refresh_options, 0, new_ui_res)
	}
	update_ui_refresh_options(&state.ui_refresh_options)
}

state_get_launch_settings :: proc(state: ^State) -> WindowSettings {
	res := state.ui_res_options.values[state.ui_res_options.sel]
	refresh := state.ui_refresh_options.values[state.ui_refresh_options.sel]
	display_index := state.ui_display_options.sel
	return(
		WindowSettings{
			w = res.w,
			h = res.h,
			refresh_rate = refresh.v,
			display_index = display_index,
		} \
	)
}


_main :: proc() {
	assert(sdl2.Init({.VIDEO}) == 0, sdl2.GetErrorString())
	defer sdl2.Quit()

	// log_display_modes()

	display_count := sdl2.GetNumVideoDisplays()

	state := State{}
	init_state(&state, display_count)
	defer destroy_state(&state)

	win := WindowSettings {
		w            = 640,
		h            = 480,
		refresh_rate = 60,
	}
	target_dt: f64 = 1000 / f64(win.refresh_rate)

	active_display := get_active_display_index()

	window := sdl2.CreateWindow(
		"Laucher",
		sdl2.WINDOWPOS_UNDEFINED_DISPLAY(active_display),
		sdl2.WINDOWPOS_UNDEFINED_DISPLAY(active_display),
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

		update_state(&state)

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
			launch(state_get_launch_settings(state))
		}
		if .SUBMIT in mu.button(ctx, "Shader Test") {
			launch_shader(state_get_launch_settings(state))
		}
		if .SUBMIT in mu.button(ctx, "Triangulation") {
			launch_triangulation(state_get_launch_settings(state))
		}
		mu.layout_row(ctx, {75, 40, 40, 40, 40})
		mu.label(ctx, "Displays:")
		for _, i in state.ui_display_options.values {
			mu.checkbox(
				ctx,
				ui_display_label(&state.ui_display_options.values[i]),
				&state.ui_display_options.values[i].checked,
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
		mu.layout_row(ctx, {75, 85, 85, 85, 85, 85})
		mu.label(ctx, "Refresh Rate:")
		for _, i in state.ui_refresh_options.values {
			if i % 5 == 0 && i != 0 {
				mu.layout_row(ctx, {75, 85, 85, 85, 85, 85})
				mu.label(ctx, "")
			}
			mu.checkbox(
				ctx,
				ui_refresh_label(&state.ui_refresh_options.values[i]),
				&state.ui_refresh_options.values[i].checked,
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

launch :: proc(win: WindowSettings) {
	window := sdl2.CreateWindow(
		"Dynamic Text",
		sdl2.WINDOWPOS_UNDEFINED_DISPLAY(win.display_index),
		sdl2.WINDOWPOS_UNDEFINED_DISPLAY(win.display_index),
		win.w,
		win.h,
		{.SHOWN, .FULLSCREEN, .ALLOW_HIGHDPI},
	)
	assert(window != nil, sdl2.GetErrorString())
	defer sdl2.DestroyWindow(window)

	mode: sdl2.DisplayMode
	found := window_settings_get_matching_display_mode(win, &mode)
	err := sdl2.SetWindowDisplayMode(window, &mode)
	if err != 0 {
		fmt.println("Failed to set window display mode with err:", err)
	}

	renderer := sdl2.CreateRenderer(window, -1, sdl2.RENDERER_ACCELERATED)
	assert(renderer != nil, sdl2.GetErrorString())
	defer sdl2.DestroyRenderer(renderer)

	dynamic_text.run(win.w, win.h, renderer, win.refresh_rate)

	// discard any events from the launched window
	event: sdl2.Event
	for sdl2.PollEvent(&event) do continue
}

launch_shader :: proc(win: WindowSettings) {
	window := sdl2.CreateWindow(
		"Shader test",
		sdl2.WINDOWPOS_UNDEFINED_DISPLAY(win.display_index),
		sdl2.WINDOWPOS_UNDEFINED_DISPLAY(win.display_index),
		win.w,
		win.h,
		{.SHOWN, .FULLSCREEN, .ALLOW_HIGHDPI, .OPENGL},
	)
	assert(window != nil, sdl2.GetErrorString())
	defer sdl2.DestroyWindow(window)

	mode: sdl2.DisplayMode
	found := window_settings_get_matching_display_mode(win, &mode)
	err := sdl2.SetWindowDisplayMode(window, &mode)
	if err != 0 {
		fmt.println("Failed to set window display mode with err:", err)
	}

	// renderer := sdl2.CreateRenderer(window, -1, sdl2.RENDERER_ACCELERATED)
	// assert(renderer != nil, sdl2.GetErrorString())
	// defer sdl2.DestroyRenderer(renderer)

	shader.run(window, win.w, win.h, win.refresh_rate)

	// discard any events from the launched window
	event: sdl2.Event
	for sdl2.PollEvent(&event) do continue
}

launch_triangulation :: proc(win: WindowSettings) {
	window := sdl2.CreateWindow(
		"Delaunay Triangulation",
		sdl2.WINDOWPOS_UNDEFINED_DISPLAY(win.display_index),
		sdl2.WINDOWPOS_UNDEFINED_DISPLAY(win.display_index),
		win.w,
		win.h,
		{.OPENGL},
	)
	assert(window != nil, sdl2.GetErrorString())
	defer sdl2.DestroyWindow(window)

	fmt.printf("%dx%d %d\n", win.w, win.h, win.refresh_rate)

	triangulation.run(window, win.w, win.h, win.refresh_rate)

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
