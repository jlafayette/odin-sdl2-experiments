package game

import "core:c"
import "vendor:sdl2"

game_handle_inputs :: proc(g: ^Game) -> bool {
	event: sdl2.Event
	for sdl2.PollEvent(&event) {
		#partial switch event.type {
		case .QUIT:
			return true
		case .KEYUP:
			if event.key.keysym.sym == .ESCAPE {
				sdl2.PushEvent(&sdl2.Event{type = .QUIT})
			}
		case .KEYDOWN:
			switch g.state {
			case .ACTIVE:
				if event.key.keysym.sym == .SPACE {
					append(&event_q, EventBallReleased{})
				}
			case .MENU:
				#partial switch event.key.keysym.sym {
				case .W:
					append(&event_q, EventLevelSelect{dir = .NEXT})
				case .S:
					append(&event_q, EventLevelSelect{dir = .PREV})
				case .RETURN:
					append(&event_q, EventGameStateChange{state = .ACTIVE})
				}
			case .WIN:
				if event.key.keysym.sym == .RETURN {
					append(&event_q, EventGameStateChange{state = .MENU})
				}
			case .LOSE:
				if event.key.keysym.sym == .RETURN {
					append(&event_q, EventGameStateChange{state = .MENU})
				}
			}
		}
	}
	numkeys: c.int
	keyboard_state := sdl2.GetKeyboardState(&numkeys)
	g.is_left = keyboard_state[sdl2.Scancode.A] > 0 || keyboard_state[sdl2.Scancode.LEFT] > 0
	g.is_right = keyboard_state[sdl2.Scancode.D] > 0 || keyboard_state[sdl2.Scancode.RIGHT] > 0
	return false
}
