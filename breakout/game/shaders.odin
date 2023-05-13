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

postprocess_vertex_source := `#version 330 core
layout(location=0) in vec2 aPos;
layout(location=1) in vec2 aTexCoords;

out vec2 TexCoords;

uniform bool chaos;
uniform bool confuse;
uniform bool shake;
uniform float time;

void main() {
	gl_Position = vec4(aPos, 0.0f, 1.0f);
	if (chaos) {
		float strength = 0.3;
		vec2 pos = vec2(aTexCoords.x + sin(time) * strength, aTexCoords.y + cos(time) * strength);
		TexCoords = pos;
	} else if (confuse) {
		TexCoords = vec2(1.0 - aTexCoords.x, 1.0 - aTexCoords.y);
	} else {
		TexCoords = aTexCoords;
	}
	if (shake) {
		float strength = 0.005;
		gl_Position.x += cos(time * 50) * strength;
		gl_Position.y += cos(time * 75) * strength;
	}
}
`

postprocess_fragment_source := `#version 330 core
in vec2 TexCoords;
out vec4 color;

uniform sampler2D scene;
uniform vec2	  offsets[9];
uniform int		  edge_kernel[9];
uniform float	  blur_kernel[9];

uniform bool chaos;
uniform bool confuse;
uniform bool shake;

void main() {
	color = vec4(0.0f);
	vec3 sample[9];
	if (chaos || shake) {
		for (int i=0; i<9; i++) {
			sample[i] = vec3(texture(scene, TexCoords.st + offsets[i]));
		}
	}
	if (chaos) {
		for (int i=0; i<9; i++) {
			color += vec4(sample[i] * edge_kernel[i], 0.0f);
		}
		color.a = 1.0f;
	} else if (confuse) {
		color = vec4(1.0 - texture(scene, TexCoords).rgb, 1.0);
	} else if (shake) {
		color = texture(scene, TexCoords) * 0.6;
		for (int i=0; i<9; i++) {
			color += vec4(sample[i] * blur_kernel[i] * 0.4, 0.0f);
		}
		color.a = 1.0f;
	} else {
		color = texture(scene, TexCoords);
	}
}
`
