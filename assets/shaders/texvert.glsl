#version 430

layout(location = 0) in vec3 vertex_position;
layout(location = 2) in vec2 uv;


uniform mat4 mvp;

out vec2 fuv;


void main() {
  gl_Position = mvp * vec4(vertex_position, 1.0);
  fuv = uv;
  fuv.x = 1 - uv.x;

}