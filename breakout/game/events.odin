package game

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

Event :: union {
	EventCollide,
	EventPowerupActivated,
	EventPowerupDeactivated,
	EventBallOut,
	EventLevelComplete,
	EventBallReleased,
}

event_q: [dynamic]Event

event_q_init :: proc() -> bool {
	return reserve_dynamic_array(&event_q, 10)
}
event_q_destroy :: proc() {
	delete_dynamic_array(event_q)
}
