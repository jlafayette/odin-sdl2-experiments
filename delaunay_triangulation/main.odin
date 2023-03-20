package delaunay_triangulation

import "core:fmt"
import "core:mem"
import "core:time"
import "vendor:sdl2"
import gl "vendor:OpenGL"
import "core:math/linalg/glsl"


main :: proc() {
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
}

_main :: proc() {
	assert(sdl2.Init({.VIDEO}) == 0, sdl2.GetErrorString())
	defer sdl2.Quit()

	display_mode: sdl2.DisplayMode
	sdl2.GetCurrentDisplayMode(1, &display_mode)
	refresh_rate := display_mode.refresh_rate

	width: i32 = 1280
	height: i32 = 960

	window := sdl2.CreateWindow(
		"Delaunay Triangulation",
		sdl2.WINDOWPOS_UNDEFINED_DISPLAY(1),
		sdl2.WINDOWPOS_UNDEFINED_DISPLAY(1),
		width,
		height,
		{.OPENGL},
	)
	assert(window != nil, sdl2.GetErrorString())
	defer sdl2.DestroyWindow(window)

	fmt.printf("%dx%d %d\n", width, height, refresh_rate)

	run(window, width, height, refresh_rate)
}


run :: proc(window: ^sdl2.Window, window_width, window_height, refresh_rate: i32) {
	target_dt: f64 = 1000 / f64(refresh_rate)

	sdl2.GL_SetAttribute(.CONTEXT_PROFILE_MASK, i32(sdl2.GLprofile.CORE))
	sdl2.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 3)
	sdl2.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 3)
	gl_context := sdl2.GL_CreateContext(window)
	defer sdl2.GL_DeleteContext(gl_context)
	gl.load_up_to(3, 3, sdl2.gl_set_proc_address)

	// Create and link shader program
	program, program_ok := gl.load_shaders_source(vertex_source, fragment_source)
	if !program_ok {
		fmt.eprintln("Failed to create GLSL program")
		return
	}
	defer gl.DeleteProgram(program)
	gl.UseProgram(program)
	uniforms := gl.get_uniforms_from_program(program)
	defer gl.destroy_uniforms(uniforms)

	// Vertex Array Object
	vao: u32
	gl.GenVertexArrays(1, &vao)
	defer gl.DeleteVertexArrays(1, &vao)
	gl.BindVertexArray(vao)

	// Vertices
	Vertex :: struct {
		pos: glsl.vec3,
	}
	vertices := []Vertex{
		{{+0.5, +0.5, 0.0}},
		{{+0.5, -0.5, 0.0}},
		{{-0.5, -0.5, 0.0}},
		{{-0.5, +0.5, 0.0}},
	}
	indices := []u16{0, 1, 3, 1, 2, 3}
	// Vertex Buffer Object
	vbo: u32
	gl.GenBuffers(1, &vbo)
	defer gl.DeleteBuffers(1, &vbo)
	gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
	gl.BufferData(
		gl.ARRAY_BUFFER,
		len(vertices) * size_of(vertices[0]),
		raw_data(vertices),
		gl.STATIC_DRAW,
	)
	// 0: (matches with location=0 in the vertex shader)
	// 3: this is a vec3
	// type: they are floats
	// false: not normalized (to 0.0-1.0 or -1.0-1.0 range, for int,byte)
	// stride: space between consective vertex attributes (0=auto for tightly packed)
	// offset: space between start of Vertex and pos attribute
	gl.VertexAttribPointer(0, 3, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, pos))
	gl.EnableVertexAttribArray(0)

	// Element Buffer Object
	ebo: u32
	gl.GenBuffers(1, &ebo)
	defer gl.DeleteBuffers(1, &ebo)
	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo)
	gl.BufferData(
		gl.ELEMENT_ARRAY_BUFFER,
		len(indices) * size_of(indices[0]),
		raw_data(indices),
		gl.STATIC_DRAW,
	)

	wireframe := false

	start_tick := time.tick_now()
	game_loop: for {
		duration := time.tick_since(start_tick)
		t := f32(time.duration_seconds(duration))

		event: sdl2.Event
		for sdl2.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				break game_loop
			case .KEYUP:
				if event.key.keysym.sym == .ESCAPE {
					sdl2.PushEvent(&sdl2.Event{type = .QUIT})
				}
			case .MOUSEBUTTONDOWN:
				wireframe = true
			case .MOUSEBUTTONUP:
				wireframe = false
			}
		}

		gl.Viewport(0, 0, window_width, window_height)
		gl.ClearColor(0.25, 0.35, 0.5, 1.0)
		gl.Clear(gl.COLOR_BUFFER_BIT)
		if wireframe {
			gl.PointSize(10)
			gl.PolygonMode(gl.FRONT_AND_BACK, gl.POINT)
			gl.DrawElements(gl.TRIANGLES, i32(len(indices)), gl.UNSIGNED_SHORT, nil)
			gl.LineWidth(3)
			gl.PolygonMode(gl.FRONT_AND_BACK, gl.LINE)
			gl.DrawElements(gl.TRIANGLES, i32(len(indices)), gl.UNSIGNED_SHORT, nil)
		} else {
			gl.PolygonMode(gl.FRONT_AND_BACK, gl.FILL)
			gl.DrawElements(gl.TRIANGLES, i32(len(indices)), gl.UNSIGNED_SHORT, nil)
		}

		sdl2.GL_SwapWindow(window)

		free_all(context.temp_allocator)
	}
}

vertex_source := `#version 330 core

layout(location=0) in vec3 aPos;

void main() {
	gl_Position = vec4(aPos, 1.0);
}
`

fragment_source := `#version 330 core

out vec4 FragColor;

void main() {
	FragColor = vec4(1.0, 0.5, 0.2, 1.0);
}
`
