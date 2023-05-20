/* Text rendering following learnopengl tutorial

https://learnopengl.com/In-Practice/Text-Rendering

*/
package opengl_text

import "core:c"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:time"
import "core:math"
import glm "core:math/linalg/glsl"

import "vendor:sdl2"
import gl "vendor:OpenGL"
import tt "vendor:stb/truetype"
import "vendor:stb/image"


TERMINAL_TTF :: "dynamic_text/fonts/Terminal.ttf"


Game :: struct {
	window_width:  int,
	window_height: int,
}

run :: proc(window: ^sdl2.Window, window_width, window_height, refresh_rate: i32) {
	game := Game{int(window_width), int(window_height)}

	sdl2.GL_SetAttribute(.CONTEXT_PROFILE_MASK, i32(sdl2.GLprofile.CORE))
	sdl2.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 3)
	sdl2.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 3)
	gl_context := sdl2.GL_CreateContext(window)
	defer sdl2.GL_DeleteContext(gl_context)
	gl.load_up_to(3, 3, sdl2.gl_set_proc_address)

	// truetype stuff
	{
		// for temp test, write to out.png file
		// this code was addapted from example by Justin Meiners (MIT)
		// https://github.com/justinmeiners/stb-truetype-example/blob/master/main.c
		data, ok := os.read_entire_file_from_filename(TERMINAL_TTF)
		assert(ok)
		defer delete(data)

		info: tt.fontinfo
		ok = cast(bool)tt.InitFont(&info, &data[0], 0)
		assert(ok)
		b_w: int = 800
		b_h: int = 128
		l_h: int = 64
		bitmap: []byte = make([]byte, b_w * b_h)
		defer delete(bitmap)
		scale := tt.ScaleForPixelHeight(&info, f32(l_h))
		word := "the quick brown fox"
		ascent: i32
		descent: i32
		lineGap: i32
		tt.GetFontVMetrics(&info, &ascent, &descent, &lineGap)
		ascent = cast(i32)math.round(f32(ascent) * scale)
		descent = cast(i32)math.round(f32(descent) * scale)
		x: i32
		for letter, i in word {
			// char width
			ax: i32
			lsb: i32
			tt.GetCodepointHMetrics(&info, letter, &ax, &lsb)

			// get bounding box for char
			c_x1, c_y1, c_x2, c_y2: c.int
			tt.GetCodepointBitmapBox(&info, letter, scale, scale, &c_x1, &c_y1, &c_x2, &c_y2)

			y: i32 = ascent + c_y1

			// render character
			byte_offset: i32 = x + cast(i32)math.round(f32(lsb) * scale) + (y * i32(b_w))
			tt.MakeCodepointBitmap(
				&info,
				&bitmap[byte_offset],
				c_x2 - c_x1,
				c_y2 - c_y1,
				i32(b_w),
				scale,
				scale,
				letter,
			)
			x += cast(i32)math.round(f32(ax) * scale)

			if i < len(word) - 1 {
				kern: i32
				kern = tt.GetCodepointKernAdvance(&info, letter, cast(rune)word[i + 1])
				x += cast(i32)math.round(f32(kern) * scale)
			}
		}

		// save out 1 channel image
		image.write_png("out.png", i32(b_w), i32(b_h), 1, raw_data(bitmap), i32(b_w))
	}


	projection: glm.mat4 = glm.mat4Ortho3d(0, f32(window_width), f32(window_height), 0, -1.0, 1)

	// timing stuff
	fps: f64 = 0
	target_ms_elapsed: f64 = 1000 / f64(refresh_rate)
	ms_elapsed: f64 = target_ms_elapsed
	target_dt: f64 = (1000 / f64(refresh_rate)) / 1000
	dt := f32(ms_elapsed / 1000)

	// game loop
	game_loop: for {
		start_tick := time.tick_now()
		dt = f32(ms_elapsed / 1000)

		// process input
		event: sdl2.Event
		for sdl2.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				break game_loop
			case .KEYUP:
				if event.key.keysym.sym == .ESCAPE {
					sdl2.PushEvent(&sdl2.Event{type = .QUIT})
				}
			}
		}

		// render
		gl.Viewport(0, 0, window_width, window_height)
		gl.ClearColor(0.007843, 0.02353, 0.02745, 1)
		gl.Clear(gl.COLOR_BUFFER_BIT)

		gl_report_error()
		sdl2.GL_SwapWindow(window)

		// timing (avoid looping too fast)
		duration := time.tick_since(start_tick)
		tgt_duration := time.Duration(target_ms_elapsed * f64(time.Millisecond))
		to_sleep := tgt_duration - duration
		time.accurate_sleep(to_sleep - (2 * time.Microsecond))
		duration = time.tick_since(start_tick)
		ms_elapsed = f64(time.duration_milliseconds(duration))
		fps = 1000 / ms_elapsed
	}
}


_main :: proc(display_index: i32) {
	assert(sdl2.Init({.VIDEO}) == 0, sdl2.GetErrorString())
	defer sdl2.Quit()

	display_mode: sdl2.DisplayMode
	sdl2.GetCurrentDisplayMode(display_index, &display_mode)
	refresh_rate := display_mode.refresh_rate

	window_width: i32 = 1280
	window_height: i32 = 960

	window := sdl2.CreateWindow(
		"OpenGL Text Rendering",
		sdl2.WINDOWPOS_UNDEFINED_DISPLAY(display_index),
		sdl2.WINDOWPOS_UNDEFINED_DISPLAY(display_index),
		window_width,
		window_height,
		{.OPENGL},
	)
	assert(window != nil, sdl2.GetErrorString())
	defer sdl2.DestroyWindow(window)

	fmt.printf("%dx%d %d\n", window_width, window_height, refresh_rate)

	run(window, window_width, window_height, refresh_rate)
}


main :: proc() {
	args := os.args[1:]
	display_index: i32 = 0
	if slice.contains(args, "-1") {
		// open window on second monitor
		display_index = 1
	}
	if slice.contains(args, "-m") || slice.contains(args, "--mem-track") {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		_main(display_index)

		for _, leak in track.allocation_map {
			fmt.printf("%v leaked %v bytes\n", leak.location, leak.size)
		}
		for bad_free in track.bad_free_array {
			fmt.printf("%v allocation %p was freed badly\n", bad_free.location, bad_free.memory)
		}
	} else {
		_main(display_index)
	}
}

gl_report_error :: proc() {
	e := gl.GetError()
	if e != gl.NO_ERROR {
		fmt.println("OpenGL Error:", e)
	}
}

// Useful for spawning particles at mouse position for testing
get_mouse_pos :: proc(window_width, window_height: i32) -> [2]f32 {
	cx, cy: c.int
	sdl2.GetMouseState(&cx, &cy)
	return {f32(cx), f32(cy)}
}
