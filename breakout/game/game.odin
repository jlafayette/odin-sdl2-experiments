package game

import "core:fmt"
import "core:mem"
import "core:os"
import "core:time"
import "core:slice"
import "core:strings"
import glsl "core:math/linalg/glsl"

import "vendor:sdl2"
import gl "vendor:OpenGL"


Game :: struct {
	state:         GameState,
	window_width:  int,
	window_height: int,
}
GameState :: enum {
	ACTIVE,
	MENU,
	WIN,
}

run :: proc(window: ^sdl2.Window, window_width, window_height, refresh_rate: i32) {
	// Init
	game := Game{.MENU, 800, 600}
	target_dt: f64 = 1000 / f64(refresh_rate)

	sdl2.GL_SetAttribute(.CONTEXT_PROFILE_MASK, i32(sdl2.GLprofile.CORE))
	sdl2.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 3)
	sdl2.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 3)
	gl_context := sdl2.GL_CreateContext(window)
	defer sdl2.GL_DeleteContext(gl_context)
	gl.load_up_to(3, 3, sdl2.gl_set_proc_address)

	program1, program_ok := gl.load_shaders_source(vertex_source, fragment_source1)
	if !program_ok {
		fmt.eprintln("Failed to create GLSL program")
		return
	}
	defer gl.DeleteProgram(program1)
	gl.UseProgram(program1)

	// game loop
	game_loop: for {
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

		// update

		// render
	}
}
