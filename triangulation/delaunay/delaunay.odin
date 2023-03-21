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
Pt :: distinct glsl.vec2

EPSILON :: 1e-4


triangulate :: proc(pxyz: ^[dynamic]Pt, v_backing: ^[dynamic]I_Triangle) -> int {
	// clear_dynamic_array(v)
	if len(pxyz) < 3 {
		return 0
	}

	nv := len(pxyz)
	// clear_dynamic_array(v_backing)
	v := v_backing[:0]


	trimax := 4 * len(pxyz)
	// complete := make([dynamic]bool, trimax, trimax)
	// defer delete(complete)
	emax := 200
	edges := make([dynamic]I_Edge, 0, emax)
	defer delete(edges)

	/*
		find min and max vertex bounds
		this allows for calculation of the bounding triangle
	*/
	xmin := pxyz[0].x
	xmax := xmin
	ymin := pxyz[0].y
	ymax := ymin
	for pt in pxyz {
		xmin = math.min(xmin, pt.x)
		xmax = math.max(xmax, pt.x)
		ymin = math.min(ymin, pt.y)
		ymax = math.max(ymax, pt.y)
	}
	dx := xmax - xmin
	dy := ymax - ymin
	dmax := math.max(dx, dy)
	midx := (xmin + xmax) / 2
	midy := (ymin + ymax) / 2

	/*
		Setup the super triangle
		this encompasses all the points
		The coordinates are added to the end of the vertex list.
		The supertriangle is the first in the tirangle list.
	*/
	{

		p1 := Pt{-100, -100}
		i1 := len(pxyz)
		p2 := Pt{0, 100}
		i2 := len(pxyz) + 1
		p3 := Pt{100, -100}
		i3 := len(pxyz) + 2
		append(pxyz, p1, p2, p3)
		last_i := len(v)
		v = v_backing[:last_i + 1]
		v[last_i] = I_Triangle{i1, i2, i3, false}
		// complete[0] = false
	}

	/*
		Include each point one at a time into the existing mesh
	*/
	fmt.printf("\niloop")
	for i := 0; i < nv; i += 1 {
		xp := pxyz[i].x
		yp := pxyz[i].y
		fmt.printf("\n|%d<%d(%.2f,%.2f)", i, nv, xp, yp)
		clear_dynamic_array(&edges)

		/*
			Set up the edge buffer
			if the point(xp, yp) is inside the circumcircle then the
			three edges of that triangle are added to the edge buffer and
			that triangle is removed
		*/
		ntri := len(v)
		fmt.printf("\n  jloop.%d", ntri)

		for j := 0; j < ntri; j += 1 {
			fmt.printf("|%d<%d", j, ntri)
			if v[j].complete {
				continue
			}
			x1 := pxyz[v[j].p1].x
			y1 := pxyz[v[j].p1].y
			x2 := pxyz[v[j].p2].x
			y2 := pxyz[v[j].p2].y
			x3 := pxyz[v[j].p3].x
			y3 := pxyz[v[j].p3].y
			inside, xc, yc, r := circum_circle(xp, yp, x1, y1, x2, y2, x3, y3)
			if (xc < xp && ((xp - xc) * (xp - xc)) > r) {
				v[j].complete = true
			}
			if inside {
				append(&edges, I_Edge{v[j].p1, v[j].p2})
				append(&edges, I_Edge{v[j].p2, v[j].p3})
				append(&edges, I_Edge{v[j].p3, v[j].p1})
				v[j] = v[ntri - 1]
				v = v_backing[:len(v) - 1]
				ntri -= 1
				j -= 1
			}
		}

		/*
			Tag multiple edges
		*/
		for j := 0; j < len(edges); j += 1 {
			for k := j + 1; k < len(edges); k += 1 {
				if ((edges[j].p1 == edges[k].p2) && (edges[j].p2 == edges[k].p1)) {
					edges[j].p1 = -1
					edges[j].p2 = -1
					edges[k].p1 = -1
					edges[k].p2 = -1
				}
				// In case of anticlockwise (shouldn't be needed)
				if ((edges[j].p1 == edges[k].p1) && (edges[j].p2 == edges[j].p2)) {
					edges[j].p1 = -1
					edges[j].p2 = -1
					edges[k].p1 = -1
					edges[k].p2 = -1
				}
			}
		}

		/*
			Form new triangles for the current point
			skipping over any tagged edges.
			All edges are arranged in clockwise order
		*/
		for j := 0; j < len(edges); j += 1 {
			if edges[j].p1 < 0 || edges[j].p2 < 0 {
				continue
			}
			last_i := len(v)
			v = v_backing[:last_i + 1]
			v[last_i] = I_Triangle{edges[j].p1, edges[j].p2, i, false}
			// append(v, I_Triangle{edges[j].p1, edges[j].p2, i, false})
			// complete[len(v) - 1] = false
		}
	}

	/*
		Remove triangles with supertriangle vertices
		These are triangles that have a vertex number greater than nv
	*/
	for i := 0; i < len(v); i += 1 {
		if v[i].p1 >= nv || v[i].p2 >= nv || v[i].p3 >= nv {
			// TODO: figure out how to shrink dynamic array
			// Maybe use a slice?
		}
	}
	return len(v)
}

circum_circle :: proc(xp, yp, x1, y1, x2, y2, x3, y3: f32) -> (bool, f32, f32, f32) {
	xc: f32 = 0
	yc: f32 = 0
	rsqr: f32 = 0

	fabsy1y2 := math.abs(y1 - y2)
	fabsy2y3 := math.abs(y2 - y3)

	if fabsy1y2 < EPSILON && fabsy2y3 < EPSILON {
		return false, xc, yc, rsqr
	}
	if fabsy1y2 < EPSILON {
		m2 := -(x3 - x2) / (y3 - y2)
		mx2 := (x2 + x3) / 2
		my2 := (y2 + y3) / 2
		xc = (x2 + x1) / 2
		yc = m2 * (xc - mx2) + my2
	} else if fabsy2y3 < EPSILON {
		m1 := -(x2 - x1) / (y2 - y1)
		mx1 := (x1 + x2) / 2
		my1 := (y1 + y2) / 2
		xc = (x3 + x2) / 2
		yc = m1 * (xc - mx1) + my1
	} else {
		m1 := -(x2 - x1) / (y2 - y1)
		m2 := -(x3 - x2) / (y3 - y2)
		mx1 := (x1 + x2) / 2
		mx2 := (x2 + x3) / 2
		my1 := (y1 + y2) / 2
		my2 := (y2 + y3) / 2
		xc = (m1 * mx1 - m2 * mx2 + my2 - my1) / (m1 - m2)
		if fabsy1y2 > fabsy2y3 {
			yc = m1 * (xc - mx1) + my1
		} else {
			yc = m2 * (xc - mx2) + my2
		}
	}

	dx := x2 - xc
	dy := y2 - yc
	rsqr = dx * dx + dy * dy
	dx = xp - xc
	dy = yp - yc
	drsqr := dx * dx + dy * dy

	result := (drsqr - rsqr) <= EPSILON
	return result, xc, yc, rsqr
}
