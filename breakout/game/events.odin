package game

import "core:fmt"
import "core:math/rand"
import glm "core:math/linalg/glsl"


EventCollideType :: enum {
	PADDLE,
	BRICK,
	POWERUP,
	WALL,
}
EventCollide :: struct {
	type:  EventCollideType,
	pos:   glm.vec2,
	solid: bool,
}

EventPowerupActivated :: struct {
	type: PowerupType,
}
EventPowerupDeactivated :: struct {
	type: PowerupType,
}

EventBallOut :: struct {}
EventLevelComplete :: struct {}
EventBallReleased :: struct {}
EventGameStateChange :: struct {
	state: GameState,
}
LevelSelectDir :: enum {
	NEXT,
	PREV,
}
EventLevelSelect :: struct {
	dir: LevelSelectDir,
}

Event :: union {
	EventCollide,
	EventPowerupActivated,
	EventPowerupDeactivated,
	EventBallOut,
	EventLevelComplete,
	EventBallReleased,
	EventGameStateChange,
	EventLevelSelect,
}

event_q: [dynamic]Event

event_q_init :: proc() -> bool {
	err := reserve(&event_q, 10)
	return err == .None
}
event_q_destroy :: proc() {
	delete(event_q)
}

game_handle_events :: proc(game: ^Game) -> bool {
	// handle events
	for event in event_q {
		switch e in event {
		case EventCollide:
			game.effects.shake = true
			pan: f32 = e.pos.x / f32(game.window_width)
			pan = (pan * 1.8) - .9
			pitch := rand.float32(&game.rand)
			switch e.type {
			case .BRICK:
				game.effects.shake_time = 0.05
				if !e.solid do powerup_spawn(&game.powerups, e.pos)
				if e.solid {
					sound_play(.SOLID, 1, pan, (pitch * .2) + .8)
				} else {
					sound_play(.BLEEP, 1, pan, (pitch * .2) + .85)
				}
			case .PADDLE:
				if game.paddle.sticky {
					pitch = 0.5
				} else {
					pitch = 1
				}
				sound_play(Sound.BLOOP, 1, pan, pitch)
				game.effects.shake_time = 0.02
			case .POWERUP:
				sound_play(.POWERUP, 1, pan, 1)
			case .WALL:
				sound_play(.SOLID, 1, pan, (pitch * .1) + .95)
			}
		case EventPowerupActivated:
			switch e.type {
			case .SPEED:
				game.ball.velocity *= 1.2
			case .STICKY:
				game.ball.sticky += 1
				game.paddle.sticky = true
			case .PASS_THROUGH:
				game.ball.pass_through += 1
			case .PADDLE_SIZE_INCREASE:
				game.paddle.size.x += 50
			case .CONFUSE:
				game.effects.confuse = true
			case .CHAOS:
				game.effects.chaos = true
			}
		case EventPowerupDeactivated:
			switch e.type {
			case .SPEED:
				game.ball.velocity /= 1.2
			case .STICKY:
				game.ball.sticky -= 1
				game.paddle.sticky = game.ball.sticky > 0
			case .PASS_THROUGH:
				game.ball.pass_through -= 1
			case .PADDLE_SIZE_INCREASE:
				game.paddle.size.x -= 50
			case .CONFUSE:
				game.effects.confuse = false
			case .CHAOS:
				game.effects.chaos = false
			}
		case EventLevelComplete:
			if game.state == .ACTIVE {
				game.state = .WIN
			}
		case EventLevelSelect:
			number: int
			switch e.dir {
			case .NEXT:
				number = game.level.number + 1
				if number > LEVEL_COUNT {
					number = 1
				}
			case .PREV:
				number = game.level.number - 1
				if number < 1 {
					number = LEVEL_COUNT
				}
			}
			load_ok := game_level_change(game, number)
			if !load_ok {
				return false
			}
		case EventBallOut:
			if game.state == .ACTIVE {
				game.lives -= 1
			}
			if game.lives <= 0 {
				game.state = .LOSE
			} else {
				ball_reset(&game.ball, game.paddle.pos, game.paddle.size)
				game.effects.confuse = false
				game.effects.chaos = false
			}
		case EventBallReleased:
			fmt.println("EventBallReleased")
			game.ball.stuck = false
			game.ball.stuck_offset = {0, 0}
		case EventGameStateChange:
			fmt.printf("Game state changed from %v to %v\n", game.state, e.state)
			if game.state == .LOSE && e.state == .MENU {
				game.lives = 3
				game_level_reset(&game.level)
				paddle_reset(&game.paddle)
				clear(&game.powerups.data)
				ball_reset(&game.ball, game.paddle.pos, game.paddle.size)
				game.effects.confuse = false
				game.effects.chaos = false
			}
			game.state = e.state
		}
	}
	clear(&event_q)
	return true
}

game_level_change :: proc(game: ^Game, number: int) -> bool {
	ok := game_level_load(&game.level, number, game.window_width, game.window_height / 2)
	if !ok {
		fmt.eprintf("Error loading level %d\n", number)
		return false
	}
	paddle_reset(&game.paddle)
	ball_reset(&game.ball, game.paddle.pos, game.paddle.size)
	clear(&game.powerups.data)
	game.effects.confuse = false
	game.effects.chaos = false
	return true
}
