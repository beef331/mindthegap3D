#version 430

layout(location = 0) in vec3 vertex_position;
layout(location = 1) in vec3 normal;
layout(location = 2) in vec2 uv;
layout(location = 3) in vec4 colour;


uniform mat4 vp;
out vec4 fColour;
out vec3 fNormal;
out vec2 fuv;

struct data{
  int state;
  mat4 matrix;
};

layout(std430, binding = 0) buffer instanceData{
  data instData[];
};

void main() {
  mat4 matrix = instData[gl_InstanceID].matrix;
  mat3 normToWorld = mat3(matrix);
  gl_Position =  vp * matrix * vec4(vertex_position, 1);
  fColour = colour;
  fNormal = normalize(normToWorld * normal).xyz;
  fuv = uv;
}
