#version 430
in vec3 pos;

out vec4 frag_colour;

uniform sampler2D tex;
in vec4 fColour;
void main() {
  //frag_colour.xy = fUv.xy;
  frag_colour = fColour;
}