package game

import glm "core:math/linalg/glsl"

GameObject :: struct {
	sprite:   Texture2D,
	pos:      glm.vec2,
	size:     glm.vec2,
	rotation: f32,
	velocity: f32,
	color:    glm.vec3,
}
