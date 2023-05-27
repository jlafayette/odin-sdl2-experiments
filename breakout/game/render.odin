package game

import "core:fmt"
import "core:strings"
import glm "core:math/linalg/glsl"

import gl "vendor:OpenGL"
import "vendor:sdl2"

ShaderPrograms :: struct {
	sprite:   u32,
	particle: u32,
	// text:     u32,
}
Textures :: struct {
	brick:       Texture2D,
	brick_solid: Texture2D,
	background:  Texture2D,
	ball:        Texture2D,
	paddle:      Texture2D,
	particle:    Texture2D,
}

Renderer :: struct {
	shaders:  ShaderPrograms,
	textures: Textures,
	buffers:  SpriteBuffers,
}
renderer_init :: proc(r: ^Renderer, projection: glm.mat4) -> bool {
	ok: bool
	r.shaders.sprite, ok = gl.load_shaders_source(sprite_vertex_source, sprite_fragment_source)
	if !ok {
		fmt.eprintln("Failed to create GLSL program")
		return false
	}

	r.shaders.particle, ok = gl.load_shaders_source(
		particle_vertex_source,
		particle_fragment_source,
	)
	if !ok {
		fmt.eprintln("Failed to create GLSL program for particles")
		return false
	}

	r.buffers = sprite_buffers_init()

	r.textures.brick = sprite_texture("breakout/textures/block.png", r.shaders.sprite, projection)
	r.textures.brick_solid = sprite_texture(
		"breakout/textures/block_solid.png",
		r.shaders.sprite,
		projection,
	)
	r.textures.background = sprite_texture(
		"breakout/textures/background.jpg",
		r.shaders.sprite,
		projection,
	)
	r.textures.paddle = sprite_texture(
		"breakout/textures/paddle.png",
		r.shaders.sprite,
		projection,
	)
	r.textures.ball = sprite_texture(
		"breakout/textures/awesomeface.png",
		r.shaders.sprite,
		projection,
	)
	r.textures.particle = sprite_texture(
		"breakout/textures/particle2.png",
		r.shaders.particle,
		projection,
	)

	return true
}
renderer_destroy :: proc(r: ^Renderer) {
	sprite_buffers_destroy(&r.buffers)
	gl.DeleteProgram(r.shaders.sprite)
	gl.DeleteProgram(r.shaders.particle)
	// gl.DeleteProgram(r.shaders.text)
}

game_render :: proc(g: ^Game, window: ^sdl2.Window) {
	r := &g.renderer
	game := g
	vao := r.buffers.vao

	// render
	gl.Viewport(0, 0, i32(game.window_width), i32(game.window_height))
	// matches edges of background image (this shows when screen shakes)
	gl.ClearColor(0.007843, 0.02353, 0.02745, 1)
	gl.Clear(gl.COLOR_BUFFER_BIT)

	post_processor_begin_render(&game.effects)

	// draw background
	draw_sprite(
		r.shaders.sprite,
		r.textures.background.id,
		r.buffers.vao,
		{0, 0},
		{f32(game.window_width), f32(game.window_height)},
		0,
		{1, 1, 1},
	)
	// draw level
	for brick in game.level.bricks {
		if brick.destroyed {
			continue
		}
		texture_id: u32
		if brick.is_solid {
			texture_id = r.textures.brick_solid.id
		} else {
			texture_id = r.textures.brick.id
		}
		pos := brick.pos
		size := brick.size
		draw_sprite(r.shaders.sprite, texture_id, r.buffers.vao, pos, size, 0, brick.color)
	}
	// draw paddle
	paddle_color: glm.vec3 = {1, 1, 1}
	if game.paddle.sticky {
		paddle_color = {1, .5, 1}
	}
	draw_sprite(
		r.shaders.sprite,
		r.textures.paddle.id,
		vao,
		game.paddle.pos,
		game.paddle.size,
		0,
		paddle_color,
	)
	// draw powerups
	powerups_render(&game.powerups, r.shaders.sprite, vao)
	// draw particles
	particles_render(&game.ball_sparks, r.shaders.particle, r.textures.particle.id, vao)
	// draw ball
	ball_color: glm.vec3 = {1, 1, 1}
	if game.ball.pass_through > 0 {
		ball_color = {1, .5, 1}
	}
	draw_sprite(
		r.shaders.sprite,
		r.textures.ball.id,
		vao,
		game.ball.pos,
		game.ball.size,
		0,
		ball_color,
	)
	// particles_render(&mouse_sparks, particle_program, particle_texture.id, vao)
	post_processor_end_render(&game.effects)
	post_processor_render(&game.effects, f32(game.sec_elapsed))

	// Text rendering
	sb: strings.Builder
	strings.builder_init_len(&sb, 10, context.temp_allocator)
	fmt.sbprintf(&sb, "Lives: %d", game.lives)
	write_text(&g.lives_writer, strings.to_string(sb), {10, 10}, {1, 1, 1})


	switch game.state {
	case .ACTIVE:
	case .MENU:
		writer := &g.menu_writer

		center: glm.vec2 = {f32(game.window_width) / 2, f32(game.window_height) / 2}
		line1 := "Press ENTER to start"
		dim1 := text_get_size(writer, line1)
		pos1: glm.vec2 = {center.x - dim1.x * .5, center.y + f32(writer.line_gap)}
		write_text(writer, line1, pos1, {1, 1, 1})

		line2 := "Press W or S to select level"
		dim2 := text_get_size(writer, line2)
		pos2: glm.vec2 = {center.x - dim2.x * .5, pos1.y + dim1.y + f32(writer.line_gap)}
		write_text(writer, line2, pos2, .75)
	case .WIN:
		writer := &g.menu_writer

		center: glm.vec2 = {f32(game.window_width) / 2, f32(game.window_height) / 2}
		line1 := "You WON!!!"
		dim1 := text_get_size(writer, line1)
		pos1: glm.vec2 = {center.x - dim1.x * .5, center.y + f32(writer.line_gap)}
		write_text(writer, line1, pos1, {1, 1, 1})

		line2 := "Press ENTER to retry or ESC to quit"
		dim2 := text_get_size(writer, line2)
		pos2: glm.vec2 = {center.x - dim2.x * .5, pos1.y + dim1.y + f32(writer.line_gap)}
		write_text(writer, line2, pos2, .75)
	case .LOSE:
		writer := &g.menu_writer

		center: glm.vec2 = {f32(game.window_width) / 2, f32(game.window_height) / 2}
		line1 := "You lost :("
		dim1 := text_get_size(writer, line1)
		pos1: glm.vec2 = {center.x - dim1.x * .5, center.y + f32(writer.line_gap)}
		write_text(writer, line1, pos1, {1, 1, 1})

		line2 := "Press ENTER to retry or ESC to quit"
		dim2 := text_get_size(writer, line2)
		pos2: glm.vec2 = {center.x - dim2.x * .5, pos1.y + dim1.y + f32(writer.line_gap)}
		write_text(writer, line2, pos2, .75)
	}


	gl_report_error()
	sdl2.GL_SwapWindow(window)
}
