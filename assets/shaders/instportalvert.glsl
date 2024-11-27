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
out vec3 local;
out vec3 origColour;

struct data{
  int portalIndex;
  mat4 matrix;
};


layout(std430, binding = 0) buffer instanceData{
  data instData[];
};

const vec4 portalColor[7] = vec4[](
  vec4(1, 0, 0, 1),
  vec4(0, 1, 0, 1),
  vec4(0, 0, 1, 1),
  vec4(1, 1, 0, 1),
  vec4(1, 0, 1, 1),
  vec4(0, 1, 1, 1),
  vec4(1, 0, 1, 1)
);

void main() {
  data theData = instData[gl_InstanceID];
  mat4 matrix = theData.matrix;
  mat3 normToWorld = mat3(matrix);
  gl_Position =  vp * matrix * vec4(vertex_position, 1);
  local = vertex_position;
  origColour = colour.rgb;
  fColour = mix(colour, portalColor[theData.portalIndex], float(colour.rgb == vec3(1)));

  fNormal = normalize(normToWorld * normal).xyz;
}
