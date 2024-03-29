package main

import "core:mem"
import "core:fmt"
import "core:time"
import "core:strings"
import glsl "core:math/linalg/glsl"

import "vendor:sdl2"
import gl "vendor:OpenGL"

GL_VERSION_MAJOR :: 3
GL_VERSION_MINOR :: 3

Game :: struct {
	fps: f64,
}


main :: proc() {
	assert(sdl2.Init({.VIDEO}) == 0, sdl2.GetErrorString())
	defer sdl2.Quit()

	displayMode: sdl2.DisplayMode
	sdl2.GetCurrentDisplayMode(0, &displayMode)
	refresh_rate := displayMode.refresh_rate

	window_width: i32 = 1280
	window_height: i32 = 960

	window := sdl2.CreateWindow(
		"UI Example",
		sdl2.WINDOWPOS_UNDEFINED,
		sdl2.WINDOWPOS_UNDEFINED,
		window_width,
		window_height,
		{.OPENGL},
	)
	assert(window != nil, sdl2.GetErrorString())
	defer sdl2.DestroyWindow(window)
	// sdl2.SetWindowFullscreen(window, sdl2.WINDOW_FULLSCREEN)

	fmt.printf("%dx%d %d\n", window_width, window_height, refresh_rate)

	run(window, window_width, window_height, refresh_rate)
}


run :: proc(window: ^sdl2.Window, window_width, window_height, refresh_rate: i32) {
	target_dt: f64 = 1000 / f64(refresh_rate)

	game := Game{}

	sdl2.GL_SetAttribute(.CONTEXT_PROFILE_MASK, i32(sdl2.GLprofile.CORE))
	sdl2.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, GL_VERSION_MAJOR)
	sdl2.GL_SetAttribute(.CONTEXT_MINOR_VERSION, GL_VERSION_MINOR)

	gl_context := sdl2.GL_CreateContext(window)
	defer sdl2.GL_DeleteContext(gl_context)

	gl.load_up_to(GL_VERSION_MAJOR, GL_VERSION_MINOR, sdl2.gl_set_proc_address)

	program, program_ok := gl.load_shaders_source(vertex_source, fragment_source)
	if !program_ok {
		fmt.eprintln("Failed to create GLSL program")
		return
	}
	defer gl.DeleteProgram(program)

	gl.UseProgram(program)

	uniforms := gl.get_uniforms_from_program(program)
	defer gl.destroy_uniforms(uniforms)

	vao: u32
	gl.GenVertexArrays(1, &vao)
	defer gl.DeleteVertexArrays(1, &vao)
	gl.BindVertexArray(vao)

	// OpenGL buffers
	vbo, ebo: u32
	gl.GenBuffers(1, &vbo);defer gl.DeleteBuffers(1, &vbo)
	gl.GenBuffers(1, &ebo);defer gl.DeleteBuffers(1, &ebo)

	Vertex :: struct {
		pos: glsl.vec3,
		col: glsl.vec4,
	}
	vertices := []Vertex{
		{{-0.5, +0.5, 0}, {1.0, 0.0, 0.0, 0.75}},
		{{-0.5, -0.5, 0}, {1.0, 1.0, 0.0, 0.75}},
		{{+0.5, -0.5, 0}, {0.0, 1.0, 0.0, 0.75}},
		{{+0.5, +0.5, 0}, {0.0, 0.0, 1.0, 0.75}},
	}

	indices := []u16{0, 1, 2, 2, 3, 0}

	gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
	gl.BufferData(
		gl.ARRAY_BUFFER,
		len(vertices) * size_of(vertices[0]),
		raw_data(vertices),
		gl.STATIC_DRAW,
	)
	gl.EnableVertexAttribArray(0)
	gl.EnableVertexAttribArray(1)
	gl.VertexAttribPointer(0, 3, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, pos))
	gl.VertexAttribPointer(1, 4, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, col))

	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo)
	gl.BufferData(
		gl.ELEMENT_ARRAY_BUFFER,
		len(indices) * size_of(indices[0]),
		raw_data(indices),
		gl.STATIC_DRAW,
	)

	start: f64
	end: f64

	start_tick := time.tick_now()

	game_loop: for {
		// start = get_time()

		duration := time.tick_since(start_tick)
		t := f32(time.duration_seconds(duration))

		// Handle input events
		event: sdl2.Event
		for sdl2.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				break game_loop
			case .KEYDOWN, .KEYUP:
				if event.type == .KEYUP && event.key.keysym.sym == .ESCAPE {
					sdl2.PushEvent(&sdl2.Event{type = .QUIT})
				}
			}
		}

		pos := glsl.vec3{glsl.cos(t * 2), glsl.sin(t * 2), 0}
		pos *= 0.3

		model := glsl.mat4{0.5, 0, 0, 0, 0, 0.5, 0, 0, 0, 0, 0.5, 0, 0, 0, 0, 1}

		model[0, 3] = -pos.x
		model[1, 3] = -pos.y
		model[2, 3] = -pos.z

		model[3].yzx = pos.yzx

		model = model * glsl.mat4Rotate({0, 1, 1}, t)

		view := glsl.mat4LookAt({0, -1, +1}, {0, 0, 0}, {0, 0, 1})
		proj := glsl.mat4Perspective(45, 1.3, 0.1, 100.0)

		u_transform := proj * view * model

		gl.UniformMatrix4fv(uniforms["u_transform"].location, 1, false, &u_transform[0, 0])

		gl.Viewport(0, 0, window_width, window_height)
		gl.ClearColor(0.5, 0.7, 1.0, 1.0)
		gl.Clear(gl.COLOR_BUFFER_BIT)

		gl.DrawElements(gl.TRIANGLES, i32(len(indices)), gl.UNSIGNED_SHORT, nil)

		sdl2.GL_SwapWindow(window)

		free_all(context.temp_allocator)

		// Timing (avoid looping too fast)
		end = get_time()
		to_sleep := time.Duration((target_dt - (end - start)) * f64(time.Millisecond))
		time.accurate_sleep(to_sleep)
		end = get_time()
		game.fps = 1000 / (end - start)
	}
}


get_time :: proc() -> f64 {
	return f64(sdl2.GetPerformanceCounter()) * 1000 / f64(sdl2.GetPerformanceFrequency())
}

vertex_source := `#version 330 core

layout(location=0) in vec3 a_position;
layout(location=1) in vec4 a_color;

out vec4 v_color;

uniform mat4 u_transform;

void main() {
	gl_Position = u_transform * vec4(a_position, 1.0);
	v_color = a_color;
}
`

fragment_source := `#version 330 core

in vec4 v_color;

out vec4 o_color;

void main() {
	o_color = v_color;
}
`
