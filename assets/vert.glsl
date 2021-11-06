#version 430

layout(location = 0) in vec3 vertex_position;
layout(location = 1) in vec3 normal;
layout(location = 3) in vec4 colour;


uniform mat4 mvp;
out vec4 fColour;
out vec3 fNormal;


void main() {
  gl_Position = mvp * vec4(vertex_position, 1.0);
  fColour = colour;
  fNormal = normal;
}