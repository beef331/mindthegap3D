#version 430

layout(location = 0) in vec3 vertex_position;
layout(location = 1) in vec3 normal;
layout(location = 2) in vec2 uv;
layout(location = 3) in vec4 colour;


uniform mat4 vp;
uniform vec4 activeColour;
uniform vec4 inactiveColour;

out vec4 fColour;
out vec3 fNormal;
out vec2 fuv;
out vec2 samplePos;

struct data{
  mat4 matrix;
};


layout(std430, binding = 0) buffer instanceData{
  data instData[];
};

void main() {
  data theData = instData[gl_InstanceID];
  mat4 matrix = theData.matrix;
  mat3 normToWorld = mat3(matrix);
  vec4 worldPos = matrix * vec4(vertex_position, 1);
  gl_Position =  vp * worldPos;
  fColour = colour;
  fNormal = normalize(normToWorld * normal).xyz;

  vec4 offsetPos = vp * (matrix * vec4(vertex_position - (normal * 0.5), 1));
  vec3 ndc = offsetPos.xyz / offsetPos.w;
  samplePos = ndc.xy * 0.5 + 0.5; 
  fuv = uv;
}
