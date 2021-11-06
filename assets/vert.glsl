#version 430

layout(location = 0) in vec3 vertex_position;
layout(location = 3) in vec4 colour;


uniform mat4 mvp;
out vec4 fColour;


void main() {
  gl_Position = mvp * vec4(vertex_position, 1.0);
  fColour = colour;
}