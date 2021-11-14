#version 430

layout(location = 0) in vec3 vertex_position;
layout(location = 2) in vec2 vUv;



uniform mat4 mvp;
out vec3 pos;
out vec2 fUv;

void main() {
  pos = vertex_position;
  gl_Position = mvp * vec4(vertex_position, 1);
  fUv = vUv;
}