package delaunay_triangulation

import "core:fmt"
import "core:math"
import "core:math/linalg/glsl"

Point :: distinct glsl.vec2
Edge :: struct {
	p0: Point,
	p1: Point,
	i0: u16,
	i1: u16,
}
edges_equal :: proc(a, b: Edge) -> bool {
	return a.p0 == b.p0 && a.p1 == b.p1
}
Circle :: struct {
	center: Point,
	radius: f32,
}
Triangle :: struct {
	p0:      Point,
	p1:      Point,
	p2:      Point,
	e:       [3]Edge,
	indices: [3]u16,
	circle:  Circle,
}
Delaunay :: struct {
	triangles: [dynamic]Triangle,
	edges:     [dynamic]Edge,
}

EPS :: 1e-4

new_tri :: proc(p0, p1, p2: Point, i0, i1, i2: u16) -> Triangle {
	ax := p1.x - p0.x
	ay := p1.y - p0.y
	bx := p2.x - p1.x
	by := p2.y - p1.y

	m := p1.x * p1.x - p0.x * p0.x + p1.y * p1.y - p0.y * p0.y
	u := p2.x * p2.x - p0.x * p0.x + p2.y * p2.y - p0.y * p0.y
	s := 1 / (2 * (ax * by - ay * bx))

	circle := Circle{}
	circle.center.x = ((p2.y - p0.y) * m + (p0.y - p1.y) * u) * s
	circle.center.y = ((p0.x - p2.x) * m + (p1.x - p0.x) * u) * s
	dx := p0.x - circle.center.x
	dy := p0.y - circle.center.y
	circle.radius = dx * dx + dy * dy
	return(
		Triangle{
			p0,
			p1,
			p2,
			{{p0, p1, i0, i1}, {p1, p2, i1, i2}, {p0, p2, i0, i2}},
			{i0, i1, i2},
			circle,
		} \
	)
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
	// fmt.printf("xmin: %.2f, xmax: %.2f, ymin: %.2f, ymax: %.2f\n", xmin, xmax, ymin, ymax)

	dx := xmax - xmin
	dy := ymax - ymin
	dmax := math.max(dx, dy)
	midx := (xmin + xmax) / 2
	midy := (ymin + ymax) / 2

	d := Delaunay{}
	reserve_dynamic_array(&d.triangles, len(points))
	reserve_dynamic_array(&d.edges, len(points))
	p0 := Point{midx - 20 * dmax, midy - dmax}
	p1 := Point{midx, midy + 20 * dmax}
	p2 := Point{midx + 20 * dmax, midy - dmax}
	append(&d.triangles, new_tri(p0, p1, p2, 0, 0, 0)) // no indices, this is the big tri

	// TODO: make better capacity guesses
	edges := make([dynamic]Edge, len(points) * 3)
	tmps := make([dynamic]Triangle, len(points))
	for pt, pt_i in points {
		clear_dynamic_array(&edges)
		clear_dynamic_array(&tmps)

		for tri, tri_i in d.triangles {
			// check if point is inside of the triangle circumcircle
			dist :=
				(tri.circle.center.x - pt.x) * (tri.circle.center.x - pt.x) +
				(tri.circle.center.y - pt.y) * (tri.circle.center.y - pt.y)
			if (dist - tri.circle.radius) <= EPS {
				append(&edges, tri.e[0])
				append(&edges, tri.e[1])
				append(&edges, tri.e[2])
			} else {
				append(&tmps, tri)
			}
		}
		// Mark duplicate edges
		edge_dup := make([dynamic]bool, len(edges))
		for edge, edge_i in edges {
			append(&edge_dup, false)
		}
		for e0, e0_i in edges {
			for e1_i := e0_i; e1_i < len(edges); e1_i += 1 {
				if e0_i == e1_i {
					continue
				}
				if edge_dup[e0_i] || edge_dup[e1_i] {
					continue
				}
				if edges_equal(e0, edges[e1_i]) {
					edge_dup[e1_i] = true
				}
			}
		}
		// Erase duplicates from d.edges

		// Update triangulation
		for e, i in edges {
			if edge_dup[i] {
				continue
			}
			append(&tmps, new_tri(e.p0, e.p1, {pt.x, pt.y}, e.i0, e.i1, u16(pt_i)))
		}

		// replace triangles with tmps
		// might be better to do a pointer swap or something
		clear_dynamic_array(&d.triangles)
		for tri in tmps {
			append(&d.triangles, tri)
		}
	}

}
