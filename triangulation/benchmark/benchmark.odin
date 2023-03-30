package benchmark

import "core:os"
import "core:path/filepath"
import "core:strings"

import "../timer"


file :: proc() -> string {
	path := filepath.join({"triangulation", "benchmark_reports", "001"})
	return path
}

write_report :: proc(t: ^timer.Timer) -> bool {
	out_file := file()
	defer delete(out_file)
	b := timer.report(t, false)
	defer strings.builder_destroy(&b)
	ok := os.write_entire_file(out_file, b.buf[:])
	return ok
}
