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


triangulate :: proc(points: ^[dynamic]Point, tris: ^[dynamic]I_Triangle) -> (int, int) {
	clear_dynamic_array(tris)

	// find min and max boundries of the point cloud
	fmt.println(points)
	xmin: f32 = 0
	xmax: f32 = 0
	ymin: f32 = 0
	ymax: f32 = 0
	for p, i in points {
		xmin = math.min(xmin, p.x)
		xmax = math.max(xmax, p.x)
		ymin = math.min(xmin, p.y)
		ymax = math.max(ymax, p.y)
	}
	// map to 0-1 space
	height := ymax - ymin
	width := xmax - xmin
	d := math.max(width, height) // larget dimension
	for p, i in points {
		points[i].x = (p.x - xmin) / d
		points[i].y = (p.y - ymin) / d
	}
	fmt.println(points)


	// TODO: sort points by proximity
	// This is an optimization, so it's ok to skip for now

	// add super triangle around our points
	append(points, Point{-100, -100}, Point{100, -100}, Point{0, 100})

	// undo the 0-1 mapping
	for p, i in points {
		points[i].x = p.x * d + xmin
		points[i].y = p.y * d + ymin
	}
	fmt.println(points)

	// this is a weird standin for a slice...
	return len(points) - 3, len(tris)
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
