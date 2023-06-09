#version 430

layout(location = 0) in vec3 vertex_position;
layout(location = 1) in vec3 normal;
layout(location = 3) in vec4 colour;


uniform mat4 vp;
uniform float time;

out vec4 fColour;
out vec3 fNormal;

struct data{
  float velocity;
  mat4 matrix;
};


layout(std430, binding = 0) buffer instanceData{
  data instData[];
};

void main() {
  data theData = instData[gl_InstanceID];
  mat4 matrix = theData.matrix;
  mat3 normToWorld = mat3(matrix);
  vec3 pos = vertex_position;
  pos.x += sin(time * theData.velocity + pos.z) / 3.0;
  gl_Position =  vp * matrix * vec4(pos.xyz, 1.0);
  fColour = colour;

  fNormal = normalize(normToWorld * normal).xyz;
}
