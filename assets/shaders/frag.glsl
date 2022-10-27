#version 430
out vec4 frag_colour;


in vec4 fColour;
in vec3 fNormal;
in vec3 pos;
in vec2 fuv;

void main() {
  frag_colour = fColour * (1 - dot(fNormal, normalize(vec3(-1, -1, 0))));
}
