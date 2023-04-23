package pitch

CHROMATIC_SCALE: [12]f64 = {
	261.63,
	277.18,
	293.66,
	311.13,
	329.23,
	349.23,
	369.99,
	392.00,
	415.30,
	440.00,
	466.16,
	493.88,
}

c := CHROMATIC_SCALE[0]
c_sharp := CHROMATIC_SCALE[1]
d := CHROMATIC_SCALE[2]
d_sharp := CHROMATIC_SCALE[3]
e := CHROMATIC_SCALE[4]
f := CHROMATIC_SCALE[5]
f_sharp := CHROMATIC_SCALE[6]
g := CHROMATIC_SCALE[7]
g_sharp := CHROMATIC_SCALE[8]
a := CHROMATIC_SCALE[9]
a_sharp := CHROMATIC_SCALE[10]
b := CHROMATIC_SCALE[11]

SCALE := [?]f64{c, d, e, f, g, a, b, 2 * c}

@(private)
next_pitch_up := true

next_pitch :: proc(current_idx: int, scale: []f64) -> int {
	new_idx: int
	if next_pitch_up {
		new_idx = current_idx + 1
		if new_idx >= len(scale) {
			next_pitch_up = false
			new_idx = current_idx - 1
		}
	} else {
		new_idx = current_idx - 1
		if new_idx < 0 {
			next_pitch_up = true
			new_idx = current_idx + 1
		}
	}
	// fmt.printf("pitch: %d->%d %t\n", current_idx, new_idx, next_pitch_up)
	return new_idx
}
