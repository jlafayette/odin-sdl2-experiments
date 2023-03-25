package delaunay_triangulation

import "core:fmt"
import "core:math"
import "core:container/queue"
import "core:math/linalg/glsl"

I_Verts :: distinct [3]int
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


triangulate :: proc(points: ^[dynamic]Point, verts: ^[dynamic]I_Verts) -> (int, int) {
	clear_dynamic_array(verts)

	// find min and max boundries of the point cloud
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


	// TODO: sort points by proximity
	// This is an optimization, so it's ok to skip for now

	// keep track of number of points (keeping for now to have 1 to 1 with c code reference)
	num_points := len(points)

	// add super triangle around our points
	append(points, Point{-100, -100}, Point{100, -100}, Point{0, 100})
	num_points += 3

	// setup required data structures
	// verts is which vertices are part of which triangles (this is arg in this version)
	append(verts, I_Verts{len(points) - 3, len(points) - 2, len(points) - 1})
	// tris keeps track of adjacent triangles, counting in the same direction as the vertices
	tris := make([dynamic][3]int, 0, len(verts))
	defer delete(tris)
	append(&tris, [3]int{-1, -1, -1}) // -1 means there are no adjacent triangles
	n_t: int = 1 // TODO: use len(tris)?
	triangle_stack_backing := make([dynamic]int, 0, num_points - 3)
	defer delete(triangle_stack_backing)
	triangle_stack := queue.Queue(int){}
	queue.init_from_slice(&triangle_stack, triangle_stack_backing[:])
	// insert all points and triangulate one by one
	for ii := 0; ii < num_points - 3; ii += 1 {
		// find triangle T which contains points[i]
		j: int = n_t - 1
		for {
			if point_within_triangle(
				   points[ii],
				   points[verts[j][0]],
				   points[verts[j][1]],
				   points[verts[j][2]],
			   ) {
				n_t += 2
				// delete triangle t and replace it with three sub-triangles touching P
				append(
					verts,
					I_Verts{ii, verts[j][1], verts[j][2]},
					I_Verts{ii, verts[j][2], verts[j][0]},
				)
				// update adjacencies of triangles surrounding the old triangle
				// fix adjaceny of A
				adj1 := tris[j][0]
				adj2 := tris[j][1]
				adj3 := tris[j][2]
				if adj1 >= 0 {
					for m := 0; m < 3; m += 1 {
						if tris[adj1][m] == j {
							tris[adj1][m] = j // does this even do anything?
							break
						}
					}
				}
				if adj2 >= 0 {
					for m := 0; m < 3; m += 1 {
						if tris[adj2][m] == j {
							tris[adj2][m] = n_t - 2
							break
						}
					}
				}
				if adj3 >= 0 {
					for m := 0; m < 3; m += 1 {
						if tris[adj3][m] == j {
							tris[adj3][m] = n_t - 1
							break
						}
					}
				}
				// adjacencies of new triangles
				{
					t_2 := [3]int{j, tris[j][1], n_t - 1}
					if len(tris) <= n_t - 2 {
						append(&tris, t_2)
					} else {
						tris[n_t - 2] = t_2
					}

					// tris[n_t - 2][0] = j
					// tris[n_t - 2][1] = tris[j][1]
					// tris[n_t - 2][2] = n_t - 1
					t_1 := [3]int{n_t - 2, tris[j][2], j}
					if len(tris) <= n_t - 1 {
						append(&tris, t_1)
					} else {
						tris[n_t - 1] = t_1
					}
					// tris[n_t - 1][0] = n_t - 2
					// tris[n_t - 1][1] = tris[j][2]
					// tris[n_t - 1][2] = j
				}

				// replace v3 of containing triangle with P and rotate to v1
				verts[j][2] = verts[j][1]
				verts[j][1] = verts[j][0]
				verts[j][0] = ii
				// replace 1st and 3rd adjacencies of containing triangle with new triangles
				tris[j][1] = tris[j][0]
				tris[j][2] = n_t - 2
				tris[j][0] = n_t - 1
				// place each triangle containing P onto a stack, if the edge opposite P has an adj tri
				if tris[j][1] >= 0 {
					queue.push_back(&triangle_stack, j)
				}
				if tris[n_t - 2][1] >= 0 {
					queue.push_back(&triangle_stack, n_t - 2)
				}
				if tris[n_t - 1][1] >= 0 {
					queue.push_back(&triangle_stack, n_t - 1)
				}
				// looping through the stack
				for {
					L, ok := queue.pop_back_safe(&triangle_stack)
					if !ok {
						break
					}
					v1 := Point{points[verts[L][2]][0], points[verts[L][2]][1]}
					v2 := Point{points[verts[L][1]][0], points[verts[L][1]][1]}
					opp_vert := -1
					opp_vert_id := -1
					for k := 0; k < 3; k += 1 {
						if (verts[tris[L][1]][k] != verts[L][1]) &&
						   (verts[tris[L][1]][k]) != verts[L][2] {
							opp_vert = verts[tris[L][1]][k]
							opp_vert_id = k
							break
						}
					}
					v3 := Point{points[opp_vert][0], points[opp_vert][1]}
					P := Point{points[ii][0], points[ii][1]}

					// check if P in circumcircle of triangle on top of stack
					circle2 := circum_circle(v1, v2, v3)
					if inside(P, circle2) {
						// swap diagonal, and redo triangles L R A & C
						R := tris[L][1]
						C := tris[L][2]
						A := tris[R][opp_vert_id % 3]
						// fix adjacency of A
						if A >= 0 {
							for m := 0; m < 3; m += 1 {
								if tris[A][m] == R {
									tris[A][m] = L
									break
								}
							}
						}
						// fix adjacency of C
						for C >= 0 {
							for m := 0; m < 3; m += 1 {
								if tris[C][m] == L {
									tris[C][m] = R
									break
								}
							}
						}
						// fix adjacency of R
						for m := 0; m < 3; m += 1 {
							if verts[R][m] == opp_vert {
								verts[R][(m + 2) % 3] = ii
								break
							}
						}
						for m := 0; m < 3; m += 1 {
							if tris[R][m] == L {
								tris[R][m] = C
								break
							}
						}
						for m := 0; m < 3; m += 1 {
							if tris[R][m] == A {
								tris[R][m] = L
								break
							}
						}
						for m := 0; m < 3; m += 1 {
							if verts[R][0] != ii {
								temp1 := verts[R][0]
								temp2 := tris[R][0]
								verts[R][0] = verts[R][1]
								verts[R][1] = verts[R][2]
								verts[R][2] = temp1
								tris[R][0] = tris[R][1]
								tris[R][1] = tris[R][2]
								tris[R][2] = temp2
								// swizzle?
							}
						}

						// fix vertices and adjaceny of L
						verts[L][2] = opp_vert
						for m := 0; m < 3; m += 1 {
							if tris[L][m] == C {
								tris[L][m] = R
								break
							}
						}
						for m := 0; m < 3; m += 1 {
							if tris[L][m] == R {
								tris[L][m] = A
								break
							}
						}
						// add L and R to stack if they have triangles opposite P
						if tris[L][1] >= 0 {
							queue.push_back(&triangle_stack, L)
						}
						if tris[R][1] >= 0 {
							queue.push_back(&triangle_stack, R)
						}

					}
				}
				break

			}
			// did not break so...
			// adjust j in the direction of target point ii
			AB := Point{
				points[verts[j][1]][0] - points[verts[j][0]][0],
				points[verts[j][1]][1] - points[verts[j][0]][1],
			}
			BC := Point{
				points[verts[j][2]][0] - points[verts[j][1]][0],
				points[verts[j][2]][1] - points[verts[j][1]][1],
			}
			CA := Point{
				points[verts[j][0]][0] - points[verts[j][2]][0],
				points[verts[j][0]][1] - points[verts[j][2]][1],
			}
			AP := Point{
				points[ii][0] - points[verts[j][0]][0],
				points[ii][1] - points[verts[j][0]][1],
			}
			BP := Point{
				points[ii][0] - points[verts[j][1]][0],
				points[ii][1] - points[verts[j][1]][1],
			}
			CP := Point{
				points[ii][0] - points[verts[j][2]][0],
				points[ii][1] - points[verts[j][2]][1],
			}
			N1 := Point{AB[1], -AB[0]}
			N2 := Point{BC[1], -BC[0]}
			N3 := Point{CA[1], -CA[0]}
			S1 := AP[0] * N1[0] + AP[1] * N1[1]
			S2 := BP[0] * N2[0] + BP[1] * N2[1]
			S3 := CP[0] * N3[0] + CP[1] * N3[1]
			if ((S1 > 0) && (S1 >= S2) && (S1 >= S3)) {
				j = tris[j][0]
			} else if ((S2 > 0) && (S2 >= S1) && (S2 >= S3)) {
				j = tris[j][1]
			} else if ((S3 > 0) && (S3 >= S1) && (S3 >= S2)) {
				j = tris[j][2]
			}
		}
	}

	fmt.println("verts1", verts)

	// count how many triangles we have that don't involve supertriangle vertices
	// ...
	// delete any triangles that contain the supertriangle vertices
	verts_final := make([dynamic]I_Verts, 0, n_t)
	defer delete(verts_final)
	for i := 0; i < n_t; i += 1 {
		if ((verts[i][0] < (num_points - 3)) &&
			   (verts[i][1] < (num_points - 3)) &&
			   (verts[i][2] < (num_points - 3))) {
			append(&verts_final, verts[i])
		}
	}
	fmt.println("verts_final:", verts_final)

	// undo the 0-1 mapping
	for p, i in points {
		points[i].x = p.x * d + xmin
		points[i].y = p.y * d + ymin
	}
	fmt.println("points", points)

	clear_dynamic_array(verts)
	for v in verts_final {
		append(verts, v)
	}
	fmt.println("verts2:", verts)

	// this is a weird standin for a slice...
	return len(points) - 3, len(verts)
}

to_int :: proc "contextless" (b: bool) -> int {
	if b {
		return 1
	} else {
		return 0
	}
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

point_within_triangle :: proc "contextless" (P, V1, V2, V3: Point) -> bool {
	AB := Point{V2[0] - V1[0], V2[1] - V1[1]}
	BC := Point{V3[0] - V2[0], V3[1] - V2[1]}
	CA := Point{V1[0] - V3[0], V1[1] - V3[1]}
	AP := Point{P[0] - V1[0], P[1] - V1[1]}
	BP := Point{P[0] - V2[0], P[1] - V2[1]}
	CP := Point{P[0] - V3[0], P[1] - V3[1]}

	N1 := Point{AB[1], -AB[0]}
	N2 := Point{BC[1], -BC[0]}
	N3 := Point{CA[1], -CA[0]}

	S1: f32 = AP[0] * N1[0] + AP[1] * N1[1]
	S2: f32 = BP[0] * N2[0] + BP[1] * N2[1]
	S3: f32 = CP[0] * N3[0] + CP[1] * N3[1]

	tolerance: f32 = 0.0001

	if ((S1 < 0 && S2 < 0 && S3 < 0) ||
		   (S1 < tolerance && S2 < 0 && S3 < 0) ||
		   (S2 < tolerance && S1 < 0 && S3 < 0) ||
		   (S3 < tolerance && S1 < 0 && S2 < 0)) { 	// inside triangle
		return true
	} else {
		return false
	}
}
