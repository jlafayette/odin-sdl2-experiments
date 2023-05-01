package game

import "core:fmt"
import "core:mem"
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
	game := Game{.MENU, 800, 600}
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

	projection: glm.mat4 = glm.mat4Ortho3d(0, f32(window_width), f32(window_height), 0, -1.0, 1)

	// sprite renderer
	// sprite init
	vbo: u32
	quadVao: u32

	Vertex :: struct {
		pos: glm.vec2,
		tex: glm.vec2,
	}
	vertices := []Vertex{
		{{0, 1}, {0, 1}},
		{{1, 0}, {1, 0}},
		{{0, 0}, {0, 0}},
		{{0, 1}, {0, 1}},
		{{1, 1}, {1, 1}},
		{{1, 0}, {1, 0}},
	}
	gl.GenVertexArrays(1, &quadVao)
	defer gl.DeleteVertexArrays(1, &quadVao)
	gl.GenBuffers(1, &vbo);defer gl.DeleteBuffers(1, &vbo)
	gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
	gl.BufferData(
		gl.ARRAY_BUFFER,
		len(vertices) * size_of(vertices[0]),
		raw_data(vertices),
		gl.STATIC_DRAW,
	)
	gl.BindVertexArray(quadVao)
	gl.EnableVertexAttribArray(0)
	gl.EnableVertexAttribArray(1)
	gl.VertexAttribPointer(0, 2, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, pos))
	gl.VertexAttribPointer(1, 2, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, tex))
	// SpriteRenderer Init
	tex: Texture2D
	{

		tex.internal_format = gl.RGB
		tex.image_format = gl.RGB
		tex.wrap_s = gl.REPEAT
		tex.wrap_t = gl.REPEAT
		tex.filter_min = gl.NEAREST
		tex.filter_max = gl.NEAREST
		gl.GenTextures(1, &tex.id)
		alpha := false
		w, h, nr_channels: i32
		data := image.load("breakout/resources/images/ship1.png", &w, &h, &nr_channels, 0)
		defer image.image_free(data)
		fmt.println("w:", w, "h:", h, "channels:", nr_channels)
		tex.width = u32(w)
		tex.height = u32(h)
		gl.BindTexture(gl.TEXTURE_2D, tex.id);defer gl.BindTexture(gl.TEXTURE_2D, 0)
		gl.TexImage2D(
			gl.TEXTURE_2D,
			0,
			i32(tex.internal_format),
			w,
			h,
			0,
			tex.image_format,
			gl.UNSIGNED_BYTE,
			data,
		)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, i32(tex.wrap_s))
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, i32(tex.wrap_t))
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, i32(tex.filter_min))
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, i32(tex.filter_max))

		// proj := glm.mat4Ortho3d(0, f32(w), f32(h), 0, -1, 1)
		gl.UseProgram(sprite_program)
		gl.Uniform1i(gl.GetUniformLocation(sprite_program, "image"), 0)
		gl.UniformMatrix4fv(
			gl.GetUniformLocation(sprite_program, "projection"),
			1,
			false,
			&projection[0, 0],
		)
	}

	rotate: f32 = 0
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
		rotate += 1

		// render
		gl.Viewport(0, 0, window_width, window_height)
		gl.ClearColor(0.5, 0.5, 0.5, 1)
		gl.Clear(gl.COLOR_BUFFER_BIT)
		draw_sprite(tex, sprite_program, quadVao, {500, 450}, {240, 320}, rotate, {1, 1, 1})
		gl_report_error()
		sdl2.GL_SwapWindow(window)
	}
}


Texture2D :: struct {
	id:              u32,
	width:           u32,
	height:          u32,
	internal_format: u32,
	image_format:    u32,
	wrap_s:          u32,
	wrap_t:          u32,
	filter_min:      u32,
	filter_max:      u32,
}

draw_sprite :: proc(
	tex: Texture2D,
	program_id: u32,
	vao: u32,
	pos, size: glm.vec2,
	rotate: f32,
	color: glm.vec3,
) {
	gl.UseProgram(program_id)
	model := glm.mat4(1)
	model = model * glm.mat4Translate({pos.x, pos.y, 0})
	model = model * glm.mat4Rotate({0, 0, 1}, glm.radians(rotate))
	model = model * glm.mat4Translate({-.5 * size.x, -.5 * size.y, 0})
	model = model * glm.mat4Scale({size.x, size.y, 1})

	gl.UniformMatrix4fv(gl.GetUniformLocation(program_id, "model"), 1, false, &model[0, 0])
	c := color
	gl.Uniform3fv(gl.GetUniformLocation(program_id, "spriteColor"), 1, &c[0])
	gl.ActiveTexture(gl.TEXTURE0)
	gl.BindTexture(gl.TEXTURE_2D, tex.id)

	gl.BindVertexArray(vao);defer gl.BindVertexArray(0)

	gl.DrawArrays(gl.TRIANGLES, 0, 6)
}

gl_report_error :: proc() {
	e := gl.GetError()
	if e != gl.NO_ERROR {
		fmt.println("OpenGL Error:", e)
	}
}
