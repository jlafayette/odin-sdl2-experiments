package game

import "core:fmt"
import "core:strings"
import glm "core:math/linalg/glsl"

import gl "vendor:OpenGL"
import "vendor:stb/image"


SpriteBuffers :: struct {
	vbo: u32,
	vao: u32,
}
SpriteVertex :: struct {
	pos: glm.vec2,
	tex: glm.vec2,
}
sprite_vertices := []SpriteVertex{
	{{0, 1}, {0, 1}},
	{{1, 0}, {1, 0}},
	{{0, 0}, {0, 0}},
	{{0, 1}, {0, 1}},
	{{1, 1}, {1, 1}},
	{{1, 0}, {1, 0}},
}
sprite_buffers_init :: proc() -> SpriteBuffers {
	vbo, vao: u32

	gl.GenVertexArrays(1, &vao)
	gl.GenBuffers(1, &vbo)
	gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
	gl.BufferData(
		gl.ARRAY_BUFFER,
		len(sprite_vertices) * size_of(sprite_vertices[0]),
		raw_data(sprite_vertices),
		gl.STATIC_DRAW,
	)
	gl.BindVertexArray(vao)
	gl.EnableVertexAttribArray(0)
	gl.EnableVertexAttribArray(1)
	gl.VertexAttribPointer(
		0,
		2,
		gl.FLOAT,
		false,
		size_of(SpriteVertex),
		offset_of(SpriteVertex, pos),
	)
	gl.VertexAttribPointer(
		1,
		2,
		gl.FLOAT,
		false,
		size_of(SpriteVertex),
		offset_of(SpriteVertex, tex),
	)

	return SpriteBuffers{vbo, vao}
}
sprite_buffers_destroy :: proc(buffers: ^SpriteBuffers) {
	gl.DeleteBuffers(1, &buffers.vbo)
	gl.DeleteVertexArrays(1, &buffers.vao)
}

Texture2D :: struct {
	id:     u32,
	width:  i32,
	height: i32,
}
sprite_texture :: proc(filename: cstring, sprite_program: u32, projection: glm.mat4) -> Texture2D {
	tex: Texture2D
	gl.GenTextures(1, &tex.id)
	nr_channels: i32
	data := image.load(filename, &tex.width, &tex.height, &nr_channels, 0)
	internal_format: i32 = gl.RGB
	image_format: u32 = gl.RGB
	if nr_channels == 4 {
		internal_format = gl.RGBA
		image_format = gl.RGBA
	}
	defer image.image_free(data)
	fmt.println("w:", tex.width, "h:", tex.height, "channels:", nr_channels)
	gl.BindTexture(gl.TEXTURE_2D, tex.id);defer gl.BindTexture(gl.TEXTURE_2D, 0)
	gl.TexImage2D(
		gl.TEXTURE_2D,
		0,
		internal_format,
		tex.width,
		tex.height,
		0,
		image_format,
		gl.UNSIGNED_BYTE,
		data,
	)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)

	gl.UseProgram(sprite_program)
	gl.Uniform1i(gl.GetUniformLocation(sprite_program, "image"), 0)
	proj := projection
	gl.UniformMatrix4fv(gl.GetUniformLocation(sprite_program, "projection"), 1, false, &proj[0, 0])
	return tex
}

draw_sprite :: proc(
	program_id: u32,
	texture_id: u32,
	vao: u32,
	pos, size: glm.vec2,
	rotate: f32,
	color: glm.vec3,
) {
	gl.UseProgram(program_id)
	model := glm.mat4(1)
	model = model * glm.mat4Translate({pos.x, pos.y, 0})
	model = model * glm.mat4Translate({.5 * size.x, .5 * size.y, 0})
	model = model * glm.mat4Rotate({0, 0, 1}, glm.radians(rotate))
	model = model * glm.mat4Translate({-.5 * size.x, -.5 * size.y, 0})
	model = model * glm.mat4Scale({size.x, size.y, 1})

	gl.UniformMatrix4fv(gl.GetUniformLocation(program_id, "model"), 1, false, &model[0, 0])
	c := color
	gl.Uniform3fv(gl.GetUniformLocation(program_id, "spriteColor"), 1, &c[0])
	gl.ActiveTexture(gl.TEXTURE0)
	gl.BindTexture(gl.TEXTURE_2D, texture_id)

	gl.BindVertexArray(vao);defer gl.BindVertexArray(0)

	// needed for alpha channel to work
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	gl.DrawArrays(gl.TRIANGLES, 0, 6)
}
