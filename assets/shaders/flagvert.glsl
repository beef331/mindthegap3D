#version 430

layout(location = 0) in vec3 vertex_position;
layout(location = 1) in vec3 normal;
layout(location = 2) in vec2 uv;
layout(location = 3) in vec4 colour;


uniform mat4 mvp;
uniform mat4 m;
uniform float time;
out vec4 fColour;
out vec3 fNormal;
out vec2 fuv;


void main() {
  vec3 pos = vertex_position;
  if(colour.r > 0.0 && colour.g <= 0.1 && colour.b <= 0.1){ // Lazy way to find "red"
    pos.z += cos(time * pos.x * 30) * 0.05 * pos.x;
  }

  gl_Position = mvp * vec4(pos, 1.0);
  fColour = colour;
  fNormal = normalize((mat3(m) * normal).xyz);
  fuv = uv;
}
