package game

import glm "core:math/linalg/glsl"


EventCollideType :: enum {
	PADDLE,
	BRICK,
	POWERUP,
}

EventCollide :: struct {
	type: EventCollideType,
	pos:  glm.vec2,
}
EventPowerupActivated :: struct {
	type: PowerupType,
}
EventPowerupDeactivated :: struct {
	type: PowerupType,
}

Event :: union {
	EventCollide,
	EventPowerupActivated,
	EventPowerupDeactivated,
}

event_q: [dynamic]Event

event_q_init :: proc() -> bool {
	return reserve_dynamic_array(&event_q, 10)
}
event_q_destroy :: proc() {
	delete_dynamic_array(event_q)
}
