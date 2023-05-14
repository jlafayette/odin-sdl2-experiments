package game

import "core:fmt"
import "core:strings"
import "core:math/rand"
import glm "core:math/linalg/glsl"

PowerupType :: enum {
	SPEED,
	STICKY,
	PASS_THROUGH,
	PADDLE_SIZE_INCREASE,
	CONFUSE,
	CHAOS,
}
powerup_textures: [6]cstring = {
	"breakout/textures/powerup_speed.png",
	"breakout/textures/powerup_sticky.png",
	"breakout/textures/powerup_passthrough.png",
	"breakout/textures/powerup_increase.png",
	"breakout/textures/powerup_confuse.png",
	"breakout/textures/powerup_chaos.png",
}
powerup_colors: [6]glm.vec3 = {
	{0.5, 0.5, 1.0},
	{1.0, 0.5, 1.0},
	{.5, 1, .5},
	{1, .6, .4},
	{1, .3, .3},
	{.9, .25, .25},
}
powerup_durations: [6]f32 = {30, 20, 10, 30, 15, 15}

Powerup :: struct {
	type:      PowerupType,
	pos:       glm.vec2,
	size:      glm.vec2,
	velocity:  glm.vec2,
	duration:  f32,
	activated: bool,
	destroyed: bool,
}

Powerups :: struct {
	data:        [dynamic]Powerup,
	rand:        rand.Rand,
	texture_ids: [6]u32,
}
powerups_init :: proc(p: ^Powerups, program_id: u32, projection: glm.mat4) -> bool {
	ok := reserve_dynamic_array(&p.data, 20)
	rand.init(&p.rand, 987)
	for i := 0; i < len(p.texture_ids); i += 1 {
		tex := sprite_texture(powerup_textures[i], program_id, projection)
		p.texture_ids[i] = tex.id
	}
	return ok
}
powerups_destroy :: proc(p: ^Powerups) {
	delete(p.data)
}

powerup_spawn :: proc(p: ^Powerups, pos: glm.vec2) {
	r := rand.float32(&p.rand)
	if r > 0.5 {
		r = 0.05
	}
	// r *= 0.24
	pu: Maybe(Powerup)
	switch r {
	case 0.00 ..< 0.02:
		pu = Powerup {
			type = .SPEED,
		}
	case 0.02 ..< 0.04:
		pu = Powerup {
			type = .STICKY,
		}
	case 0.04 ..< 0.06:
		pu = Powerup {
			type = .PASS_THROUGH,
		}
	case 0.06 ..< 0.08:
		pu = Powerup {
			type = .PADDLE_SIZE_INCREASE,
		}
	case 0.08 ..< 0.10:
		pu = Powerup {
			type = .CONFUSE,
		}
	case 0.10 ..< 0.12:
		pu = Powerup {
			type = .CHAOS,
		}
	}
	powerup, ok := pu.?
	if ok {
		powerup.duration = powerup_durations[powerup.type]
		powerup.pos = pos
		powerup.size = {100, 25}
		powerup.velocity = {0, 100}
		append(&p.data, powerup)
		fmt.printf("spawned powerup: %v  ", powerup.type)
		powerup_report(p)
	}
}
powerup_report :: proc(p: ^Powerups) {
	b: strings.Builder
	strings.builder_init_len_cap(&b, 0, 512, context.temp_allocator)
	fmt.sbprintf(&b, "%d  (", len(p.data))
	for pu in p.data {
		fmt.sbprintf(&b, "%.2f ", pu.duration)
	}
	fmt.sbprint(&b, ")\n")
	fmt.print(strings.to_string(b))
}
powerups_update :: proc(p: ^Powerups, dt: f32, height: int) {
	for _, i in p.data {
		pu: ^Powerup = &p.data[i]
		pu.pos += pu.velocity * dt
		if pu.activated {
			pu.duration -= dt
			if pu.duration <= 0 {
				pu.activated = false
				append(&event_q, EventPowerupDeactivated{type = pu.type})
			}
		}
		if pu.pos.y - pu.size.y >= f32(height) {
			pu.destroyed = true
		}
	}
	for i := len(p.data) - 1; i >= 0; i -= 1 {
		pu := p.data[i]
		if pu.destroyed && !pu.activated {
			unordered_remove(&p.data, i)
		}
	}
}
powerups_handle_collision :: proc(p: ^Powerups, paddle: ^Paddle, pu_i: int) {
	pu: ^Powerup = &p.data[pu_i]
	pu.activated = true
	pu.destroyed = true
	append(&event_q, EventPowerupActivated{type = pu.type})
}
powerups_render :: proc(p: ^Powerups, program_id: u32, vao: u32) {
	for pu in p.data {
		if pu.destroyed do continue
		draw_sprite(
			program_id,
			p.texture_ids[pu.type],
			vao,
			pu.pos,
			pu.size,
			0,
			powerup_colors[pu.type],
		)
	}
}
