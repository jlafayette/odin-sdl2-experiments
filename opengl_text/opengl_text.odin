/* Text rendering following learnopengl tutorial

https://learnopengl.com/In-Practice/Text-Rendering

*/
package opengl_text

import "core:c"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"
import "core:math"
import glm "core:math/linalg/glsl"

import "vendor:sdl2"
import gl "vendor:OpenGL"
import tt "vendor:stb/truetype"
import "vendor:stb/image"


TERMINAL_TTF :: "dynamic_text/fonts/Terminal.ttf"


vertex_shader_src :: `#version 330 core
layout(location=0) in vec2 aPos;
layout(location=1) in vec2 aTex;
out vec2 TexCoords;

uniform mat4 projection;

void main() {
	gl_Position = projection * vec4(aPos, 0.0, 1.0);
	TexCoords = aTex;
}
`
fragment_shader_src :: `#version 330 core
in vec2 TexCoords;
out vec4 color;

uniform sampler2D text;
uniform vec3 textColor;

void main() {
	float t = texture(text, TexCoords).r;
	vec4 sampled = vec4(1.0, 1.0, 1.0, texture(text, TexCoords).r);
	color = vec4(textColor, 1.0) * sampled;
}
`

Character :: struct {
	texture_id: u32,
	size:       glm.ivec2,
	bearing:    glm.ivec2,
	advance:    i32,
}
Writer :: struct {
	info:      tt.fontinfo,
	scale:     f32,
	ascent:    i32,
	descent:   i32,
	line_gap:  i32,
	chars:     map[rune]Character,
	vao:       u32,
	vbo:       u32,
	shader_id: u32,
}
Vertex :: struct {
	pos: glm.vec2,
	tex: glm.vec2,
}
writer_init :: proc(w: ^Writer, ttf_file: string, height: f32, projection: glm.mat4) -> bool {
	data := os.read_entire_file_from_filename(ttf_file) or_return
	defer delete(data)

	info := &w.info
	ok := cast(bool)tt.InitFont(info, &data[0], 0)
	if !ok do return false

	scale := tt.ScaleForPixelHeight(info, height)
	ascent, descent, line_gap: i32
	tt.GetFontVMetrics(info, &ascent, &descent, &line_gap)
	ascent = cast(i32)math.round(f32(ascent) * scale)
	descent = cast(i32)math.round(f32(descent) * scale)
	line_gap = cast(i32)math.round(f32(line_gap) * scale)
	fmt.printf(
		"Writer height:%.2f, scale:%.2f, ascent:%d, descent:%d, line_gap:%d\n",
		height,
		scale,
		ascent,
		descent,
		line_gap,
	)

	reserve_map(&w.chars, 128)

	gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1) // disable byte-alignment restriction
	for i := 32; i < 128; i += 1 {
		// char width
		advance_width: i32
		left_side_bearing: i32
		tt.GetCodepointHMetrics(info, rune(i), &advance_width, &left_side_bearing)
		width, height, xoff, yoff: i32
		bitmap := tt.GetCodepointBitmap(info, scale, scale, rune(i), &width, &height, &xoff, &yoff)
		defer tt.FreeBitmap(bitmap, nil)

		/*
		// write to png, useful for debugging
		if i > 32 {
			buf: [32]byte
			s := fmt.bprintf(buf[:], "%d.png", i)
			cs_buf := buf[:len(s) + 1]
			cs := strings.unsafe_string_to_cstring(string(cs_buf))
			image.write_png(cs, i32(width), i32(height), 1, bitmap, i32(width))
		}
		*/

		texture: u32
		gl.GenTextures(1, &texture)
		gl.BindTexture(gl.TEXTURE_2D, texture)
		gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RED, width, height, 0, gl.RED, gl.UNSIGNED_BYTE, bitmap)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
		char := Character {
			texture_id = texture,
			size = {width, height},
			bearing = {xoff, yoff},
			advance = advance_width,
		}
		// if i > 32 {
		// 	fmt.printf(
		// 		"[%c] size: %v, bearing: %v, advance: %d\n",
		// 		rune(i),
		// 		char.size,
		// 		char.bearing,
		// 		char.advance,
		// 	)
		// }
		w.chars[rune(i)] = char
	}
	gl.BindTexture(gl.TEXTURE_2D, 0)
	w.scale = scale
	w.ascent = ascent
	w.descent = descent
	w.line_gap = line_gap

	shader_id: u32
	shader_id, ok = gl.load_shaders_source(vertex_shader_src, fragment_shader_src)
	assert(ok)
	gl.UseProgram(shader_id)
	proj := projection
	gl.UniformMatrix4fv(gl.GetUniformLocation(shader_id, "projection"), 1, false, &proj[0, 0])

	w.shader_id = shader_id

	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
	vao, vbo: u32
	gl.GenVertexArrays(1, &vao)
	gl.GenBuffers(1, &vbo)
	gl.BindVertexArray(vao);defer gl.BindVertexArray(0)
	gl.BindBuffer(gl.ARRAY_BUFFER, vbo);defer gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BufferData(gl.ARRAY_BUFFER, size_of(Vertex) * 6, nil, gl.DYNAMIC_DRAW)
	gl.EnableVertexAttribArray(0)
	gl.VertexAttribPointer(0, 2, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, pos))
	gl.EnableVertexAttribArray(1)
	gl.VertexAttribPointer(1, 2, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, tex))


	w.vao = vao
	w.vbo = vbo

	return true
}
writer_destroy :: proc(w: ^Writer) {
	delete(w.chars)
}
write_text :: proc(
	w: ^Writer,
	text: string,
	projection: glm.mat4,
	pos: glm.vec2,
	color: glm.vec3,
) {
	gl.UseProgram(w.shader_id)
	gl.Uniform3f(gl.GetUniformLocation(w.shader_id, "textColor"), color.x, color.y, color.z)
	gl.ActiveTexture(gl.TEXTURE0)
	gl.BindVertexArray(w.vao);defer gl.BindVertexArray(0)
	defer gl.BindTexture(gl.TEXTURE_2D, 0)

	// iterate through all characters
	x := pos.x
	ch: Character
	ok: bool
	for c, i in text {
		if ch, ok = w.chars[c]; !ok do continue

		xpos: f32 = x + f32(ch.bearing.x)
		ypos: f32 = pos.y - f32(ch.bearing.y) - f32(ch.size.y)
		ypos -= f32(w.descent) // raise text so 0,0 (bottom,left) still shows the entire text
		wi: f32 = f32(ch.size.x)
		h: f32 = f32(ch.size.y)
		vertices: [6]Vertex = {
			{{xpos, ypos + h}, {0, 0}},
			{{xpos, ypos}, {0, 1}},
			{{xpos + wi, ypos}, {1, 1}},
			{{xpos, ypos + h}, {0, 0}},
			{{xpos + wi, ypos}, {1, 1}},
			{{xpos + wi, ypos + h}, {1, 0}},
		}
		// render glyph texture over quad
		gl.BindTexture(gl.TEXTURE_2D, ch.texture_id)
		// update content of vbo memory
		gl.BindBuffer(gl.ARRAY_BUFFER, w.vbo)
		gl.BufferSubData(gl.ARRAY_BUFFER, 0, size_of(vertices), raw_data(vertices[:]))
		gl.BindBuffer(gl.ARRAY_BUFFER, 0)
		// render quad
		gl.DrawArrays(gl.TRIANGLES, 0, 6)

		// increment x
		x += f32(ch.advance) * w.scale
		if i < len(text) - 1 {
			next_i := text[i + 1]
			kern: i32
			kern = tt.GetCodepointKernAdvance(&w.info, rune(i), rune(next_i))
			x += math.round(f32(kern) * w.scale)
		}
	}
}
text_get_size :: proc(w: ^Writer, text: string) -> glm.vec2 {
	size: glm.vec2
	size.y = f32(w.ascent + math.abs(w.descent))
	ch: Character
	ok: bool
	for c, i in text {
		if ch, ok = w.chars[c]; !ok do continue
		if i < len(text) - 1 {
			size.x += f32(ch.advance) * w.scale
			next_i := text[i + 1]
			kern: i32
			kern = tt.GetCodepointKernAdvance(&w.info, rune(i), rune(next_i))
			size.x += math.round(f32(kern) * w.scale)
		} else {
			size.x += f32(ch.size.x)
		}
	}
	return size
}

run :: proc(window: ^sdl2.Window, window_width, window_height, refresh_rate: i32) {
	sdl2.GL_SetAttribute(.CONTEXT_PROFILE_MASK, i32(sdl2.GLprofile.CORE))
	sdl2.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 3)
	sdl2.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 3)
	gl_context := sdl2.GL_CreateContext(window)
	defer sdl2.GL_DeleteContext(gl_context)
	gl.load_up_to(3, 3, sdl2.gl_set_proc_address)

	// 0,0 is upper left (currently text is upside down using this projection)
	// projection: glm.mat4 = glm.mat4Ortho3d(0, f32(window_width), f32(window_height), 0, -1.0, 1)

	// 0,0 is lower left
	projection: glm.mat4 = glm.mat4Ortho3d(0, f32(window_width), 0, f32(window_height), -1.0, 1)

	writer: Writer
	writer_ok := writer_init(&writer, TERMINAL_TTF, 48, projection)
	assert(writer_ok)
	defer writer_destroy(&writer)

	writer16: Writer
	writer_ok = writer_init(&writer16, TERMINAL_TTF, 16, projection)
	assert(writer_ok)
	defer writer_destroy(&writer16)

	// timing stuff
	fps: f64 = 0
	target_ms_elapsed: f64 = 1000 / f64(refresh_rate)
	ms_elapsed: f64 = target_ms_elapsed
	target_dt: f64 = (1000 / f64(refresh_rate)) / 1000
	dt := f32(ms_elapsed / 1000)

	// game loop
	game_loop: for {
		start_tick := time.tick_now()
		dt = f32(ms_elapsed / 1000)

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

		// render
		gl.Viewport(0, 0, window_width, window_height)
		gl.ClearColor(0, .1, .2, 1)
		gl.Clear(gl.COLOR_BUFFER_BIT)
		col1: glm.vec3 = {.9, .4, .6}
		col2: glm.vec3 = {.1, .7, 1}
		write_text(&writer, "Xxgxph", projection, {0, 0}, col1)
		write_text(&writer, "Josh is the greatest!!", projection, {200, 700}, col1)
		write_text(&writer16, "Josh is the greatest!!", projection, {200, 800}, col2)
		write_text(&writer16, "JOSH IS THE GREATEST!!", projection, {200, 820}, col2)
		{
			text := "XxgxphxX"
			size := text_get_size(&writer, text)
			upper_right := glm.vec2{f32(window_width), f32(window_height)}
			pos := upper_right - size
			write_text(&writer, text, projection, pos, col1)
		}

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


_main :: proc(display_index: i32) {
	assert(sdl2.Init({.VIDEO}) == 0, sdl2.GetErrorString())
	defer sdl2.Quit()

	display_mode: sdl2.DisplayMode
	sdl2.GetCurrentDisplayMode(display_index, &display_mode)
	refresh_rate := display_mode.refresh_rate

	window_width: i32 = 1280
	window_height: i32 = 960

	window := sdl2.CreateWindow(
		"OpenGL Text Rendering",
		sdl2.WINDOWPOS_UNDEFINED_DISPLAY(display_index),
		sdl2.WINDOWPOS_UNDEFINED_DISPLAY(display_index),
		window_width,
		window_height,
		{.OPENGL, .ALLOW_HIGHDPI},
	)
	assert(window != nil, sdl2.GetErrorString())
	defer sdl2.DestroyWindow(window)

	fmt.printf("%dx%d %d\n", window_width, window_height, refresh_rate)

	run(window, window_width, window_height, refresh_rate)
}


main :: proc() {
	args := os.args[1:]
	display_index: i32 = 0
	if slice.contains(args, "-1") {
		// open window on second monitor
		display_index = 1
	}
	if slice.contains(args, "-m") || slice.contains(args, "--mem-track") {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		_main(display_index)

		for _, leak in track.allocation_map {
			fmt.printf("%v leaked %v bytes\n", leak.location, leak.size)
		}
		for bad_free in track.bad_free_array {
			fmt.printf("%v allocation %p was freed badly\n", bad_free.location, bad_free.memory)
		}
	} else {
		_main(display_index)
	}
}

gl_report_error :: proc() {
	e := gl.GetError()
	if e != gl.NO_ERROR {
		fmt.println("OpenGL Error:", e)
	}
}
