package game

vertex_source := `#version 330 core

layout(location=0) in vec3 aPos;
layout(location=1) in vec4 aColor;

out vec4 vColor;

void main() {
	gl_Position = vec4(aPos, 1.0);
	vColor = aColor;
}
`

fragment_source1 := `#version 330 core

in vec4 vColor;

out vec4 oColor;

void main() {
	oColor = vColor;
}	
`
