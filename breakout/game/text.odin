package game

import "core:os"
import "core:fmt"
import "core:math"
import glm "core:math/linalg/glsl"

import gl "vendor:OpenGL"
import tt "vendor:stb/truetype"


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
	gl.DeleteProgram(w.shader_id)
}
debug := true
write_text :: proc(w: ^Writer, text: string, pos: glm.vec2, color: glm.vec3) {
	gl.UseProgram(w.shader_id)
	gl.Uniform3f(gl.GetUniformLocation(w.shader_id, "textColor"), color.x, color.y, color.z)
	gl.ActiveTexture(gl.TEXTURE0)
	gl.BindVertexArray(w.vao);defer gl.BindVertexArray(0)
	defer gl.BindTexture(gl.TEXTURE_2D, 0)

	// iterate through all characters
	x := pos.x
	ch: Character
	ok: bool
	defer {
		if debug do fmt.println()
		debug = false
	}
	for c, i in text {
		if ch, ok = w.chars[c]; !ok do continue

		xpos: f32 = x + f32(ch.bearing.x)
		ypos: f32 = pos.y + f32(w.ascent + ch.bearing.y)
		wi: f32 = f32(ch.size.x)
		h: f32 = f32(ch.size.y)
		vertices: [6]Vertex = {
			{{xpos, ypos + h}, {0, 1}},
			{{xpos + wi, ypos}, {1, 0}},
			{{xpos, ypos}, {0, 0}},
			{{xpos, ypos + h}, {0, 1}},
			{{xpos + wi, ypos + h}, {1, 1}},
			{{xpos + wi, ypos}, {1, 0}},
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
