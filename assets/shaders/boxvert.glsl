#version 430

layout(location = 0) in vec3 vertex_position;
layout(location = 1) in vec3 normal;
layout(location = 2) in vec2 uv;
layout(location = 3) in vec4 colour;


uniform mat4 mvp;
uniform mat4 m;
uniform int isWalkable;

uniform vec4 walkColour;
uniform vec4 notWalkableColour;

out vec4 fColour;
out vec3 fNormal;
out vec2 fuv;

void main() {
  gl_Position = mvp * vec4(vertex_position, 1.0);
  fColour = colour;
  if(fColour.rgb == vec3(1, 1, 1)){
    if(isWalkable == 1){
      fColour = walkColour;
    }else{
      fColour = notWalkableColour;
    }
  }
  fNormal = normalize((mat3(m) * normal).xyz);
  fuv = uv;
}
