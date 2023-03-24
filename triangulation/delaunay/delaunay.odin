package delaunay_triangulation

import "core:fmt"
import "core:math"
import "core:math/linalg/glsl"

I_Triangle :: struct {
	p1:       int,
	p2:       int,
	p3:       int,
	complete: bool,
}
I_Edge :: struct {
	p1: int,
	p2: int,
}
Point :: distinct glsl.vec2

EPSILON :: 1e-4

Circle :: struct {
	center: Point,
	radius: f32,
}


triangulate :: proc(points: ^[dynamic]Point, tris: ^[dynamic]I_Triangle) -> int {
	clear_dynamic_array(tris)

	// find min and max boundries of the point cloud

	// this is a weird standin for a slice...
	return len(tris)
}


inside :: proc "contextless" (p: Point, circle: Circle) -> bool {
	dx := circle.center.x - p.x
	dy := circle.center.y - p.y
	dist := dx * dx + dy * dy
	return dist <= circle.radius
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
