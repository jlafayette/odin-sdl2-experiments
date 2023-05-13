package game

import "core:fmt"
import glm "core:math/linalg/glsl"

import gl "vendor:OpenGL"

PPVertex :: struct {
	pos: glm.vec2,
	tex: glm.vec2,
}
PostProcessor :: struct {
	msfbo:      u32,
	fbo:        u32,
	rbo:        u32,
	vao:        u32,
	width:      i32,
	height:     i32,
	texture:    Texture2D,
	program_id: u32,
	confuse:    bool,
	chaos:      bool,
	shake:      bool,
}
post_processor_init :: proc(
	p: ^PostProcessor,
	program_id: u32,
	window_width: i32,
	window_height: i32,
) -> bool {
	p.width = window_width
	p.height = window_height
	p.program_id = program_id
	gl.GenFramebuffers(1, &p.msfbo)
	gl.GenFramebuffers(1, &p.fbo)
	gl.GenRenderbuffers(1, &p.rbo)
	// init render buffer storage with multisampled color buffer
	gl.BindFramebuffer(gl.FRAMEBUFFER, p.msfbo)
	gl.BindRenderbuffer(gl.RENDERBUFFER, p.rbo)
	// allocate storage for render buffer object
	max_samples: i32
	gl.GetIntegerv(gl.MAX_SAMPLES, &max_samples)
	fmt.printf("max samples: %d\n", max_samples)
	gl.RenderbufferStorageMultisample(gl.RENDERBUFFER, 4, gl.RGB, window_width, window_height)
	// attach MS render buffer object to framebuffer
	gl.FramebufferRenderbuffer(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.RENDERBUFFER, p.rbo)
	if gl.CheckFramebufferStatus(gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE {
		fmt.eprintln("Error: post-processor failed to init MSFBO")
		return false
	}
	// init the FBO/texture to blit mutisampled color-buffer to
	// (used for shader operations for postprocessing effects)
	{
		gl.BindFramebuffer(gl.FRAMEBUFFER, p.fbo);defer gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
		p.texture = generate_texture(window_width, window_height)
		// attach texture to framebuffer as its color attachment
		gl.FramebufferTexture2D(
			gl.FRAMEBUFFER,
			gl.COLOR_ATTACHMENT0,
			gl.TEXTURE_2D,
			p.texture.id,
			0,
		)
		if gl.CheckFramebufferStatus(gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE {
			fmt.eprintln("Error: post-processor failed to init FBO")
			return false
		}
	}
	// initialize render data and uniforms
	{
		vbo: u32
		vertices: [6]PPVertex = {
			{{-1, -1}, {0, 0}},
			{{1, 1}, {1, 1}},
			{{-1, 1}, {0, 1}},
			{{-1, -1}, {0, 0}},
			{{1, -1}, {1, 0}},
			{{1, 1}, {1, 1}},
		}
		gl.GenVertexArrays(1, &p.vao)
		gl.GenBuffers(1, &vbo)
		gl.BindBuffer(gl.ARRAY_BUFFER, vbo);defer gl.BindBuffer(gl.ARRAY_BUFFER, 0)
		gl.BufferData(gl.ARRAY_BUFFER, size_of(vertices), raw_data(vertices[:]), gl.STATIC_DRAW)

		gl.BindVertexArray(p.vao);defer gl.BindVertexArray(0)
		gl.EnableVertexAttribArray(0)
		gl.VertexAttribPointer(0, 2, gl.FLOAT, false, size_of(PPVertex), offset_of(PPVertex, pos))
		gl.EnableVertexAttribArray(1)
		gl.VertexAttribPointer(1, 2, gl.FLOAT, false, size_of(PPVertex), offset_of(PPVertex, tex))
	}
	// shader set int "scene", 0 , true
	gl.UseProgram(program_id)
	gl.Uniform1i(gl.GetUniformLocation(program_id, "scene"), 0)
	offset: f32 = 1.0 / 300.0
	offsets: [9][2]f32 = {
		{-offset, offset},
		{0, offset},
		{offset, offset},
		{-offset, 0},
		{0, 0},
		{offset, 0},
		{-offset, -offset},
		{0, -offset},
		{offset, -offset},
	}
	gl.Uniform2fv(gl.GetUniformLocation(program_id, "offsets"), 9, &offsets[0][0])
	edge_kernel: [9]i32 = {-1, -1, -1, -1, 8, -1, -1, -1, -1}
	gl.Uniform1iv(gl.GetUniformLocation(program_id, "edge_kernel"), 9, &edge_kernel[0])
	blur_kernel: [9]f32 = {
		1.0 / 16.0,
		2.0 / 16.0,
		1.0 / 16.0,
		2.0 / 16.0,
		4.0 / 16.0,
		2.0 / 16.0,
		1.0 / 16.0,
		2.0 / 16.0,
		1.0 / 16.0,
	}
	gl.Uniform1fv(gl.GetUniformLocation(program_id, "blur_kernel"), 9, &blur_kernel[0])

	return true
}
@(private = "file")
generate_texture :: proc(width, height: i32) -> Texture2D {
	tex: Texture2D
	tex.width = width
	tex.height = height
	gl.GenTextures(1, &tex.id)

	gl.BindTexture(gl.TEXTURE_2D, tex.id);defer gl.BindTexture(gl.TEXTURE_2D, 0)
	internal_format: i32 = gl.RGB
	image_format: u32 = gl.RGB
	gl.TexImage2D(
		gl.TEXTURE_2D,
		0,
		internal_format,
		tex.width,
		tex.height,
		0,
		image_format,
		gl.UNSIGNED_BYTE,
		nil,
	)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)

	return tex
}
post_processor_begin_render :: proc(p: ^PostProcessor) {
	gl.BindFramebuffer(gl.FRAMEBUFFER, p.msfbo)
	gl.ClearColor(0, 0, 0, 1)
	gl.Clear(gl.COLOR_BUFFER_BIT)
}
post_processor_end_render :: proc(p: ^PostProcessor) {
	// now resolve multisampled color-buffer into intermediate FBO to
	// store to texture
	gl.BindFramebuffer(gl.READ_FRAMEBUFFER, p.msfbo)
	gl.BindFramebuffer(gl.DRAW_FRAMEBUFFER, p.fbo)
	// binds both READ and WRITE framebuffer to default framebuffer
	defer gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
	gl.BlitFramebuffer(
		0,
		0,
		p.width,
		p.height,
		0,
		0,
		p.width,
		p.height,
		gl.COLOR_BUFFER_BIT,
		gl.NEAREST,
	)
}
post_processor_render :: proc(p: ^PostProcessor, time: f32) {
	// set uniforms/options
	gl.UseProgram(p.program_id)
	gl.Uniform1f(gl.GetUniformLocation(p.program_id, "time"), time)
	gl.Uniform1i(gl.GetUniformLocation(p.program_id, "confuse"), i32(p.confuse))
	gl.Uniform1i(gl.GetUniformLocation(p.program_id, "chaos"), i32(p.chaos))
	gl.Uniform1i(gl.GetUniformLocation(p.program_id, "shake"), i32(p.shake))
	// render textured quad
	gl.ActiveTexture(gl.TEXTURE0)
	gl.BindTexture(gl.TEXTURE_2D, p.texture.id)
	gl.BindVertexArray(p.vao);defer gl.BindVertexArray(0)
	gl.DrawArrays(gl.TRIANGLES, 0, 6)
}
