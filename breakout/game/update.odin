package game

game_update :: proc(g: ^Game, dt: f32) {
	paddle_update(&g.paddle, dt, g.window_width, g.is_left, g.is_right)
	ball_update(&g.ball, dt, g.window_width, g.window_height)
	if g.ball.stuck {
		ball_stuck_update(&g.ball, g.paddle.pos)
	}
	collide_info: CollideInfo
	no_blocks := true
	for brick, brick_i in g.level.bricks {
		if brick.destroyed {
			continue
		}
		collide_type: CollideType = .SOLID_BLOCK
		if !brick.is_solid {
			collide_type = .BLOCK
			no_blocks = false
		}
		collide_info = check_collision_ball(
			g.ball.pos,
			g.ball.radius,
			brick.pos,
			brick.size,
			collide_type,
		)
		if collide_info.type != .NONE {
			append(&event_q, EventCollide{type = .BRICK, pos = brick.pos, solid = brick.is_solid})
			ball_handle_collision(&g.ball, collide_info)
			if !brick.is_solid {
				g.level.bricks[brick_i].destroyed = true
			}
		}
	}
	if no_blocks {
		append(&event_q, EventLevelComplete{})
	}
	if !g.ball.stuck {
		collide_info = check_collision_ball(
			g.ball.pos,
			g.ball.radius,
			g.paddle.pos,
			g.paddle.size,
			.PADDLE,
		)
		if collide_info.type != .NONE {
			append(&event_q, EventCollide{type = .PADDLE, pos = g.paddle.pos})
			ball_handle_paddle_collision(&g.ball, &g.paddle, collide_info)
		}
	}
	// update powerups
	powerups_update(&g.powerups, dt, g.window_height)
	for pu, pu_i in g.powerups.data {
		if pu.activated || pu.destroyed {
			continue
		}
		collided := check_collision_rect(g.paddle.pos, g.paddle.size, pu.pos, pu.size)
		if collided {
			append(&event_q, EventCollide{type = .POWERUP, pos = pu.pos})
			powerups_handle_collision(&g.powerups, &g.paddle, pu_i)
		}
	}
	// update particles
	particle_update(&g.ball_sparks, dt, g.ball.pos, g.ball.velocity, g.ball.radius * .5)
	post_processor_update(&g.effects, dt)
}
