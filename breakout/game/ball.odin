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
	ball.pos = {f32(window_width) * .5, paddle_top - ball.radius}
	ball.velocity = {2, -7}
	ball.velocity *= .1
	ball.stuck = true
}

ball_stuck_update :: proc(ball: ^Ball, paddle_pos, paddle_size: glm.vec2) {
	paddle_top: f32 = paddle_pos.y - (paddle_size.y * .5)
	ball.pos = {paddle_pos.x, paddle_top - ball.radius}
}

ball_update :: proc(ball: ^Ball, dt: f32, window_width, window_height: int, ball_released: bool) {
	if ball_released {
		ball.stuck = false
	}
	if ball.stuck {
		return
	}
	ball.pos += ball.velocity * dt
	if ball.pos.x - ball.radius <= 0 {
		ball.velocity.x = -ball.velocity.x
		ball.pos.x = ball.radius
	} else if ball.pos.x + ball.radius >= f32(window_width) {
		ball.velocity.x = -ball.velocity.x
		ball.pos.x = f32(window_width) - ball.radius
	}
	if ball.pos.y - ball.radius <= 0 {
		ball.velocity.y = -ball.velocity.y
		ball.pos.y = ball.radius
	}
	// temp, this would lose the game
	if ball.pos.y + ball.size.y >= f32(window_height) {
		ball.velocity.y = -ball.velocity.y
		ball.pos.y = f32(window_height) - ball.size.y
	}
}

check_collision :: proc(ball: Ball, other_pos, other_size: glm.vec2) -> bool {
	p1 := ball.pos - ball.radius // (ball.size * .5)
	x_collide := p1.x + ball.size.x >= other_pos.x && other_pos.x + other_size.x >= p1.x
	y_collide := p1.y + ball.size.y >= other_pos.y && other_pos.y + other_size.y >= p1.y
	return x_collide && y_collide
}
