package text

import "core:fmt"
import "core:math"
import "core:strings"
import "core:unicode/utf8"

import "vendor:sdl2"
import "vendor:sdl2/ttf"

@(private)
WHITE: sdl2.Color : {255, 255, 255, 255}

@(private)
CHARS :: "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!\"#$%&\'()*+,-./:;<=>?@[\\]^_`{|}~ "

Pos :: struct {
	x: i32,
	y: i32,
}
Dim :: struct {
	w: i32,
	h: i32,
}

@(private)
Text :: struct {
	tex: ^sdl2.Texture,
	dim: Dim,
}

Drawer :: struct {
	font_size: i32,
	font:      ^ttf.Font,
	char_map:  map[rune]Text,
	renderer:  ^sdl2.Renderer,
}

@(private)
DEBUG_TTF :: "dynamic_text/fonts/Terminal.ttf"
@(private)
DEFAULT_TTF :: "dynamic_text/fonts/consola.ttf"

create_drawer :: proc(debug: bool, font_size: i32, renderer: ^sdl2.Renderer) -> ^Drawer {
	char_map: map[rune]Text = make(map[rune]Text)
	ttf_filepath: cstring = DEBUG_TTF if debug else DEFAULT_TTF
	font: ^ttf.Font = ttf.OpenFont(ttf_filepath, font_size)
	if font == nil {
		fmt.println("error opening font:", sdl2.GetErrorString())
		return nil
	}
	create_chars(debug, font, renderer, &char_map)
	ptr := new(Drawer)
	ptr.font_size = font_size
	ptr.font = font
	ptr.char_map = char_map
	ptr.renderer = renderer
	return ptr
}

destroy_drawer :: proc(drawer: ^Drawer) {
	ttf.CloseFont(drawer.font)
	for _, value in drawer.char_map {
		sdl2.DestroyTexture(value.tex)
	}
	delete(drawer.char_map)
	free(drawer)
}

draw :: proc(
	drawer: ^Drawer,
	builder: ^strings.Builder,
	pos: Pos,
	wrap_width: i32 = -1,
	scale: f64 = 1.0,
) {
	str := strings.to_string(builder^)
	// do we need to free this str?

	char_map := drawer.char_map
	renderer := drawer.renderer

	char_spacing: i32 = 2
	row_spacing: i32 = 10
	tallest_in_row: i32 = 0
	x: i32 = pos.x
	y: i32 = pos.y
	for c in str {
		text: Text = char_map[c]

		wf: f64 = f64(text.dim.w) * scale
		hf: f64 = f64(text.dim.h) * scale
		w := i32(math.round(wf))
		h := i32(math.round(hf))

		dest := sdl2.Rect {
			x = x,
			y = y,
			w = w,
			h = h,
		}
		e := sdl2.RenderCopy(renderer, text.tex, nil, &dest)
		if e < 0 {
			fmt.println("failed writing char:", c, "with error", sdl2.GetErrorString())
			break
		}
		x += w + char_spacing
		if wrap_width > 0 {
			tallest_in_row = max(tallest_in_row, h)
			if x > (pos.x + wrap_width) {
				x = pos.x
				y += tallest_in_row + row_spacing
				tallest_in_row = 0
			}
		}
	}
}

@(private)
create_chars :: proc(
	debug: bool,
	font: ^ttf.Font,
	renderer: ^sdl2.Renderer,
	char_map: ^map[rune]Text,
) {
	for c in CHARS[:] {
		str := utf8.runes_to_string([]rune{c})
		defer delete(str)
		char_map[c] = create_text(debug, cstring(raw_data(str)), font, renderer)
	}
}

@(private)
create_text :: proc(debug: bool, str: cstring, font: ^ttf.Font, renderer: ^sdl2.Renderer) -> Text {
	surface: ^sdl2.Surface
	if debug {
		surface = ttf.RenderText_Solid(font, str, WHITE)
	} else {
		surface = ttf.RenderText_Blended(font, str, WHITE)
	}
	if surface == nil {
		fmt.println("error creating surface", sdl2.GetErrorString())
	}
	defer sdl2.FreeSurface(surface)

	texture := sdl2.CreateTextureFromSurface(renderer, surface)
	if texture == nil {
		fmt.println("error creating texture", sdl2.GetErrorString())
	}
	dim := Dim{}
	ttf.SizeText(font, str, &dim.w, &dim.h)

	return Text{tex = texture, dim = dim}
}
