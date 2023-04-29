/* Breakout clone following learnopengl tutorial

https://learnopengl.com/In-Practice/2D-Game/Breakout

*/
package breakout

import "core:fmt"
import "core:mem"
import "core:os"
import "core:time"
import "core:slice"
import "core:strings"
import glsl "core:math/linalg/glsl"

import "vendor:sdl2"
import gl "vendor:OpenGL"


main :: proc() {

	args := os.args[1:]
	if slice.contains(args, "-m") || slice.contains(args, "--mem-track") {
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

	fmt.println("hellope!")

	x := new([12]int)
	free(x)

}
