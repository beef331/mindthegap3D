#version 430
out float frag_colour;

uniform float signColour;

void main() {
  frag_colour = signColour;
}