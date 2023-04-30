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
