package game

import "core:fmt"
import "core:os"
import "core:path/filepath"
import glm "core:math/linalg/glsl"

Brick :: struct {
	pos:       glm.vec2,
	size:      glm.vec2,
	color:     glm.vec3,
	is_solid:  bool,
	destroyed: bool,
}

GameLevel :: struct {
	bricks:    [dynamic]Brick,
	row_len:   int,
	row_count: int,
	completed: bool,
}

level_one_file: string = filepath.join({"breakout", "levels", "one.lvl"})
level_two_file: string = filepath.join({"breakout", "levels", "two.lvl"})
level_three_file: string = filepath.join({"breakout", "levels", "three.lvl"})
level_four_file: string = filepath.join({"breakout", "levels", "four.lvl"})

game_level_load :: proc(level: ^GameLevel, file: string, width, height: int) -> bool {
	tiles, row_len, row_count, ok := game_level_load_from_file(file)
	if !ok do return false
	defer delete(tiles)
	fmt.printf("%d x %d\n", row_len, row_count)
	game_level_init(level, tiles[:], row_len, row_count, width, height)
	return true
}

game_level_init :: proc(
	level: ^GameLevel,
	tiles: []int,
	row_len, row_count: int,
	lvl_width, lvl_height: int,
) {
	reserve_dynamic_array(&level.bricks, len(tiles))
	level.completed = false
	level.row_len = row_len
	level.row_count = row_count
	unit_w := f32(lvl_width) / f32(row_len)
	unit_h := f32(lvl_height) / f32(row_count)
	for t, i in tiles {
		if (t <= '0') {
			continue
		}
		x := i % row_len
		y := i / row_len
		pos := glm.vec2{f32(x) * unit_w, f32(y) * unit_h}
		size := glm.vec2{unit_w, unit_h}
		color: glm.vec3
		switch t {
		case '1':
			color = {.8, .8, .7}
		case '2':
			color = {.2, .6, 1}
		case '3':
			color = {0, .7, 0}
		case '4':
			color = {.8, .8, .4}
		case '5':
			color = {1, .5, 0}
		case:
			color = {0, 0, 0}
		}
		is_solid := t == '1'
		append(&level.bricks, Brick{pos, size, color, is_solid, false})
	}
}
game_level_destroy :: proc(level: ^GameLevel) {
	delete(level.bricks)
}

game_level_load_from_file :: proc(file: string) -> ([dynamic]int, int, int, bool) {
	data, read_ok := os.read_entire_file_from_filename(file)
	if !read_ok {
		fmt.eprintf("Error reading file %s\n", file)
		return nil, 0, 0, false
	}
	defer delete(data)
	numbers := make([dynamic]int, 0, len(data) / 2)
	row_len: int = 0
	row_len_known := false
	current_row_len: int = 0
	for b, i in data {
		if b == ' ' || b == '\r' {
			continue
		}
		if b == '\n' {
			row_len_known = true
			if current_row_len != row_len {
				fmt.eprintf("Error loading %s, all rows must be the same length\n", file)
				delete(numbers)
				return nil, 0, 0, false
			}
			current_row_len = 0
			continue
		}
		if !row_len_known do row_len += 1
		current_row_len += 1
		append(&numbers, int(b))
	}
	row_count := len(numbers) / row_len
	return numbers, row_len, row_count, true
}
