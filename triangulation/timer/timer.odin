package timer

import "core:fmt"
import "core:strings"
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

destroy :: proc(t: ^Timer) {
	delete(t.runs)
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
	b := report(t)
	defer strings.builder_destroy(&b)
	fmt.print(strings.to_string(b))
}

report :: proc(t: ^Timer, verbose: bool = true) -> strings.Builder {
	b := strings.Builder{}
	strings.builder_init_len_cap(&b, 0, estimated_report_len(t))
	total: time.Duration = 0
	for run in t.runs {
		total += run.duration
		if verbose {
			ms_elapsed := f32(time.duration_milliseconds(run.duration))
			fmt.sbprintf(&b, "Triangulation of %d vertices took %.4f ms\n", t.vertex_count, ms_elapsed)
		}
	}
	average_duration := total / time.Duration(len(t.runs))
	average_ms := f32(time.duration_milliseconds(average_duration))
	fmt.sbprintf(&b, "Average %.4f ms per run (%d total runs)\n", average_ms, len(t.runs))
	return b
}

@(private)
estimated_report_len :: proc(t: ^Timer) -> int {
	return (len(t.runs) + 1) * 50
}
