#version 430
out vec4 frag_colour;

uniform float signColour;

void main() {
  frag_colour = vec4(signColour);
}