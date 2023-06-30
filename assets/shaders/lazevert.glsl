#version 430

layout(location = 0) in vec3 vertex_position;
layout(location = 3) in vec4 vCol;

uniform mat4 vp;
out vec4 fCol;

layout(std430, binding = 0) buffer instanceData{
  mat4 instData[];
};

void main() {
  mat4 matrix = instData[gl_InstanceID];
  gl_Position =  vp * matrix * vec4(vertex_position, 1);
  fCol = vCol;
}
