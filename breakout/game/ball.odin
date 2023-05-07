package game

import glm "core:math/linalg/glsl"

Ball :: struct {
	pos:      glm.vec2,
	size:     glm.vec2,
	velocity: glm.vec2,
	radius:   f32,
	stuck:    bool,
}

ball_init :: proc(ball: ^Ball, window_width, window_height: int, paddle_top: f32) {
	ball.radius = 12.5
	ball.size = ball.radius * 2
	ball.pos = {(f32(window_width) * .5) - ball.radius, paddle_top - ball.size.y}
	ball.velocity = {4, -7}
	ball.velocity *= .5
	ball.stuck = true
}

ball_stuck_update :: proc(ball: ^Ball, paddle_pos, paddle_size: glm.vec2) {
	ball.pos = paddle_pos
	ball.pos.y -= ball.size.y
	ball.pos.x += (paddle_size.x * .5) - ball.radius
}

ball_update :: proc(ball: ^Ball, dt: f32, window_width, window_height: int, ball_released: bool) {
	if ball_released {
		ball.stuck = false
	}
	if ball.stuck {
		return
	}
	ball.pos += ball.velocity * dt
	if ball.pos.x <= 0 {
		ball.velocity.x = -ball.velocity.x
		ball.pos.x = 0
	} else if ball.pos.x + ball.size.x >= f32(window_width) {
		ball.velocity.x = -ball.velocity.x
		ball.pos.x = f32(window_width) - ball.size.x
	}
	if ball.pos.y <= 0 {
		ball.velocity.y = -ball.velocity.y
		ball.pos.y = 0
	}
	// temp, this would lose the game
	if ball.pos.y + ball.size.y >= f32(window_height) {
		ball.velocity.y = -ball.velocity.y
		ball.pos.y = f32(window_height) - ball.size.y
	}
}

check_collision :: proc(p1, s1, p2, s2: glm.vec2) -> bool {
	x_collide := p1.x + s1.x >= p2.x && p2.x + s2.x >= p1.x
	y_collide := p1.y + s1.y >= p2.y && p2.y + s2.y >= p1.y
	return x_collide && y_collide
}
