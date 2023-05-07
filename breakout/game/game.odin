package game

import "core:c"
import "core:fmt"
import "core:mem"
import "core:math"
import "core:os"
import "core:runtime"
import "core:time"
import "core:slice"
import "core:strings"
import glm "core:math/linalg/glsl"

import "vendor:sdl2"
import gl "vendor:OpenGL"
import "vendor:stb/image"


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
	game := Game{.MENU, int(window_width), int(window_height)}
	target_dt: f64 = 1000 / f64(refresh_rate)

	sdl2.GL_SetAttribute(.CONTEXT_PROFILE_MASK, i32(sdl2.GLprofile.CORE))
	sdl2.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 3)
	sdl2.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 3)
	gl_context := sdl2.GL_CreateContext(window)
	defer sdl2.GL_DeleteContext(gl_context)
	gl.load_up_to(3, 3, sdl2.gl_set_proc_address)

	sprite_program, program_ok := gl.load_shaders_source(
		sprite_vertex_source,
		sprite_fragment_source,
	)
	if !program_ok {
		fmt.eprintln("Failed to create GLSL program")
		return
	}
	defer gl.DeleteProgram(sprite_program)
	gl.UseProgram(sprite_program)

	buffers := sprite_buffers_init()
	defer sprite_buffers_destroy(&buffers)

	projection: glm.mat4 = glm.mat4Ortho3d(0, f32(window_width), f32(window_height), 0, -1.0, 1)
	brick_texture := sprite_texture("breakout/textures/block.png", sprite_program, &projection)
	brick_solid_texture := sprite_texture(
		"breakout/textures/block_solid.png",
		sprite_program,
		&projection,
	)
	background_texture := sprite_texture(
		"breakout/textures/background.jpg",
		sprite_program,
		&projection,
	)
	paddle_texture := sprite_texture("breakout/textures/paddle.png", sprite_program, &projection)
	ball_texture := sprite_texture(
		"breakout/textures/awesomeface.png",
		sprite_program,
		&projection,
	)

	level: GameLevel
	load_ok := game_level_load(&level, level_one_file, game.window_width, game.window_height / 2)
	fmt.printf("w: %v, h: %v\n", game.window_width, game.window_height)
	assert(load_ok)
	defer game_level_destroy(&level)

	paddle: Paddle
	paddle_init(&paddle, game.window_width, game.window_height)

	ball: Ball
	paddle_top: f32 = paddle.pos.y - (paddle.size.y * .5)
	ball_init(&ball, game.window_width, game.window_height, paddle_top)

	// TODO: calculate dt
	dt: f32 = 1

	// game loop
	game_loop: for {
		// process input
		ball_released := false
		event: sdl2.Event
		for sdl2.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				break game_loop
			case .KEYUP:
				if event.key.keysym.sym == .ESCAPE {
					sdl2.PushEvent(&sdl2.Event{type = .QUIT})
				}
			case .KEYDOWN:
				if event.key.keysym.sym == .SPACE {
					ball_released = true
				}
			}
		}
		numkeys: c.int
		keyboard_state := sdl2.GetKeyboardState(&numkeys)
		is_left := keyboard_state[sdl2.Scancode.A] > 0 || keyboard_state[sdl2.Scancode.LEFT] > 0
		is_right := keyboard_state[sdl2.Scancode.D] > 0 || keyboard_state[sdl2.Scancode.RIGHT] > 0
		paddle_update(&paddle, dt, game.window_width, is_left, is_right)
		ball_update(&ball, dt, game.window_width, game.window_height, ball_released)
		if ball.stuck {
			ball_stuck_update(&ball, paddle.pos, paddle.size)
		}

		// render
		gl.Viewport(0, 0, window_width, window_height)
		gl.ClearColor(0.5, 0.5, 0.5, 1)
		gl.Clear(gl.COLOR_BUFFER_BIT)
		// draw background
		draw_sprite(
			sprite_program,
			background_texture.id,
			buffers.vao,
			{f32(game.window_width) * .5, f32(game.window_height) * .5},
			{f32(game.window_width), f32(game.window_height)},
			0,
			{1, 1, 1},
		)
		// draw level
		for brick in level.bricks {
			texture_id: u32
			if brick.is_solid {
				texture_id = brick_solid_texture.id
			} else {
				texture_id = brick_texture.id
			}
			pos := brick.pos
			size := brick.size
			pos.x += size.x * .5
			pos.y += size.y * .5
			draw_sprite(sprite_program, texture_id, buffers.vao, pos, size, 0, brick.color)
		}
		// draw paddle
		draw_sprite(
			sprite_program,
			paddle_texture.id,
			buffers.vao,
			paddle.pos,
			paddle.size,
			0,
			{1, 1, 1},
		)
		// draw ball
		draw_sprite(
			sprite_program,
			ball_texture.id,
			buffers.vao,
			ball.pos,
			ball.size,
			0,
			{1, 1, 1},
		)
		gl_report_error()
		sdl2.GL_SwapWindow(window)
	}
}

gl_report_error :: proc() {
	e := gl.GetError()
	if e != gl.NO_ERROR {
		fmt.println("OpenGL Error:", e)
	}
}
