package game

import "core:c"
import "core:fmt"
import "core:mem"
import "core:math"
import "core:math/rand"
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

GameState :: enum {
	ACTIVE,
	MENU,
	WIN,
}
Game :: struct {
	state:         GameState,
	lives:         int,
	window_width:  int,
	window_height: int,
	rand:          rand.Rand,
	sec_elapsed:   f64,
	level:         GameLevel,
	is_left:       bool,
	is_right:      bool,
	ball:          Ball,
	paddle:        Paddle,
	effects:       PostProcessor,
	ball_sparks:   ParticleEmitter,
	powerups:      Powerups,
	projection:    glm.mat4,
	renderer:      Renderer,
	lives_writer:  Writer,
	menu_writer:   Writer,
}
game_init :: proc(g: ^Game, width, height: int) {
	g.state = .MENU // TODO: start in main menu
	g.lives = 3
	g.window_width = width
	g.window_height = height
	rand.init(&g.rand, 214)
	g.projection = glm.mat4Ortho3d(0, f32(width), f32(height), 0, -1.0, 1)

	assert(game_level_load(&g.level, 1, width, height / 2), "Failed to load level")

	paddle_init(&g.paddle, width, height)
	ball_init(&g.ball, g.paddle.pos, g.paddle.size)

	assert(
		post_processor_init(&g.effects, i32(g.window_width), i32(g.window_height)),
		"Failed to init post processor effects",
	)
	particle_emitter_init(&g.ball_sparks, 123)
	assert(renderer_init(&g.renderer, g.projection), "Failed to init renderer")
	assert(
		powerups_init(&g.powerups, g.renderer.shaders.sprite, g.projection),
		"Failed to init powerups",
	)
	assert(
		writer_init(&g.lives_writer, TERMINAL_TTF, 16, g.projection),
		"Failed to init text writer",
	)
	assert(
		writer_init(&g.menu_writer, TERMINAL_TTF, 24, g.projection),
		"Failed to init text writer",
	)
}
game_destroy :: proc(g: ^Game) {
	game_level_destroy(&g.level)
	post_processor_destroy(&g.effects)
	particle_emitter_destroy(&g.ball_sparks)
	powerups_destroy(&g.powerups)
	writer_destroy(&g.lives_writer)
	writer_destroy(&g.menu_writer)
	renderer_destroy(&g.renderer)
}

run :: proc(window: ^sdl2.Window, window_width, window_height, refresh_rate: i32) {
	game_start_tick := time.tick_now()

	// Init OpenGL
	sdl2.GL_SetAttribute(.CONTEXT_PROFILE_MASK, i32(sdl2.GLprofile.CORE))
	sdl2.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 3)
	sdl2.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 3)
	gl_context := sdl2.GL_CreateContext(window)
	defer sdl2.GL_DeleteContext(gl_context)
	gl.load_up_to(3, 3, sdl2.gl_set_proc_address)

	game: Game
	game_init(&game, int(window_width), int(window_height))

	sound_ok := sound_engine_init()
	if !sound_ok {
		return
	}
	defer sound_engine_destroy()

	// events
	assert(event_q_init(), "Failed to init event queue")
	defer event_q_destroy()

	// start music
	// music_play(.BREAKOUT)

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
		game.sec_elapsed = time.duration_seconds(game_duration)

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

		exit := game_handle_inputs(&game)
		if exit {
			break game_loop
		}
		game_update(&game, dt)

		ok := game_handle_events(&game)
		if !ok do break game_loop

		game_render(&game, window)

		// timing (avoid looping too fast)
		duration := time.tick_since(start_tick)
		tgt_duration := time.Duration(target_ms_elapsed * f64(time.Millisecond))
		to_sleep := tgt_duration - duration
		time.accurate_sleep(to_sleep - (2 * time.Microsecond))
		duration = time.tick_since(start_tick)
		ms_elapsed = f64(time.duration_milliseconds(duration))
		fps = 1000 / ms_elapsed

		free_all(context.temp_allocator)
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
