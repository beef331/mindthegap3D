#version 430

layout(location = 0) in vec3 vertex_position;
layout(location = 2) in vec2 uv;

uniform mat4 matrix;

out vec2 fuv;


void main() {
  gl_Position = matrix * vec4(vertex_position, 1);
  fuv = uv;
}
