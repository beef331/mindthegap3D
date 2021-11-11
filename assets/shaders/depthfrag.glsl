#version 430
out vec4 frag_colour;


in vec4 fColour;

void main() {
  frag_colour = vec4(gl_FragCoord.z / gl_FragCoord.w);
}