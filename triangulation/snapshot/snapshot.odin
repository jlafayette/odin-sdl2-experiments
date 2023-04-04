package snapshot

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strconv"
import "core:strings"

import "../delaunay"

I_Triangle :: delaunay.I_Triangle


// Compare two slices of triangles to see if they are equal
// Order does not matter (both slices are sorted before comparison)
compare :: proc(t1, t2: []I_Triangle) -> (success: bool) {
	if len(t1) != len(t2) {
		fmt.eprintf("ERROR: trangle slices are of unequal length (%d vs %d)\n", len(t1), len(t2))
		return false
	}
	// currently this procedure mutates the input values, could change
	// this to make copies intead if this causes problems
	less :: proc(i, j: I_Triangle) -> bool {
		if i.x != j.x {
			return i.x < j.x
		}
		if i.y != j.y {
			return i.y < j.y
		}
		return i.z < j.z
	}
	slice.sort_by(t1, less)
	slice.sort_by(t2, less)

	for i := 0; i < len(t1); i += 1 {
		if t1[i] != t2[i] {
			fmt.eprintf("ERROR: Tris at index %d are not equal (%v != %v)\n", i, t1[i], t2[i])
			return false
		}
	}

	return true
}

path :: proc() -> string {
	path := filepath.join({"triangulation", "saved_snapshots"})
	return path
}


ensure_path_exists :: proc(path: string) -> (error: os.Errno) {
	if !os.exists(path) {
		err := os.make_directory(path)
		return err
	}
	return os.ERROR_NONE
}


file :: proc(path: string, vertex_count, iteration: int) -> string {
	b := strings.Builder{}
	defer strings.builder_destroy(&b)
	strings.builder_init_len_cap(&b, 0, 16)
	fmt.sbprintf(&b, "snapshot_%d_", vertex_count)
	if iteration <= 9 do fmt.sbprint(&b, "0")
	fmt.sbprintf(&b, "%d", iteration)
	file := filepath.join({path, strings.to_string(b)})
	return file
}


write_triangles :: proc(path: string, tris: []I_Triangle) -> bool {
	size := len(tris) * 3 * 4 // 3chars per int + separators, "123,123,123 "
	b := strings.Builder{}
	strings.builder_init_len_cap(&b, 0, size)
	defer strings.builder_destroy(&b)
	for tri, i in tris {
		if i != 0 do fmt.sbprint(&b, ' ')
		fmt.sbprintf(&b, "%X,%X,%X", tri.x, tri.y, tri.z)
	}
	fmt.sbprint(&b, " ")
	ok := os.write_entire_file(path, b.buf[:])
	return ok
}


read_triangles :: proc(path: string) -> ([dynamic]I_Triangle, bool) {
	data, read_ok := os.read_entire_file(path)
	if !read_ok do return nil, false
	defer delete(data)

	acc: [3]byte
	acc_i := 0
	tri: I_Triangle
	tri_i: int = 0
	tris := make([dynamic]I_Triangle, 0, 100)
	for x in data {
		switch x {
		case ' ':
			ok: bool
			tri[tri_i], ok = strconv.parse_int(string(acc[:acc_i]), 16)
			if !ok {
				return tris, false
			}
			tri_i = 0
			append(&tris, tri)
			tri = {-1, -1, -1}
			acc_i = 0
		case ',':
			ok: bool
			tri[tri_i], ok = strconv.parse_int(string(acc[:acc_i]), 16)
			if !ok do return tris, false
			tri_i += 1
			acc_i = 0
		case:
			acc[acc_i] = x
			acc_i += 1
		}
	}
	return tris, true
}

equal :: proc(tris1, tris2: []I_Triangle) -> bool {
	if len(tris1) != len(tris2) do return false
	for i := 0; i < len(tris1); i += 1 {
		if tris1[i] != tris2[i] do return false
	}
	return true
}
