package main

import "core:fmt"
import "core:time"
import "core:strings"

import "vendor:sdl2"
import "vendor:sdl2/ttf"

import "text"


SCREEN_WIDTH: i32 = 1280
SCREEN_HEIGHT: i32 = 960
TARGET_DT: f64 = 1000 / 60
perf_frequency: f64

Game :: struct {
	fps:             f64,
	text_input:      string,
	text_size_index: int,
}
game := Game {
	text_input      = "Try typing something... ",
	text_size_index = 3,
}

main :: proc() {

	assert(sdl2.Init(sdl2.INIT_VIDEO) == 0, sdl2.GetErrorString())
	defer sdl2.Quit()

	window := sdl2.CreateWindow(
		"Example Game",
		sdl2.WINDOWPOS_UNDEFINED,
		sdl2.WINDOWPOS_UNDEFINED,
		SCREEN_WIDTH,
		SCREEN_HEIGHT,
		sdl2.WINDOW_SHOWN,
	)
	assert(window != nil, sdl2.GetErrorString())
	defer sdl2.DestroyWindow(window)

	renderer := sdl2.CreateRenderer(window, -1, sdl2.RENDERER_ACCELERATED)
	assert(renderer != nil, sdl2.GetErrorString())
	defer sdl2.DestroyRenderer(renderer)

	ttf_init_result := ttf.Init()
	assert(ttf_init_result == 0, sdl2.GetErrorString())
	defer ttf.Quit()

	debug_text_drawer := text.create_drawer(true, 12, renderer)
	assert(debug_text_drawer != nil, "error creating text.Drawer")
	defer text.destroy_drawer(debug_text_drawer)

	text_sizes := [7]i32{12, 18, 24, 36, 48, 60, 72}
	text_drawers: [7]^text.Drawer
	for i in 0 ..< len(text_drawers) {
		text_drawer := text.create_drawer(true, text_sizes[i], renderer)
		assert(text_drawer != nil, "error creating text.Drawer")
		text_drawers[i] = text_drawer
	}
	defer {
		for i in 0 ..< len(text_drawers) {
			text.destroy_drawer(text_drawers[i])
		}
	}

	perf_frequency = f64(sdl2.GetPerformanceFrequency())
	start: f64
	end: f64

	event: sdl2.Event

	game_loop: for {
		start = get_time()
		// Update
		// Handle input events
		for sdl2.PollEvent(&event) {
			if handle_exit(&event) {break game_loop}
			game.text_input = handle_key_press(&event, game.text_input)
			{
				new_index := handle_change_text_size(&event, game.text_size_index)
				index := clamp(new_index, 0, len(text_sizes) - 1)
				game.text_size_index = index
			}
		}

		// Render
		// draw fps
		fps_str := fmt.tprintf("FPS: %f", game.fps)
		text.draw(debug_text_drawer, &fps_str, text.Pos{10, 10})
		// draw text input
		// scale: f64 = f64(text_sizes[game.text_size_index]) / 100
		text.draw(
			text_drawers[game.text_size_index],
			&game.text_input,
			text.Pos{100, 100},
			SCREEN_WIDTH - 200,
		)

		// Timing (avoid looping too fast)
		end = get_time()
		to_sleep := time.Duration((TARGET_DT - (end - start)) * f64(time.Millisecond))
		time.accurate_sleep(to_sleep)
		end = get_time()
		game.fps = 1000 / (end - start)

		sdl2.RenderPresent(renderer)
		sdl2.SetRenderDrawColor(renderer, 0, 0, 0, 100)
		sdl2.RenderClear(renderer)

		free_all(context.temp_allocator)
	}
}

handle_exit :: proc(event: ^sdl2.Event) -> bool {
	#partial switch event.type {
	case .QUIT:
		return true
	case .KEYDOWN:
		return event.key.keysym.scancode == .ESCAPE
	}
	return false
}

handle_key_press :: proc(event: ^sdl2.Event, prev_input: string) -> string {
	new_input := prev_input
	#partial switch event.type {
	case .TEXTINPUT:
		input := cstring(raw_data(event.text.text[:])) // event.text.text [32]u8 (utf-8 encoding)
		new_input = strings.concatenate({prev_input, string(input)})
		fmt.println("TEXTINPUT event:", new_input)
	case .KEYDOWN:
		if event.key.keysym.scancode == .BACKSPACE {
			if len(prev_input) > 0 {
				new_input = prev_input[:len(prev_input) - 1]
				fmt.println("BACKSPACE event:", new_input)
			}
		}
	}
	return new_input
}

handle_change_text_size :: proc(event: ^sdl2.Event, current_size: int) -> int {
	new_size := current_size
	if event.type == .MOUSEWHEEL {
		fmt.printf("MOUSEWHEEL event: x=%d, y=%d\n", event.wheel.x, event.wheel.y)
		new_size += int(event.wheel.y)
	}
	return new_size
}

get_time :: proc() -> f64 {
	return f64(sdl2.GetPerformanceCounter()) * 1000 / perf_frequency
}
