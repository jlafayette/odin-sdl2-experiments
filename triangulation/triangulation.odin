package triangulation
// TRACY_ENABLE :: #config(TRACY_ENABLE, false)

import "core:c"
import "core:os"
import "core:fmt"
import "core:mem"
import "core:path/filepath"
import "core:slice"
import "core:time"
import "core:strings"
import "core:strconv"
import "core:math/rand"
import "core:math/linalg/glsl"
import "vendor:sdl2"
import gl "vendor:OpenGL"

// import tracy "../../../odin-tracy"
import "delaunay"
import "timer"
import "snapshot"
import "benchmark"


Vertex :: struct {
	pos:   glsl.vec3,
	sel:   f32,
	hover: f32,
}
Sel :: union {
	u16,
}

Mesh :: struct {
	vertices:      [dynamic]Vertex,
	indices:       [dynamic]u16,
	point_indices: [dynamic]u16,
	selected:      Sel,
	modified:      bool,
	seed:          u64,
}
Buffers :: struct {
	vao: u32,
	vbo: u32,
	ebo: u32,
}

MAX_VERTICES :: 1200

init_mesh :: proc(mesh: ^Mesh) {
	reserve_dynamic_array(&mesh.vertices, MAX_VERTICES)
	append(
		&mesh.vertices,
		Vertex{{+0.53, +0.51, 0.0}, 0, 0},
		Vertex{{+0.56, -0.52, 0.0}, 0, 0},
		Vertex{{-0.58, -0.54, 0.0}, 0, 0},
	)
	reserve_dynamic_array(&mesh.point_indices, MAX_VERTICES)
	reserve_dynamic_array(&mesh.indices, MAX_VERTICES * 3)
	add_vertex(mesh, -0.5, +0.55)
	mesh.modified = true
}
add_vertex :: proc(mesh: ^Mesh, x, y: f32) {
	if len(mesh.vertices) >= MAX_VERTICES {
		fmt.println("ERROR: max vertices count reached", MAX_VERTICES)
		return
	}
	append(&mesh.vertices, Vertex{{x, y, 0.0}, 0, 0})
	update_triangulation(mesh)
	mesh_update_hover(mesh, {x, y})
}
random_vertices :: proc(mesh: ^Mesh, count: int) {
	r := rand.Rand{}
	mesh.seed += 1
	rand.init(&r, mesh.seed)
	clear_dynamic_array(&mesh.vertices)
	for i := 0; i < count; i += 1 {
		pos: glsl.vec3 = {
			rand.float32(&r) * 2 - 1,
			rand.float32(&r) * 2 - 1,
			rand.float32(&r) * 2 - 1,
		}
		append(&mesh.vertices, Vertex{pos, 0, 0})
	}

	update_triangulation(mesh)
}
update_triangulation :: proc(mesh: ^Mesh) {
	clear_dynamic_array(&mesh.point_indices)
	for _, i in mesh.vertices {
		append(&mesh.point_indices, u16(i))
	}

	points := make([dynamic]delaunay.Point, 0, len(mesh.vertices) + 3)
	defer delete(points)
	for vertex in mesh.vertices {
		append(&points, delaunay.Point(vertex.pos.xy))
	}

	point_slice, tri_slice := delaunay.triangulate(&points)
	defer delete(tri_slice)

	clear_dynamic_array(&mesh.indices)
	nv := len(point_slice)
	for tri in tri_slice {
		append(&mesh.indices, u16(tri.x), u16(tri.y), u16(tri.z))
	}

	mesh.modified = true
}
mesh_set_hover :: proc(mesh: ^Mesh, i: u16) {
	switch sel_i in mesh.selected {
	case u16:
		if sel_i == i {
			return
		}
		mesh.vertices[sel_i].sel = 0
		mesh.vertices[sel_i].hover = 0
	}
	mesh.selected = i
	mesh.vertices[i].sel = 0
	mesh.vertices[i].hover = 1
	mesh.modified = true
}
mesh_set_selected :: proc(mesh: ^Mesh, value: bool) {
	switch sel_i in mesh.selected {
	case u16:
		vfloat: f32 = 0
		if value do vfloat = 1
		mesh.vertices[sel_i].sel = vfloat
		mesh.modified = true
	}
}
mesh_update_hover :: proc(mesh: ^Mesh, mouse_pos: [2]f32) {
	closest_i: int = -1
	closest_dist: f32 = 9999999
	for v, i in mesh.vertices {
		d := dist_squared(mouse_pos, v.pos.xy)
		if d < closest_dist {
			closest_i = i
			closest_dist = d
		}
	}
	if closest_i >= 0 {
		mesh_set_hover(mesh, cast(u16)closest_i)
	}
}
mesh_update_mouse_drag :: proc(mesh: ^Mesh, mouse_pos: [2]f32) {
	switch sel_i in mesh.selected {
	case u16:
		mesh.vertices[sel_i].pos.xy = mouse_pos
	}
	update_triangulation(mesh)
}

destroy_mesh :: proc(mesh: ^Mesh) {
	delete(mesh.vertices)
	delete(mesh.indices)
	delete(mesh.point_indices)
}


main :: proc() {
	args := os.args[1:]
	mem_check := slice.contains(args, "-mem-check") || slice.contains(args, "-m")
	if mem_check {
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
	// tracy.SetThreadName("main")
	// context.allocator = tracy.MakeProfiledAllocator(
	// 	self = &tracy.ProfiledAllocatorData{},
	// 	callstack_size = 20,
	// 	backing_allocator = context.allocator,
	// 	secure = true,
	// )
	// when TRACY_ENABLE {
	// 	fmt.println("tracy is enabled!")
	// }

	args := os.args[1:]
	test := slice.contains(args, "-test") || slice.contains(args, "-t")

	if test {
		iterations := 50
		for arg, i in args {
			if arg == "-iter" || arg == "-i" {
				ok: bool
				iterations, ok = strconv.parse_int(args[i + 1])
				assert(ok, "Failed to parse number of iterations")
				break
			}
		}

		save_snapshot := slice.contains(args, "-save-snapshot") || slice.contains(args, "-ss")
		check_snapshot := slice.contains(args, "-check-snapshot") || slice.contains(args, "-cs")
		if save_snapshot && check_snapshot {
			fmt.eprintln(
				"ERROR: cannot enable options to save and check snapshots in the same run",
			)
			return
		}

		save_benchmark := slice.contains(args, "-save-benchmark") || slice.contains(args, "-b")

		// Vertices
		mesh := Mesh{}
		init_mesh(&mesh)
		defer destroy_mesh(&mesh)

		vertex_count := 1000
		t := timer.Timer{}
		timer.init(&t, vertex_count, iterations)
		defer timer.destroy(&t)

		for i := 0; i < iterations; i += 1 {
			// defer tracy.FrameMark()

			// copied from random_vertices procedure but split apart so we
			// aren't timing the random generation part
			r := rand.Rand{}
			mesh.seed = cast(u64)i
			rand.init(&r, mesh.seed)
			clear_dynamic_array(&mesh.vertices)
			for i := 0; i < vertex_count; i += 1 {
				pos: glsl.vec3 = {
					rand.float32(&r) * 2 - 1,
					rand.float32(&r) * 2 - 1,
					rand.float32(&r) * 2 - 1,
				}
				append(&mesh.vertices, Vertex{pos, 0, 0})
			}

			timer.start(&t, vertex_count)
			update_triangulation(&mesh)
			timer.stop(&t)
			fmt.print(".") // so we have something to indicate progress
			if save_snapshot {

				path := snapshot.path()
				defer delete(path)
				if err := snapshot.ensure_path_exists(path); err != os.ERROR_NONE {
					fmt.eprintln("ERROR creating directory", path, err)
					return
				}
				file := snapshot.file(path, vertex_count, i)
				defer delete(file)

				tris := make([dynamic]snapshot.I_Triangle, 0, len(mesh.indices) / 3)
				defer delete(tris)
				for i := 0; i < len(mesh.indices); i += 3 {
					append(
						&tris,
						snapshot.I_Triangle{
							cast(int)mesh.indices[i],
							cast(int)mesh.indices[i + 1],
							cast(int)mesh.indices[i + 2],
						},
					)
				}
				snapshot.write_triangles(file, tris[:])
			}
			if check_snapshot {
				path := snapshot.path()
				defer delete(path)
				file := snapshot.file(path, vertex_count, i)
				defer delete(file)
				tris, ok := snapshot.read_triangles(file)
				if !ok {
					fmt.eprintf(
						"ERROR: snapshot file not found %s, try saving snapshots with -ss first",
						file,
					)
					return
				}
				defer delete(tris)
				actual_tris := make([dynamic]snapshot.I_Triangle, 0, len(mesh.indices) * 3)
				for j := 0; j < len(mesh.indices); j += 3 {
					i0 := cast(int)mesh.indices[j]
					i1 := cast(int)mesh.indices[j + 1]
					i2 := cast(int)mesh.indices[j + 2]
					tri := snapshot.I_Triangle{i0, i1, i2}
					append(&actual_tris, tri)
				}
				success := snapshot.compare(actual_tris[:], tris[:])
				if !success {
					fmt.eprintln("ERROR: results did not match saved snapshot")
					return
				}
			}
		}
		fmt.print("\n")
		timer.print(&t)

		// Write report for run
		if save_benchmark {
			ok := benchmark.write_report(&t)
			fmt.println("write ok:", ok)
		}
	} else {
		_open_window_and_run()
	}
}

_open_window_and_run :: proc() {
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

	// Vertices
	mesh := Mesh{}
	init_mesh(&mesh)
	defer destroy_mesh(&mesh)

	tri_buffers := create_buffers(mesh.vertices[:], mesh.indices[:])
	defer delete_buffers(&tri_buffers)
	point_buffers := create_buffers(mesh.vertices[:], mesh.point_indices[:])
	defer delete_buffers(&point_buffers)

	left_btn_clicked := false

	start_tick := time.tick_now()
	game_loop: for {
		// defer tracy.FrameMark()

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
			case .KEYDOWN:
				if event.key.keysym.sym == .R {
					random_vertices(&mesh, MAX_VERTICES - 100)
				}
			case .MOUSEMOTION:
				// currently selected is same as hover and only one point can be selected
				pos := gl_mouse_position(window_width, window_height)
				if left_btn_clicked {
					// if left button clicked, move selected to mouse position
					mesh_update_mouse_drag(&mesh, pos)
				} else {
					// update hover
					mesh_update_hover(&mesh, pos)
				}
			case .MOUSEBUTTONUP:
				switch event.button.button {
				case sdl2.BUTTON_LEFT:
					left_btn_clicked = false
				}
			case .MOUSEBUTTONDOWN:
				switch event.button.button {
				case sdl2.BUTTON_LEFT:
					left_btn_clicked = true
				// update selected if within hover range
				case sdl2.BUTTON_RIGHT:
					// place vertex at mouse location
					pos := gl_mouse_position(window_width, window_height)
					add_vertex(&mesh, pos.x, pos.y)
				}
			}
		}
		mesh_set_selected(&mesh, left_btn_clicked)

		gl.Viewport(0, 0, window_width, window_height)
		gl.ClearColor(0, 0, 0, 1.0)
		gl.Clear(gl.COLOR_BUFFER_BIT)

		if mesh.modified {
			update_buffers(tri_buffers, mesh.vertices[:], mesh.indices[:])
			update_buffers(point_buffers, mesh.vertices[:], mesh.point_indices[:])
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
			gl.LineWidth(1)
			gl.PolygonMode(gl.FRONT_AND_BACK, gl.LINE)
			gl.DrawElements(gl.TRIANGLES, i32(len(mesh.indices)), gl.UNSIGNED_SHORT, nil)
		}
		{
			start_draw(&point_buffers)
			defer end_draw()
			gl.UseProgram(program1)
			gl.PointSize(3)
			gl.PolygonMode(gl.FRONT_AND_BACK, gl.POINT)
			gl.DrawElements(gl.POINTS, i32(len(mesh.point_indices)), gl.UNSIGNED_SHORT, nil)
		}

		sdl2.GL_SwapWindow(window)

		free_all(context.temp_allocator)
	}
}

gl_mouse_position :: proc(window_width, window_height: i32) -> [2]f32 {
	cx, cy: c.int
	sdl2.GetMouseState(&cx, &cy)
	glx := (f32(cx) / f32(window_width)) * 2 - 1
	gly := (1 - (f32(cy) / f32(window_height))) * 2 - 1
	return {glx, gly}
}
dist_squared :: proc(p1, p2: [2]f32) -> f32 {
	dx := p1.x - p2.x
	dy := p1.y - p2.y
	return dx * dx + dy * dy
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
	// position attribute
	gl.VertexAttribPointer(0, 3, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, pos))
	gl.EnableVertexAttribArray(0)
	// selected attribute
	gl.VertexAttribPointer(1, 1, gl.FLOAT, true, size_of(Vertex), offset_of(Vertex, sel))
	gl.EnableVertexAttribArray(1)
	// hover attribute
	gl.VertexAttribPointer(2, 1, gl.FLOAT, true, size_of(Vertex), offset_of(Vertex, hover))
	gl.EnableVertexAttribArray(2)

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
layout(location=1) in float aSelected;
layout(location=2) in float aHover;

out float selected;
out float hover;

void main() {
	gl_Position = vec4(aPos, 1.0);
	selected = aSelected;
	hover = aHover;
}
`

fragment_source1 := `#version 330 core

out vec4 FragColor;

in float selected;
in float hover;

void main() {
	float rb = 1 - selected;
	vec4 c = vec4(rb, 1.0, rb, 1.0);
	FragColor = clamp(c, 0.0, 1.0);
}
`

fragment_source2 := `#version 330 core

out vec4 FragColor;

in float selected;
in float hover;

void main() {
	float rb = 1 - selected;
	vec3 c = vec3(rb, 1.0, rb);
	c *= (hover * 0.15) + 0.15 + (selected * 0.15);
	FragColor = vec4(c.xyz, 1.0);
}
`
