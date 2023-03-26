package timer

import "core:fmt"
import "core:time"

@(private)
Run :: struct {
	duration: time.Duration,
}

Timer :: struct {
	running:      bool,
	start:        time.Tick,
	vertex_count: int,
	runs:         [dynamic]Run,
}
init :: proc(t: ^Timer, vertex_count: int, iterations: int = 100) {
	reserve_dynamic_array(&t.runs, iterations)
	t.vertex_count = vertex_count
}

start :: proc(t: ^Timer, vertex_count: int) {
	assert(!t.running, "Timer is already running!")
	t.running = true
	t.start = time.tick_now()
}

stop :: proc(t: ^Timer) {
	t.running = false
	append(&t.runs, Run{time.tick_since(t.start)})
}

print :: proc(t: ^Timer) {
	total: time.Duration = 0
	for run in t.runs {
		total += run.duration
		ms_elapsed := f32(time.duration_milliseconds(run.duration))
		fmt.printf("Triangulation of %d vertices took %.4f ms\n", t.vertex_count, ms_elapsed)
	}
	average_duration := total / time.Duration(len(t.runs))
	average_ms := f32(time.duration_milliseconds(average_duration))
	fmt.printf("Average %.4f ms per run\n", average_ms)
}
