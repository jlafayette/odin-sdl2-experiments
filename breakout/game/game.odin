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
import "vendor:sdl2/mixer"
import gl "vendor:OpenGL"
import "vendor:stb/image"

DEBUG_FPS :: false

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
	game_start_tick := time.tick_now()
	// Init
	game := Game{.MENU, int(window_width), int(window_height)}

	sound_ok := sound_engine_init()
	if !sound_ok {
		return
	}
	defer sound_engine_destroy()

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

	particle_program, program2_ok := gl.load_shaders_source(
		particle_vertex_source,
		particle_fragment_source,
	)
	if !program2_ok {
		fmt.eprintln("Failed to create GLSL program for particles")
		return
	}
	defer gl.DeleteProgram(particle_program)

	effects_program, effects_program_ok := gl.load_shaders_source(
		postprocess_vertex_source,
		postprocess_fragment_source,
	)
	if !effects_program_ok {
		fmt.eprintln("Failed to create GLSL program for effects")
		return
	}
	defer gl.DeleteProgram(effects_program)

	buffers := sprite_buffers_init()
	defer sprite_buffers_destroy(&buffers)

	projection: glm.mat4 = glm.mat4Ortho3d(0, f32(window_width), f32(window_height), 0, -1.0, 1)
	brick_texture := sprite_texture("breakout/textures/block.png", sprite_program, projection)
	brick_solid_texture := sprite_texture(
		"breakout/textures/block_solid.png",
		sprite_program,
		projection,
	)
	background_texture := sprite_texture(
		"breakout/textures/background.jpg",
		sprite_program,
		projection,
	)
	paddle_texture := sprite_texture("breakout/textures/paddle.png", sprite_program, projection)
	ball_texture := sprite_texture("breakout/textures/awesomeface.png", sprite_program, projection)
	particle_texture := sprite_texture(
		"breakout/textures/particle2.png",
		particle_program,
		projection,
	)
	ball_sparks: ParticleEmitter
	particle_emitter_init(&ball_sparks, 123)
	defer particle_emitter_destroy(&ball_sparks)
	// mouse_sparks : ParticleEmitter
	// particle_emitter_init(&mouse_sparks, 123)
	// defer particle_emitter_destroy(&mouse_sparks)

	level: GameLevel
	load_ok := game_level_load(&level, 1, game.window_width, game.window_height / 2)
	fmt.printf("w: %v, h: %v\n", game.window_width, game.window_height)
	assert(load_ok)
	defer game_level_destroy(&level)

	paddle: Paddle
	paddle_init(&paddle, game.window_width, game.window_height)

	ball: Ball
	ball_init(&ball, paddle.pos, paddle.size)

	powerups: Powerups
	assert(powerups_init(&powerups, sprite_program, projection), "Failed to init powerups")

	// effects
	effects: PostProcessor
	post_processor_init(&effects, effects_program, i32(game.window_width), i32(game.window_height))

	// events
	assert(event_q_init(), "Failed to init event queue")
	defer event_q_destroy()

	// timing stuff
	fps: f64 = 0
	target_ms_elapsed: f64 = 1000 / f64(refresh_rate)
	ms_elapsed: f64 = target_ms_elapsed
	target_dt: f64 = (1000 / f64(refresh_rate)) / 1000
	dt := f32(ms_elapsed / 1000)
	when DEBUG_FPS {
		_lo_ms: f64 = 999
		_hi_ms: f64 = 0
		_ms: f64 = 0
		_sec_tick: time.Tick = time.tick_now()
		_frames: int = 0
	}

	// game loop
	game_loop: for {
		start_tick := time.tick_now()
		dt = f32(ms_elapsed / 1000)
		// fmt.printf("\nFPS: %f\n", fps)
		// fmt.printf("ms: %f\n", ms_elapsed)
		// fmt.printf("dt: %f\n", dt)
		// fmt.printf("tgt dt: %f\n", target_dt)
		game_duration := time.tick_since(game_start_tick)
		game_sec_elapsed := time.duration_seconds(game_duration)

		// debug time tracking
		when DEBUG_FPS {
			_frames += 1
			_ms += ms_elapsed
			_lo_ms = min(ms_elapsed, _lo_ms)
			_hi_ms = max(ms_elapsed, _hi_ms)
			if time.duration_seconds(time.tick_since(_sec_tick)) >= 1.0 {
				fmt.printf(
					"%d FPS, min: %.2f, max: %.2f, avg: %.2f\n",
					_frames,
					_lo_ms,
					_hi_ms,
					_ms / cast(f64)_frames,
				)
				// reset
				_lo_ms = 999
				_hi_ms = 0
				_ms = 0
				_sec_tick = time.tick_now()
				_frames = 0
			}

		}

		// process input
		ball_released := false
		next_level := false
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
				#partial switch event.key.keysym.sym {
				case .SPACE:
					ball_released = true
				case .X:
					next_level = true
				}
			}
		}
		numkeys: c.int
		keyboard_state := sdl2.GetKeyboardState(&numkeys)
		is_left := keyboard_state[sdl2.Scancode.A] > 0 || keyboard_state[sdl2.Scancode.LEFT] > 0
		is_right := keyboard_state[sdl2.Scancode.D] > 0 || keyboard_state[sdl2.Scancode.RIGHT] > 0
		paddle_update(&paddle, dt, game.window_width, is_left, is_right)
		game_over := ball_update(&ball, dt, game.window_width, game.window_height, ball_released)
		if ball.stuck {
			ball_stuck_update(&ball, paddle.pos)
		}
		collide_info: CollideInfo
		level_complete := true
		for brick, brick_i in level.bricks {
			if brick.destroyed {
				continue
			}
			collide_type: CollideType = .SOLID_BLOCK
			if !brick.is_solid {
				collide_type = .BLOCK
				level_complete = false
			}
			collide_info = check_collision_ball(
				ball.pos,
				ball.radius,
				brick.pos,
				brick.size,
				collide_type,
			)
			if collide_info.type != .NONE {
				append(
					&event_q,
					EventCollide{type = .BRICK, pos = brick.pos, solid = brick.is_solid},
				)
				ball_handle_collision(&ball, collide_info)
				if !brick.is_solid {
					level.bricks[brick_i].destroyed = true
				}
			}
		}
		if !ball_released && !ball.stuck {
			collide_info = check_collision_ball(
				ball.pos,
				ball.radius,
				paddle.pos,
				paddle.size,
				.PADDLE,
			)
			if collide_info.type != .NONE {
				append(&event_q, EventCollide{type = .PADDLE, pos = paddle.pos})
				ball_handle_paddle_collision(&ball, &paddle, collide_info)
			}
		}
		// update powerups
		powerups_update(&powerups, dt, game.window_height)
		for pu, pu_i in powerups.data {
			if pu.activated || pu.destroyed {
				continue
			}
			collided := check_collision_rect(paddle.pos, paddle.size, pu.pos, pu.size)
			if collided {
				append(&event_q, EventCollide{type = .POWERUP, pos = pu.pos})
				powerups_handle_collision(&powerups, &paddle, pu_i)
			}
		}
		// update particles
		particle_update(&ball_sparks, dt, ball.pos, ball.velocity, ball.radius * .5)
		// mouse_pos := get_mouse_pos(i32(game.window_width), i32(game.window_height))
		// particle_update(&mouse_sparks, dt, glm.vec2(mouse_pos), {0, 0}, {0, 0})
		post_processor_update(&effects, dt)
		// handle events
		for event in event_q {
			switch e in event {
			case EventCollide:
				effects.shake = true
				switch e.type {
				case .BRICK:
					effects.shake_time = 0.05
					if !e.solid do powerup_spawn(&powerups, e.pos)
					if e.solid {
						sound_play(.SOLID)
					} else {
						sound_play(.BLEEP)
					}
				case .PADDLE:
					sound_play(Sound.BLOOP)
					effects.shake_time = 0.02
				case .POWERUP:
					sound_play(.POWERUP)
				case .WALL:
					sound_play(.SOLID)
				}
			case EventPowerupActivated:
				switch e.type {
				case .SPEED:
					ball.velocity *= 1.2
				case .STICKY:
					ball.sticky += 1
					paddle.sticky = true
				case .PASS_THROUGH:
					ball.pass_through += 1
				case .PADDLE_SIZE_INCREASE:
					paddle.size.x += 50
				case .CONFUSE:
					effects.confuse = true
				case .CHAOS:
					effects.chaos = true
				}
			case EventPowerupDeactivated:
				switch e.type {
				case .SPEED:
					ball.velocity /= 1.2
				case .STICKY:
					ball.sticky -= 1
					paddle.sticky = ball.sticky > 0
				case .PASS_THROUGH:
					ball.pass_through -= 1
				case .PADDLE_SIZE_INCREASE:
					paddle.size.x -= 50
				case .CONFUSE:
					effects.confuse = false
				case .CHAOS:
					effects.chaos = false
				}
			}
		}
		clear(&event_q)

		// handle level complete/next_level
		if level_complete || next_level {
			number := level.number + 1
			load_ok = game_level_load(&level, number, game.window_width, game.window_height / 2)
			// TODO: make game compeleted screen
			if !load_ok {
				fmt.eprintf("Error loading level %d\n", number)
				break game_loop
			}
			paddle_reset(&paddle)
			ball_reset(&ball, paddle.pos, paddle.size)
			clear(&powerups.data)
			effects.confuse = false
			effects.chaos = false
		}
		// handle game over
		if game_over {
			// TODO: make game over screen
			// TODO: add lives and only reset level when they are out
			game_level_reset(&level)
			paddle_reset(&paddle)
			ball_reset(&ball, paddle.pos, paddle.size)
			clear(&powerups.data)
			effects.confuse = false
			effects.chaos = false
		}

		// render
		gl.Viewport(0, 0, window_width, window_height)
		// matches edges of background image (this shows when screen shakes)
		gl.ClearColor(0.007843, 0.02353, 0.02745, 1)
		gl.Clear(gl.COLOR_BUFFER_BIT)
		// effects.confuse = true
		// effects.chaos = true
		post_processor_begin_render(&effects)

		// draw background
		draw_sprite(
			sprite_program,
			background_texture.id,
			buffers.vao,
			{0, 0},
			{f32(game.window_width), f32(game.window_height)},
			0,
			{1, 1, 1},
		)
		// draw level
		for brick in level.bricks {
			if brick.destroyed {
				continue
			}
			texture_id: u32
			if brick.is_solid {
				texture_id = brick_solid_texture.id
			} else {
				texture_id = brick_texture.id
			}
			pos := brick.pos
			size := brick.size
			draw_sprite(sprite_program, texture_id, buffers.vao, pos, size, 0, brick.color)
		}
		// draw paddle
		paddle_color: glm.vec3 = {1, 1, 1}
		if paddle.sticky {
			paddle_color = {1, .5, 1}
		}
		draw_sprite(
			sprite_program,
			paddle_texture.id,
			buffers.vao,
			paddle.pos,
			paddle.size,
			0,
			paddle_color,
		)
		// draw powerups
		powerups_render(&powerups, sprite_program, buffers.vao)
		// debug stuff
		draw_sprite(
			sprite_program,
			brick_texture.id,
			buffers.vao,
			{15, 15},
			{10, 10 * cast(f32)ball.sticky},
			0,
			{0, 1, 1},
		)
		// draw particles
		particles_render(&ball_sparks, particle_program, particle_texture.id, buffers.vao)
		// draw ball
		ball_color: glm.vec3 = {1, 1, 1}
		if ball.pass_through > 0 {
			ball_color = {1, .5, 1}
		}
		draw_sprite(
			sprite_program,
			ball_texture.id,
			buffers.vao,
			ball.pos,
			ball.size,
			0,
			ball_color,
		)
		// particles_render(&mouse_sparks, particle_program, particle_texture.id, buffers.vao)
		post_processor_end_render(&effects)
		post_processor_render(&effects, f32(game_sec_elapsed))
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
