package game

import glm "core:math/linalg/glsl"

Paddle :: struct {
	pos:      glm.vec2,
	size:     glm.vec2,
	velocity: f32,
}
paddle_init :: proc(paddle: ^Paddle, window_width, window_height: int) {
	w: f32 = 250
	h: f32 = 50
	x := (f32(window_width) * .5) - (w * .5)
	y := f32(window_height) - h
	paddle.pos = {x, y}
	paddle.size = {w, h}
}
paddle_reset :: paddle_init

// Instant start and stop
paddle_update :: proc(paddle: ^Paddle, dt: f32, window_width: int, is_left, is_right: bool) {
	// pos += vel * dt

	max_vel: f32 = 800
	if (!is_left && !is_right) || (is_left && is_right) {
		paddle.velocity = 0
	} else {
		// acceleration
		acc: f32 = 0
		if is_left do acc = -max_vel
		if is_right do acc = max_vel
		paddle.velocity += acc
	}
	paddle.velocity = clamp(paddle.velocity, -max_vel, max_vel)

	// update
	paddle.pos.x += (paddle.velocity * dt)
	if paddle.pos.x <= 0 {
		paddle.velocity = 0
	} else if paddle.pos.x >= f32(window_width) - paddle.size.x {
		paddle.velocity = 0
	}
	paddle.pos.x = clamp(paddle.pos.x, 0, f32(window_width) - paddle.size.x)
}

// Gradual start and stop
// feels a bit mushy...
paddle_update2 :: proc(paddle: ^Paddle, dt: f32, window_width: int, is_left, is_right: bool) {

	// vel += acc * dt
	// pos += vel * dt

	max_acc: f32 = 7500
	if (!is_left && !is_right) || (is_left && is_right) {
		// apply drag
		if paddle.velocity > 0 {
			paddle.velocity -= max_acc * dt
		} else if paddle.velocity < 0 {
			paddle.velocity += max_acc * dt
		}
		if abs(paddle.velocity) < max_acc * dt {
			paddle.velocity = 0
		}
	} else {
		// acceleration
		acc: f32 = 0
		if is_left do acc = -max_acc
		if is_right do acc = max_acc
		paddle.velocity += acc * dt
	}
	max_vel: f32 = 800
	paddle.velocity = clamp(paddle.velocity, -max_vel, max_vel)

	// update
	paddle.pos.x += (paddle.velocity * dt)
	if paddle.pos.x <= 0 {
		paddle.velocity = 0
	} else if paddle.pos.x >= f32(window_width) - paddle.size.x {
		paddle.velocity = 0
	}
	paddle.pos.x = clamp(paddle.pos.x, 0, f32(window_width) - paddle.size.x)
}
