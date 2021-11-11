#version 430
out vec4 frag_colour;

uniform sampler2D tex;

in vec2 fuv;

void main() {
  frag_colour = texture(tex, fuv);
}