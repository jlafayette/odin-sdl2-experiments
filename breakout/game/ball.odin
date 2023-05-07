package game

import glm "core:math/linalg/glsl"

Ball :: struct {
	pos:      glm.vec2,
	size:     glm.vec2,
	velocity: glm.vec2,
	radius:   f32,
	stuck:    bool,
}
ball_init :: proc(ball: ^Ball, window_width, window_height: int) {
	ball.pos = {f32(window_width) * .5, f32(window_height) * .5}
	ball.radius = 12.5
	ball.size = ball.radius * 2
	ball.velocity = {2, -7}
	ball.velocity = {1, -3.5}
}

ball_update :: proc(ball: ^Ball, dt: f32, window_width, window_height: int) -> glm.vec2 {
	if ball.stuck {
		return ball.pos
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
	return ball.pos
}
