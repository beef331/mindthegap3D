#version 430

out vec4 frag_colour;
in vec4 color;

void main() {
  frag_colour = color;
}
