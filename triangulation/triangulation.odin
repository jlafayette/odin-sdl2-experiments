package triangulation

import "core:c"
import "core:fmt"
import "core:mem"
import "core:slice"
import "core:time"
import "core:strings"
import "vendor:sdl2"
import gl "vendor:OpenGL"
import "core:math/linalg/glsl"

import "delaunay"


Vertex :: struct {
	pos: glsl.vec3,
}

Mesh :: struct {
	vertices:      [dynamic]Vertex,
	indices:       [dynamic]u16,
	point_indices: [dynamic]u16,
	modified:      bool,
}
Buffers :: struct {
	vao: u32,
	vbo: u32,
	ebo: u32,
}

MAX_VERTICES :: 256

init_mesh :: proc(mesh: ^Mesh) {
	reserve_dynamic_array(&mesh.vertices, MAX_VERTICES)
	append(
		&mesh.vertices,
		Vertex{{+0.53, +0.51, 0.0}},
		Vertex{{+0.56, -0.52, 0.0}},
		Vertex{{-0.58, -0.54, 0.0}},
		// Vertex{{-0.5, +0.55, 0.0}},
	)
	reserve_dynamic_array(&mesh.point_indices, MAX_VERTICES)
	reserve_dynamic_array(&mesh.indices, MAX_VERTICES * 3)
	add_vertex(mesh, -0.5, +0.55)
	// append(&mesh.indices, 0, 1, 2, 1, 2, 3)
	mesh.modified = true
}

add_vertex :: proc(mesh: ^Mesh, x, y: f32) {
	if len(mesh.vertices) >= MAX_VERTICES {
		return
	}
	append(&mesh.vertices, Vertex{{x, y, 0.0}})
	clear_dynamic_array(&mesh.point_indices)
	for _, i in mesh.vertices {
		append(&mesh.point_indices, u16(i))
	}

	// sort mesh vertices by increasing x
	vertex_less :: proc(i, j: Vertex) -> bool {
		return i.pos.x < j.pos.x
	}
	slice.sort_by(mesh.vertices[:], vertex_less)
	nv := len(mesh.vertices)

	points := make([dynamic]delaunay.Point, 0, len(mesh.vertices) + 3)
	defer delete(points)
	for vertex in mesh.vertices {
		append(&points, delaunay.Point(vertex.pos.xy))
	}
	cap_backing_triangles := len(mesh.vertices) * 3
	i_triangles := make([dynamic]delaunay.I_Verts, cap_backing_triangles, cap_backing_triangles)
	defer delete(i_triangles)

	i_points_i, i_tri_i := delaunay.triangulate(&points, &i_triangles)

	// temp see transform remapping on points is working
	for p, i in points[:i_points_i] {
		mesh.vertices[i].pos = {p.x, p.y, 0.0}
	}

	clear_dynamic_array(&mesh.indices)
	for tri in i_triangles[:] {
		// if tri.x >= nv || tri.y >= nv || tri.z >= nv {
		// 	continue
		// }
		append(&mesh.indices, u16(tri.x), u16(tri.y), u16(tri.z))
	}

	mesh.modified = true
}

destroy_mesh :: proc(mesh: ^Mesh) {
	delete(mesh.vertices)
	delete(mesh.indices)
	delete(mesh.point_indices)
}


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
	program1, program_ok := gl.load_shaders_source(vertex_source, fragment_source1)
	if !program_ok {
		fmt.eprintln("Failed to create GLSL program")
		return
	}
	defer gl.DeleteProgram(program1)
	gl.UseProgram(program1)
	uniforms1 := gl.get_uniforms_from_program(program1)
	defer gl.destroy_uniforms(uniforms1)

	// Create second shader program
	program2, program2_ok := gl.load_shaders_source(vertex_source, fragment_source2)
	if !program2_ok do return
	defer gl.DeleteProgram(program2)

	// // Vertex Array Object
	// vao: u32
	// gl.GenVertexArrays(1, &vao)
	// defer gl.DeleteVertexArrays(1, &vao)
	// gl.BindVertexArray(vao)

	// Vertices
	mesh := Mesh{}
	init_mesh(&mesh)
	defer destroy_mesh(&mesh)

	tri_buffers := create_buffers(mesh.vertices[:], mesh.indices[:])
	defer delete_buffers(&tri_buffers)
	point_buffers := create_buffers(mesh.vertices[:], mesh.point_indices[:])
	defer delete_buffers(&point_buffers)

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
				switch event.button.button {
				case sdl2.BUTTON_LEFT:
					// place vertex at mouse location
					cx, cy: c.int
					sdl2.GetMouseState(&cx, &cy)
					glx := (f32(cx) / f32(window_width)) * 2 - 1
					gly := (1 - (f32(cy) / f32(window_height))) * 2 - 1
					fmt.printf("got mouse click at (%d, %d) (%.2f, %.2f)\n", cx, cy, glx, gly)
					add_vertex(&mesh, glx, gly)
				}
			}
		}

		gl.Viewport(0, 0, window_width, window_height)
		gl.ClearColor(0.25, 0.35, 0.5, 1.0)
		gl.Clear(gl.COLOR_BUFFER_BIT)

		if mesh.modified {
			update_buffers(tri_buffers, mesh.vertices[:], mesh.indices[:])
			update_buffers(point_buffers, mesh.vertices[:], mesh.point_indices[:])
			fmt.println(mesh.point_indices)
			mesh.modified = false
		}

		// Drawing is done back to front, so later things are drawn on top
		{
			start_draw(&tri_buffers)
			defer end_draw()
			gl.UseProgram(program2)
			gl.PolygonMode(gl.FRONT_AND_BACK, gl.FILL)
			gl.DrawElements(gl.TRIANGLES, i32(len(mesh.indices)), gl.UNSIGNED_SHORT, nil)
			gl.UseProgram(program1)
			gl.LineWidth(3)
			gl.PolygonMode(gl.FRONT_AND_BACK, gl.LINE)
			gl.DrawElements(gl.TRIANGLES, i32(len(mesh.indices)), gl.UNSIGNED_SHORT, nil)
		}
		{
			start_draw(&point_buffers)
			defer end_draw()
			gl.UseProgram(program1)
			gl.PointSize(10)
			gl.PolygonMode(gl.FRONT_AND_BACK, gl.POINT)
			gl.DrawElements(gl.POINTS, i32(len(mesh.point_indices)), gl.UNSIGNED_SHORT, nil)
		}

		sdl2.GL_SwapWindow(window)

		free_all(context.temp_allocator)
	}
}

create_buffers :: proc(vertices: []Vertex, indices: []u16) -> Buffers {
	// Vertex Array Object
	vao: u32
	gl.GenVertexArrays(1, &vao)
	gl.BindVertexArray(vao)
	defer gl.BindVertexArray(0)

	// Vertex Buffer Object
	vbo: u32
	gl.GenBuffers(1, &vbo)
	gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
	defer gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BufferData(
		gl.ARRAY_BUFFER,
		len(vertices) * size_of(vertices[0]),
		raw_data(vertices),
		gl.DYNAMIC_DRAW,
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
	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo)
	defer gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0)
	gl.BufferData(
		gl.ELEMENT_ARRAY_BUFFER,
		len(indices) * size_of(indices[0]),
		raw_data(indices),
		gl.DYNAMIC_DRAW,
	)

	return Buffers{vao, vbo, ebo}
}

update_buffers :: proc(buffers: Buffers, vertices: []Vertex, indices: []u16) {
	{
		gl.BindBuffer(gl.ARRAY_BUFFER, buffers.vbo)
		defer gl.BindBuffer(gl.ARRAY_BUFFER, 0)
		gl.BufferData(
			gl.ARRAY_BUFFER,
			len(vertices) * size_of(vertices[0]),
			raw_data(vertices),
			gl.DYNAMIC_DRAW,
		)
	}
	{
		gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, buffers.ebo)
		defer gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0)
		gl.BufferData(
			gl.ELEMENT_ARRAY_BUFFER,
			len(indices) * size_of(indices[0]),
			raw_data(indices[:]),
			gl.DYNAMIC_DRAW,
		)
	}
}

start_draw :: proc "contextless" (buffers: ^Buffers) {
	gl.BindVertexArray(buffers.vao)
	gl.BindBuffer(gl.ARRAY_BUFFER, buffers.vbo)
	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, buffers.ebo)
}
end_draw :: proc "contextless" () {
	gl.BindVertexArray(0)
	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0)
}

delete_buffers :: proc(buffers: ^Buffers) {
	gl.DeleteVertexArrays(1, &buffers.vao)
	gl.DeleteBuffers(1, &buffers.vbo)
	gl.DeleteBuffers(1, &buffers.ebo)
}


vertex_source := `#version 330 core

layout(location=0) in vec3 aPos;

void main() {
	gl_Position = vec4(aPos, 1.0);
}
`

fragment_source1 := `#version 330 core

out vec4 FragColor;

void main() {
	FragColor = vec4(1.0, 0.5, 0.2, 1.0);
}
`

fragment_source2 := `#version 330 core

out vec4 FragColor;

void main() {
	vec3 c = vec3(1.0, 0.5, 0.2);
	c *= 0.75;
	FragColor = vec4(c.xyz, 1.0);
}
`
