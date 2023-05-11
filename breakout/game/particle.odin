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

particle_count :: 500
new_particles_per_second :: 120
particles: [particle_count]Particle

particle_update :: proc(dt: f32, pos, vel, offset: glm.vec2) {
	for _, i in particles {
		p := &particles[i]
		p.life -= dt
		if p.life > 0 {
			p.pos -= p.vel * dt
			p.color.a -= dt * 2.5
		}
	}

	new_count: int = cast(int)math.round(new_particles_per_second * dt)

	for i := 0; i < new_count; i += 1 {
		p_index := particle_find_unused()
		particle_respawn(&particles[p_index], pos, vel, offset)
	}
}

last_used_particle: int = 0

particle_find_unused :: proc() -> int {
	for i := last_used_particle; i < len(particles); i += 1 {
		if particles[i].life <= 0 {
			last_used_particle = i
			return i
		}
	}
	for p, i in particles {
		if p.life <= 0 {
			last_used_particle = i
			return i
		}
	}
	last_used_particle = 0
	return 0
}

r := rand.Rand{}
r_seed: u64 = 123


particle_respawn :: proc(particle: ^Particle, source_pos, source_vel, offset: glm.vec2) {
	r_seed += 1
	rand.init(&r, r_seed)
	r_pos: f32 = (rand.float32(&r) * 17) - 7
	particle.pos = source_pos + r_pos + offset
	r_color := 0.75 + (rand.float32(&r) * 0.25)
	particle.color = glm.vec4{r_color, r_color, r_color, 1}
	r_scale := 10 + (rand.float32(&r) * 10)
	particle.scale = r_scale
	particle.life = 1
	particle.vel = source_vel * .1
}

particles_render :: proc(program_id: u32, texture_id: u32, vao: u32) {
	// gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE)
	gl.UseProgram(program_id)
	for p in particles {
		if p.life <= 0 {
			continue
		}
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
}
