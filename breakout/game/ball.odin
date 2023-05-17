package game

import glm "core:math/linalg/glsl"

Ball :: struct {
	pos:          glm.vec2,
	size:         glm.vec2,
	velocity:     glm.vec2,
	radius:       f32,
	stuck:        bool,
	sticky:       int,
	stuck_offset: glm.vec2,
	pass_through: int,
}

INIT_BALL_VELOCITY: glm.vec2 = {100, -350} * 1.4

ball_init :: proc(ball: ^Ball, paddle_pos, paddle_size: glm.vec2) {
	ball.radius = 20
	ball.size = ball.radius * 2
	ball_reset(ball, paddle_pos, paddle_size)
}
ball_reset :: proc(ball: ^Ball, paddle_pos, paddle_size: glm.vec2) {
	ball.stuck = true
	ball.sticky = 0
	ball.pass_through = 0
	ball.velocity = INIT_BALL_VELOCITY
	ball.stuck_offset.x = (paddle_size.x * .5) - ball.radius
	ball.stuck_offset.y = -ball.size.y
	ball_stuck_update(ball, paddle_pos)
}
ball_stick_on_collide :: proc(ball: ^Ball, paddle: ^Paddle) {
	ball.stuck = true
	ball.stuck_offset = ball.pos - paddle.pos
}
ball_stuck_update :: proc(ball: ^Ball, paddle_pos: glm.vec2) {
	ball.pos = paddle_pos + ball.stuck_offset
}

ball_update :: proc(
	ball: ^Ball,
	dt: f32,
	window_width, window_height: int,
	ball_released: bool,
) -> bool {
	if ball_released {
		ball.stuck = false
		ball.stuck_offset = {0, 0}
	}
	if ball.stuck {
		return false
	}
	ball.pos += ball.velocity * dt
	if ball.pos.x <= 0 {
		ball.velocity.x = -ball.velocity.x
		ball.pos.x = 0
		append(&event_q, EventCollide{type = .WALL, pos = ball.pos})
	} else if ball.pos.x + ball.size.x >= f32(window_width) {
		ball.velocity.x = -ball.velocity.x
		ball.pos.x = f32(window_width) - ball.size.x
		append(&event_q, EventCollide{type = .WALL, pos = ball.pos})
	}
	if ball.pos.y <= 0 {
		ball.velocity.y = -ball.velocity.y
		ball.pos.y = 0
		append(&event_q, EventCollide{type = .WALL, pos = ball.pos})
	}
	// this loses the game
	if ball.pos.y - ball.size.y >= f32(window_height) {
		return true
	}
	return false
}

check_collision_rect :: proc(p1, s1, p2, s2: glm.vec2) -> bool {
	x_collide := p1.x + s1.x >= p2.x && p2.x + s2.x >= p1.x
	y_collide := p1.y + s1.y >= p2.y && p2.y + s2.y >= p1.y
	return x_collide && y_collide
}

CollideType :: enum {
	NONE,
	WALL,
	BLOCK,
	SOLID_BLOCK,
	PADDLE,
}
CollideInfo :: struct {
	type:       CollideType,
	dir:        Direction,
	difference: glm.vec2,
}

check_collision_ball :: proc(
	ball_pos: glm.vec2,
	radius: f32,
	rect_pos, rect_size: glm.vec2,
	type: CollideType,
) -> CollideInfo {
	ball_center := ball_pos + radius
	rect_half := rect_size * .5
	rect_center := rect_pos + rect_half
	difference := ball_center - rect_center
	clamped := glm.clamp(difference, -rect_half, rect_half)
	closest := rect_center + clamped
	difference = closest - ball_center
	if glm.length_vec2(difference) < radius {
		return CollideInfo{type, vector_direction(difference), difference}
	} else {
		return CollideInfo{.NONE, .UP, {0, 0}}
	}
}

Direction :: enum {
	UP,
	RIGHT,
	DOWN,
	LEFT,
}

vector_direction :: proc(target: glm.vec2) -> Direction {
	compass: [4]glm.vec2 = {glm.vec2{0, 1}, glm.vec2{1, 0}, glm.vec2{0, -1}, glm.vec2{-1, 0}}
	max: f32 = 0
	best_match: int = -1
	for dir, i in compass {
		dot_product := glm.dot(glm.normalize(target), dir)
		if dot_product > max {
			max = dot_product
			best_match = i
		}
	}
	return Direction(best_match)
}

ball_handle_collision :: proc(ball: ^Ball, info: CollideInfo) {
	if info.type == .NONE || (ball.pass_through > 0 && info.type == .BLOCK) {
		return
	}
	// TODO: add some randomness to avoid ball getting stuck
	// ball.bounces += 1
	if info.dir == .LEFT || info.dir == .RIGHT {
		ball.velocity.x = -ball.velocity.x
		overlap := ball.radius - abs(info.difference.x)
		if info.dir == .LEFT {
			ball.pos.x += overlap
		} else {
			ball.pos.x -= overlap
		}
	} else {
		ball.velocity.y = -ball.velocity.y
		overlap := ball.radius - abs(info.difference.y)
		if info.dir == .UP {
			ball.pos.y -= overlap
		} else {
			ball.pos.y += overlap
		}
	}
}

ball_handle_paddle_collision :: proc(ball: ^Ball, paddle: ^Paddle, info: CollideInfo) {
	if ball.stuck || info.type == .NONE {
		return
	}
	center_paddle := paddle.pos.x + (paddle.size.x * .5)
	distance := (ball.pos.x + ball.radius) - center_paddle
	percentage := distance / (paddle.size.x * .5)
	strength: f32 = 2
	old_velocity := ball.velocity
	ball.velocity.x = INIT_BALL_VELOCITY.x * percentage * strength
	ball.velocity.y = -1 * abs(ball.velocity.y) // always bounce up
	ball.velocity = glm.normalize(ball.velocity) * glm.length(old_velocity)
	if ball.sticky > 0 {
		ball_stick_on_collide(ball, paddle)
	}
}
