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
  int portalId;
  mat4 matrix;
};


layout(std430, binding = 0) buffer instanceData{
  data instData[];
};

const vec3 colors[10] = vec3[10](
  vec3(0, 0, 0.5),
  vec3(0.22, 1, 0.08),
  vec3(1, 0.25, 0.39),
  vec3(0.5, 0.5, 0),
  vec3(1, 0.5, 0),
  vec3(0.85, 0.44, 0.84),
  vec3(0.18, 0.22, 0.23),
  vec3(0, 0.13, 0.28),
  vec3(1.0, 0.94, 0),
  vec3(0.44, 0.11, 0.11)
);

void main() {
  data theData = instData[gl_InstanceID];
  mat3 normToWorld = mat3(theData.matrix);
  gl_Position =  vp * theData.matrix * vec4(vertex_position, 1);
  if(colour == vec4(1)){
    fColour = vec4(colors[theData.portalId], 1);
  }else{
    fColour = colour;
  }    
  fNormal = normalize(normToWorld * normal).xyz;
  fuv = uv;
}
