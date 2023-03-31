package benchmark

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:strconv"

import "../timer"


@(private)
get_path :: proc() -> string {
	return filepath.join({"triangulation", "benchmark_reports"})
}

file :: proc() -> (result: string, success: bool) {
	path := get_path()
	if !os.exists(path) {
		mkdir_err := os.make_directory(path) // mode is not needed on Windows
		if mkdir_err != os.ERROR_NONE {
			fmt.eprintf("Error creating directory %s, os ERROR: %d\n", path, mkdir_err)
			return "", false
		}
	}
	defer delete(path)
	handle, open_err := os.open(path)
	if open_err != os.ERROR_NONE {
		fmt.eprintf("Error opening dir %s, os ERROR: %d\n", path, open_err)
		return "", false
	}
	defer os.close(handle)
	file_infos, read_err := os.read_dir(handle, 0)
	if read_err != os.ERROR_NONE {
		fmt.eprintf("Error reading dir %s, os ERROR: %d\n", path, read_err)
		return "", false
	}
	defer {
		for fi in file_infos do os.file_info_delete(fi)
		delete(file_infos)
	}
	next: int = 0
	for fi in file_infos {
		num, ok := strconv.parse_int(fi.name)
		if ok && num >= next {
			next = num + 1
		}
	}
	name := fmt.aprintf("%d", next)
	defer delete(name)
	padded := strings.right_justify(name, 3, "0")
	defer delete(padded)
	result = filepath.join({path, padded})
	return result, true
}

write_report :: proc(t: ^timer.Timer) -> (success: bool) {
	out_file, ok := file()
	if !ok do return false
	defer delete(out_file)
	b := timer.report(t, false)
	defer strings.builder_destroy(&b)
	fmt.printf("Writing report to %s\n", out_file)
	ok = os.write_entire_file(out_file, b.buf[:])
	if !ok {
		fmt.eprintf("Error writing report file to %s\n", out_file)
	}
	return ok
}
