package delaunay_triangulation

import "core:fmt"
import "core:math"
import "core:math/linalg/glsl"

Point :: distinct glsl.vec2
Edge :: struct {
	p0: Point,
	p1: Point,
}
Circle :: struct {
	center: Point,
	radius: f32,
}
Triangle :: struct {
	p0:     Point,
	p1:     Point,
	p2:     Point,
	e:      [3]Edge,
	circle: Circle,
}
Delaunay :: struct {
	triangles: [dynamic]Triangle,
	edges:     [dynamic]Edge,
}

triangulate :: proc(points: ^[dynamic]Point, indices: ^[dynamic]u16) {
	clear_dynamic_array(indices)
	if len(points) < 3 {
		return
	}

	xmin := points[0].x
	xmax := xmin
	ymin := points[0].y
	ymax := ymin
	for pt in points {
		xmin = math.min(xmin, pt.x)
		xmax = math.max(xmax, pt.x)
		ymin = math.min(ymin, pt.y)
		ymax = math.max(ymax, pt.y)
	}
	fmt.printf("xmin: %.2f, xmax: %.2f, ymin: %.2f, ymax: %.2f\n", xmin, xmax, ymin, ymax)
}
