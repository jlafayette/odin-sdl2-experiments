/*
Resources and inspiration:

	Efficient Triangulation Algorithm Suitable for Terrain Modelling
	http://paulbourke.net/papers/triangulate/

	C++ implementation by Jean Bégaint
	https://github.com/jbegaint/delaunay-cpp

	xmdi Planar Delaunay Triangulations | CAD from Scratch [16]
	https://www.youtube.com/watch?v=pPqZPX9DvTg&t=1056s&ab_channel=xmdi
	https://github.com/xmdi/CAD-from-Scratch/blob/main/016/geom.c#L929

*/
package delaunay_triangulation

TRACY_ENABLE :: #config(TRACY_ENABLE, false)

import "core:fmt"
import "core:math"
import "core:slice"
import "core:time"
import "core:container/queue"
import "core:math/linalg/glsl"
import tracy "../../../../odin-tracy"

I_Verts :: distinct [3]int
I_Triangle :: distinct [3]int
I_Edge :: distinct [2]int
Point :: distinct glsl.vec2

EPSILON :: 1e-4

Tri :: struct {
	i:      I_Triangle,
	circle: Circle,
}
create_tri :: proc(i1, i2, i3: int, p1, p2, p3: Point) -> Tri {
	circle := circum_circle(p1, p2, p3)
	tri := Tri{{i1, i2, i3}, circle}
	return tri
}

Circle :: struct {
	center: Point,
	radius: f32,
}


triangulate :: proc(points_backing: ^[dynamic]Point) -> ([]Point, []I_Triangle) {
	tracy.ZoneN("triangulate")

	// Initialize the triangle list. Store circumcircle so it doesn't
	// have to be recomputed
	tris_backing := make([dynamic]Tri, 0, len(points_backing) * 2)
	defer delete(tris_backing)

	// remap point cloud to 0-1 space
	// find min and max boundries of the point cloud
	xmin: f32 = 0
	xmax: f32 = 0
	ymin: f32 = 0
	ymax: f32 = 0
	for p, i in points_backing {
		xmin = math.min(xmin, p.x)
		xmax = math.max(xmax, p.x)
		ymin = math.min(xmin, p.y)
		ymax = math.max(ymax, p.y)
	}
	// map to 0-1 space
	height := ymax - ymin
	width := xmax - xmin
	largest_dimension := math.max(width, height) // larget dimension
	for p, i in points_backing {
		points_backing[i].x = (p.x - xmin) / largest_dimension
		points_backing[i].y = (p.y - ymin) / largest_dimension
	}

	// determine the supertriangle
	// add supertriangle around our points vertices to the end of the vertex list
	append(points_backing, Point{-100, -100}, Point{100, -100}, Point{0, 100})
	points := points_backing[:]

	// add the supertriangle to the triangle list
	i1 := len(points) - 3
	i2 := len(points) - 2
	i3 := len(points) - 1
	super_tri := create_tri(i1, i2, i3, points[i1], points[i2], points[i3])
	append(&tris_backing, super_tri)
	points = points_backing[:]
	triangles := tris_backing[:]

	// initialize buffers needed for main loop
	edges_backing := make([dynamic]I_Edge, 0, 200)
	defer delete(edges_backing)
	to_delete := make([dynamic]int, 0, 16)
	defer delete(to_delete)

	// for each sample point in the vertex list
	for i := 0; i < len(points) - 3; i += 1 {
		tracy.ZoneN("1 point loop")
		point := points[i]

		clear_dynamic_array(&edges_backing)
		clear_dynamic_array(&to_delete)

		// 	for each triangle currently in the triangle list
		for tri_i := 0; tri_i < len(triangles); tri_i += 1 {
			tracy.ZoneN("2 tri loop")
			tri := triangles[tri_i]
			// if the point lies in the triangle circumcircle then
			if inside_circle(point, tri.circle) {
				// add the three triangle edges to the edge buffer
				append(
					&edges_backing,
					I_Edge{tri.i.x, tri.i.y},
					I_Edge{tri.i.y, tri.i.z},
					I_Edge{tri.i.x, tri.i.z},
				)
				// remove the triangle from the triangle list
				remove_item(&triangles, tri_i)
				tri_i -= 1
			} // endif
		} // endfor

		// Remove doubled up edges, leaving only the edges of the
		// enclosing polygon
		edges := edges_backing[:]
		mark_duplicates(edges, &to_delete)
		slice.sort(to_delete[:])
		for di := len(to_delete) - 1; di >= 0; di -= 1 {
			remove_item(&edges, to_delete[di])
		}
		// Add to the triangle list all triangles formed between the point 
		// and the edges of the enclosing polygon
		for edge in edges {
			add_item(
				&triangles,
				&tris_backing,
				create_tri(i, edge.x, edge.y, points[i], points[edge.x], points[edge.y]),
			)
		}

	} // endfor

	// remove any triangles from the triangle list that use the supertriangle vertices
	nv := len(points_backing) - 3
	for i := 0; i < len(triangles); i += 1 {
		tri := triangles[i]
		if tri.i.x >= nv || tri.i.y >= nv || tri.i.z >= nv {
			remove_item(&triangles, i)
			i -= 1
		}
	}

	// undo the 0-1 mapping
	for p, i in points_backing {
		points_backing[i].x = p.x * largest_dimension + xmin
		points_backing[i].y = p.y * largest_dimension + ymin
	}

	result_tris := make([dynamic]I_Triangle, 0, len(triangles))
	for tri in triangles {
		append(&result_tris, tri.i)
	}

	return points_backing[:len(points_backing) - 3], result_tris[:]}


tri_includes_edge :: proc(edge: I_Edge, tri: I_Triangle) -> bool {
	return(
		edge.xy == tri.xy ||
		edge.xy == tri.yx ||
		edge.xy == tri.xz ||
		edge.xy == tri.zx ||
		edge.xy == tri.yz ||
		edge.xy == tri.zy \
	)
}


edges_equal :: proc "contextless" (e1, e2: I_Edge) -> bool {
	return e1.xy == e2.xy || e1.xy == e2.yx
}
mark_duplicates :: proc(s: []I_Edge, marked: ^[dynamic]int) {
	for i := 0; i < len(s); i += 1 {
		for j := i + 1; j < len(s); j += 1 {
			if #force_inline edges_equal(s[i], s[j]) {
				append(marked, i, j)
				break
			}
		}
	}
}
remove_duplicates :: proc(s: ^[]I_Edge) {
	for i := 0; i < len(s); i += 1 {
		for j := i + 1; j < len(s); j += 1 {
			if #force_inline edges_equal(s[i], s[j]) {
				remove_item(s, j)
				j -= 1
			}
		}
	}
}
remove_item :: proc(s: ^[]$T, i: int) {
	x := len(s) - 1
	if i != x {
		slice.swap(s^, i, x)
	}
	s^ = s[:len(s) - 1]
}
add_item :: proc(s: ^[]$T, backing: ^[dynamic]T, v: T) {
	if len(backing) == len(s) {
		append(backing, v)
		s^ = backing[:]
		return
	}
	s^ = backing[:len(s) + 1]
	s[len(s) - 1] = v
}


inside_circle :: proc(p: Point, circle: Circle) -> bool {
	dx := circle.center.x - p.x
	dy := circle.center.y - p.y
	dist := dx * dx + dy * dy
	return dist <= circle.radius
}

circum_circle :: proc(p1, p2, p3: Point) -> Circle {
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

// Inside triangle functions are not used... might be useful for optimization
// so we are keeping them for now

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
