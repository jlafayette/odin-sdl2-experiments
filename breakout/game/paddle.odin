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

paddle_update :: proc(paddle: ^Paddle, dt: f32, window_width: int, is_left, is_right: bool) {
	// TODO: use dt

	// drag
	paddle.velocity *= 0.8
	if paddle.velocity < 1 && paddle.velocity > -1 {
		paddle.velocity = 0
	}
	// acceleration
	acc: f32 = 0
	if is_left do acc += -6
	if is_right do acc += 6
	paddle.velocity += acc

	// update
	paddle.pos.x += paddle.velocity
	paddle.pos.x = clamp(paddle.pos.x, 0, f32(window_width) - paddle.size.x)
}
