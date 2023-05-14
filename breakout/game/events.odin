package game


EventCollideType :: enum {
	PADDLE,
	BRICK,
}

EventCollide :: struct {
	type: EventCollideType,
}

Event :: union {
	EventCollide,
}

event_q: [dynamic]Event

event_q_init :: proc() -> bool {
	return reserve_dynamic_array(&event_q, 10)
}
event_q_destroy :: proc() {
	delete_dynamic_array(event_q)
}
