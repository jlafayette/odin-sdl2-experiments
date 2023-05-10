package game

sprite_vertex_source := `#version 330 core

layout(location=0) in vec2 aPos;
layout(location=1) in vec2 aTexCoords;

out vec2 TexCoords;

uniform mat4 model;
uniform mat4 projection;

void main() {
	TexCoords = aTexCoords;
	gl_Position = projection * model * vec4(aPos, 0.0, 1.0);
}
`

sprite_fragment_source := `#version 330 core

in vec2 TexCoords;
out vec4 color;

uniform sampler2D image;
uniform vec3 spriteColor;

void main() {
	color = vec4(spriteColor, 1.0) * texture(image, TexCoords);
}
`

particle_vertex_source := `#version 330 core
layout(location=0) in vec2 aPos;
layout(location=1) in vec2 aTexCoords;

out vec2 TexCoords;
out vec4 ParticleColor;

uniform mat4 projection;
uniform vec2 offset;
uniform vec4 color;
uniform float scale;

void main() {
	TexCoords = aTexCoords;
	ParticleColor = color;
	gl_Position = projection * vec4((aPos * scale) + offset, 0.0, 1.0);
}
`

particle_fragment_source := `#version 330 core
in vec2 TexCoords;
in vec4 ParticleColor;
out vec4 color;

uniform sampler2D sprite;

void main() {
	color = (texture(sprite, TexCoords) * ParticleColor);
}
`
