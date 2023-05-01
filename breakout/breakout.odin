/* Breakout clone following learnopengl tutorial

https://learnopengl.com/In-Practice/2D-Game/Breakout

*/
package breakout

import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"

import "vendor:sdl2"

import "game"


_main :: proc(display_index: i32) {
	assert(sdl2.Init({.VIDEO}) == 0, sdl2.GetErrorString())
	defer sdl2.Quit()

	display_mode: sdl2.DisplayMode
	sdl2.GetCurrentDisplayMode(display_index, &display_mode)
	refresh_rate := display_mode.refresh_rate

	window_width: i32 = 1280
	window_height: i32 = 960

	window := sdl2.CreateWindow(
		"Breakout",
		sdl2.WINDOWPOS_UNDEFINED_DISPLAY(display_index),
		sdl2.WINDOWPOS_UNDEFINED_DISPLAY(display_index),
		window_width,
		window_height,
		{.OPENGL},
	)
	assert(window != nil, sdl2.GetErrorString())
	defer sdl2.DestroyWindow(window)

	fmt.printf("%dx%d %d\n", window_width, window_height, refresh_rate)

	game.run(window, window_width, window_height, refresh_rate)
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
