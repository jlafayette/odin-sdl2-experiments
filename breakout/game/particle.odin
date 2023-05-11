package game

import "core:math"
import "core:math/rand"
import glm "core:math/linalg/glsl"
import gl "vendor:OpenGL"

Particle :: struct {
	pos:   glm.vec2,
	vel:   glm.vec2,
	color: glm.vec4,
	scale: f32,
	life:  f32,
}

ParticleEmitter :: struct {
	particles:       []Particle,
	rate_per_second: int,
	last_used:       int,
	rand:            rand.Rand,
}
particle_emitter_init :: proc(e: ^ParticleEmitter, seed: u64) {
	rand.init(&e.rand, seed)
	e.particles = make([]Particle, 500)
	e.rate_per_second = 120
	fmt.printf("len particles: %d\n", len(e.particles))
}
particle_emitter_destroy :: proc(e: ^ParticleEmitter) {
	delete(e.particles)
}

particle_update :: proc(e: ^ParticleEmitter, dt: f32, pos, vel, offset: glm.vec2) {
	for _, i in e.particles {
		p := &e.particles[i]
		p.life -= dt
		if p.life > 0 {
			p.pos -= p.vel * dt
			p.color.a -= dt * 2.5
		}
	}

	new_count: int = cast(int)math.round(f32(e.rate_per_second) * dt)

	for i := 0; i < new_count; i += 1 {
		p_index := particle_find_unused(e)
		particle_respawn(&e.particles[p_index], &e.rand, pos, vel, offset)
	}
}

@(private = "file")
particle_find_unused :: proc(e: ^ParticleEmitter) -> int {
	for i := e.last_used; i < len(e.particles); i += 1 {
		if e.particles[i].life <= 0 {
			e.last_used = i
			return i
		}
	}
	for p, i in e.particles {
		if p.life <= 0 {
			e.last_used = i
			return i
		}
	}
	e.last_used = 0
	return 0
}

@(private = "file")
particle_respawn :: proc(
	particle: ^Particle,
	r: ^rand.Rand,
	source_pos, source_vel, offset: glm.vec2,
) {
	x := (rand.float32(r) * 10) - 5
	y := (rand.float32(r) * 10) - 5
	r_pos := glm.vec2{x, y}
	// r_pos: f32 = (rand.float32(r) * 17) - 7
	particle.pos = source_pos + r_pos + offset
	r_color := 0.75 + (rand.float32(r) * 0.25)
	particle.color = glm.vec4{r_color, r_color, r_color, 1}
	r_scale := 10 + (rand.float32(r) * 10)
	particle.scale = r_scale
	particle.life = 1
	particle.vel = source_vel * .1
}
import "core:fmt"

particles_render :: proc(e: ^ParticleEmitter, program_id: u32, texture_id: u32, vao: u32) {
	// gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE)
	gl.UseProgram(program_id)
	at_least_one := false
	for p in e.particles {
		if p.life <= 0 {
			continue
		}
		at_least_one = true
		pos := p.pos
		gl.Uniform2fv(gl.GetUniformLocation(program_id, "offset"), 1, &pos[0])
		col := p.color
		gl.Uniform4fv(gl.GetUniformLocation(program_id, "color"), 1, &col[0])
		scale := p.scale
		gl.Uniform1fv(gl.GetUniformLocation(program_id, "scale"), 1, &scale)
		gl.ActiveTexture(gl.TEXTURE0)
		gl.BindTexture(gl.TEXTURE_2D, texture_id)
		gl.BindVertexArray(vao);defer gl.BindVertexArray(0)
		gl.DrawArrays(gl.TRIANGLES, 0, 6)
	}
	if !at_least_one {
		fmt.print(":( ")
	}
}
