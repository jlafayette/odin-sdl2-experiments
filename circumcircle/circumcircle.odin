package dynamic_text

import "core:c"
import "core:mem"
import "core:math"
import "core:fmt"
import "core:time"
import "core:strings"
import "core:math/linalg/glsl"

import "vendor:sdl2"

Point :: distinct glsl.vec2
Color :: distinct [4]u8

BLACK :: Color{0, 0, 0, 255}
WHITE :: Color{255, 255, 255, 255}
RED :: Color{255, 0, 0, 255}
GREEN :: Color{0, 255, 0, 255}
BLUE :: Color{0, 0, 255, 255}

EPSILON :: 1e-4

SelectedPoint :: struct {
	point: Point,
	index: int,
}
Sel :: union {
	SelectedPoint,
}

Game :: struct {
	fps:           f64,
	points:        [4]Point,
	sel:           Sel,
	mouse_clicked: bool,
}

Circle :: struct {
	center: Point,
	radius: f32,
}


main :: proc() {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)

	_main()

	for _, leak in track.allocation_map {
		fmt.printf("%v leaked %v bytes\n", leak.location, leak.size)
	}
	for bad_free in track.bad_free_array {
		fmt.printf("%v allocation %p was freed badly\n", bad_free.location, bad_free.memory)
	}
}

_main :: proc() {
	window_width: i32 = 1200
	window_height: i32 = 800

	window := sdl2.CreateWindow(
		"Circumcircle Test",
		sdl2.WINDOWPOS_UNDEFINED,
		sdl2.WINDOWPOS_UNDEFINED,
		window_width,
		window_height,
		{.SHOWN},
	)
	assert(window != nil, sdl2.GetErrorString())
	defer sdl2.DestroyWindow(window)

	renderer := sdl2.CreateRenderer(window, -1, sdl2.RENDERER_ACCELERATED)
	assert(renderer != nil, sdl2.GetErrorString())
	defer sdl2.DestroyRenderer(renderer)

	run(window_width, window_height, renderer, 60)
}

run :: proc(window_width: i32, window_height: i32, renderer: ^sdl2.Renderer, refresh_rate: i32) {

	center := Point{f32(window_width) / 2, f32(window_height) / 2}
	game := Game {
		fps = 0,
		points = [4]Point{center + {0, -100}, center + {-100, 100}, center + {100, 100}, center},
	}

	target_dt: f64 = 1000 / f64(refresh_rate)
	start: f64
	end: f64

	game_loop: for {
		start = get_time()
		// Handle input events
		event: sdl2.Event
		for sdl2.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				break game_loop
			case .WINDOWEVENT:
				if event.window.event == .CLOSE {
					sdl2.PushEvent(&sdl2.Event{type = .QUIT})
				}
			case .KEYUP:
				if event.key.keysym.scancode == .ESCAPE {
					sdl2.PushEvent(&sdl2.Event{type = .QUIT})
				}
			case .MOUSEBUTTONDOWN:
				if event.button.button == sdl2.BUTTON_LEFT {
					game.mouse_clicked = true
				}
			case .MOUSEBUTTONUP:
				if event.button.button == sdl2.BUTTON_LEFT {
					game.mouse_clicked = false
				}
			}
		}
		mouse := mouse_point()
		if game.mouse_clicked {
			switch sel in game.sel {
			case SelectedPoint:
				game.points[sel.index] = mouse
				game.sel = SelectedPoint{mouse, sel.index}
			}
		} else {
			game.sel = nil
			for point, i in game.points {
				if distance(point, mouse) < 14 {
					game.sel = SelectedPoint{point, i}
					break
				}
			}
		}
		circle := circum_circle(game.points[0], game.points[1], game.points[2])
		radius := math.sqrt_f32(circle.radius)

		// Render
		draw_line(renderer, game.points[0], game.points[1])
		draw_line(renderer, game.points[1], game.points[2])
		draw_line(renderer, game.points[2], game.points[0])
		for point, i in game.points {
			color := WHITE
			if i == 3 {
				inside_circle := inside(point, circle)
				inside_triangle := point_within_triangle2(
					point,
					game.points[0],
					game.points[1],
					game.points[2],
				)
				color = BLUE
				if inside_circle {
					color = Color{185, 0, 185, 255}
					if inside_triangle {
						color = RED
					}
				}
			}
			draw_point(renderer = renderer, pt = point, color = color)
		}
		draw_circle_f32(renderer, circle.center.x, circle.center.y, radius)
		switch sel in game.sel {
		case SelectedPoint:
			draw_point(renderer, sel.point, 14, GREEN)
		}

		sdl2.RenderPresent(renderer)
		sdl2.SetRenderDrawColor(renderer, 0, 0, 0, 255)
		sdl2.RenderClear(renderer)

		free_all(context.temp_allocator)

		// Timing (avoid looping too fast)
		end = get_time()
		to_sleep := time.Duration((target_dt - (end - start)) * f64(time.Millisecond))
		time.accurate_sleep(to_sleep)
		end = get_time()
		game.fps = 1000 / (end - start)
	}
}


get_time :: proc "contextless" () -> f64 {
	return f64(sdl2.GetPerformanceCounter()) * 1000 / f64(sdl2.GetPerformanceFrequency())
}


mouse_point :: proc "contextless" () -> Point {
	cx, cy: c.int
	sdl2.GetMouseState(&cx, &cy)
	return Point{f32(cx), f32(cy)}
}


draw_point :: proc "contextless" (
	renderer: ^sdl2.Renderer,
	pt: Point,
	size: i32 = 10,
	color: Color = WHITE,
) {
	sdl2.SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a)
	x := i32(math.round(pt.x))
	y := i32(math.round(pt.y))
	rect := sdl2.Rect{}
	rect.x = x - size / 2
	rect.y = y - size / 2
	rect.w = size
	rect.h = size
	sdl2.RenderDrawRect(renderer, &rect)
}


draw_line :: proc "contextless" (renderer: ^sdl2.Renderer, p1, p2: Point, color: Color = WHITE) {
	sdl2.SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a)
	sdl2.RenderDrawLineF(renderer, p1.x, p1.y, p2.x, p2.y)
}


draw_circle_f32 :: proc "contextless" (
	renderer: ^sdl2.Renderer,
	cx, cy, radius: f32,
	color: Color = WHITE,
) {
	draw_circle(renderer, i32(math.round(cx)), i32(math.round(cy)), i32(math.round(radius)), color)
}
// Midpoint circle algorithm
draw_circle :: proc "contextless" (
	renderer: ^sdl2.Renderer,
	center_x, center_y, radius: i32,
	color: Color = WHITE,
) {
	diameter: i32 = (radius * 2)
	x: i32 = radius - 1
	y: i32 = 0
	tx: i32 = 1
	ty: i32 = 1
	error: i32 = tx - diameter

	sdl2.SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a)
	for x >= y {
		sdl2.RenderDrawPoint(renderer, center_x + x, center_y - y)
		sdl2.RenderDrawPoint(renderer, center_x + x, center_y + y)
		sdl2.RenderDrawPoint(renderer, center_x - x, center_y - y)
		sdl2.RenderDrawPoint(renderer, center_x - x, center_y + y)
		sdl2.RenderDrawPoint(renderer, center_x + y, center_y - x)
		sdl2.RenderDrawPoint(renderer, center_x + y, center_y + x)
		sdl2.RenderDrawPoint(renderer, center_x - y, center_y - x)
		sdl2.RenderDrawPoint(renderer, center_x - y, center_y + x)
		if error <= 0 {
			y += 1
			error += ty
			ty += 2
		}
		if error > 0 {
			x -= 1
			tx += 2
			error += tx - diameter
		}
	}
}


inside :: proc "contextless" (p: Point, circle: Circle) -> bool {
	dx := circle.center.x - p.x
	dy := circle.center.y - p.y
	dist := dx * dx + dy * dy
	return dist <= circle.radius
}


distance :: proc "contextless" (p1, p2: Point) -> f32 {
	dx := p2.x - p1.x
	dy := p2.y - p1.y
	return math.sqrt_f32(dx * dx + dy * dy)
}


circum_circle :: proc "contextless" (p1, p2, p3: Point) -> Circle {
	ax := p2.x - p1.x
	ay := p2.y - p1.y
	bx := p3.x - p1.x
	by := p3.y - p1.y

	m := p2.x * p2.x - p1.x * p1.x + p2.y * p2.y - p1.y * p1.y
	u := p3.x * p3.x - p1.x * p1.x + p3.y * p3.y - p1.y * p1.y
	s := 1 / (2 * (ax * by - ay * bx))

	circle_x := ((p3.y - p1.y) * m + (p1.y - p2.y) * u) * s
	circle_y := ((p1.x - p3.x) * m + (p2.x - p1.x) * u) * s

	dx := p1.x - circle_x
	dy := p1.y - circle_y
	radius := dx * dx + dy * dy
	return Circle{{circle_x, circle_y}, radius}
}

// Check both clockwise and counterclockwise
point_within_triangle2 :: proc "contextless" (p, v1, v2, v3: Point) -> bool {
	dir1 := point_within_triangle(p, v1, v2, v3)
	if dir1 do return true
	return point_within_triangle(p, v1, v3, v2)
}

// Only clockwise
point_within_triangle :: proc "contextless" (p, v1, v2, v3: Point) -> bool {
	ab := Point{v2[0] - v1[0], v2[1] - v1[1]}
	bc := Point{v3[0] - v2[0], v3[1] - v2[1]}
	ca := Point{v1[0] - v3[0], v1[1] - v3[1]}
	ap := Point{p[0] - v1[0], p[1] - v1[1]}
	bp := Point{p[0] - v2[0], p[1] - v2[1]}
	cp := Point{p[0] - v3[0], p[1] - v3[1]}

	n1 := Point{ab[1], -ab[0]}
	n2 := Point{bc[1], -bc[0]}
	n3 := Point{ca[1], -ca[0]}

	s1: f32 = ap[0] * n1[0] + ap[1] * n1[1]
	s2: f32 = bp[0] * n2[0] + bp[1] * n2[1]
	s3: f32 = cp[0] * n3[0] + cp[1] * n3[1]

	tolerance: f32 = 0.0001

	if ((s1 < 0 && s2 < 0 && s3 < 0) ||
		   (s1 < tolerance && s2 < 0 && s3 < 0) ||
		   (s2 < tolerance && s1 < 0 && s3 < 0) ||
		   (s3 < tolerance && s1 < 0 && s2 < 0)) {
		return true
	} else {
		return false
	}
}
