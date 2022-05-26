#version 430

layout(location = 0) in vec3 vertex_position;
layout(location = 1) in vec3 normal;
layout(location = 2) in vec2 uv;
layout(location = 3) in vec4 colour;


uniform mat4 mvp;
uniform mat4 m;
out vec4 fColour;
out vec3 fNormal;
out vec2 fuv;


void main() {
  gl_Position = mvp * vec4(vertex_position, 1.0);
  fColour = colour;
  fNormal = normalize((mat3(m) * normal).xyz);
  fuv = uv;
}
