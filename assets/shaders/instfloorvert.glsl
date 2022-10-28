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

struct data{
  int nearPlayer;
  mat4 matrix;
};


layout(std430, binding = 0) buffer instanceData{
  data instData[];
};

void main() {
  data theData = instData[gl_InstanceID];
  mat4 matrix = theData.matrix;
  mat3 normToWorld = mat3(matrix);
  gl_Position =  vp * matrix * vec4(vertex_position, 1);
  fColour = colour;
  if(fColour.rgb == vec3(1)){
    fColour.rgb /= float(theData.nearPlayer);
  }

  fNormal = normalize(normToWorld * normal).xyz;
  fuv = uv;
}
