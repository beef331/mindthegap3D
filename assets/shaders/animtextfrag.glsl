#version 430
out vec4 frag_colour;


in vec4 fColour;
in vec3 fNormal;
in vec3 pos;
in vec2 fuv;

uniform sampler2D tex;
uniform float progress;

void main() {
  vec4 col = texture(tex, fuv);
  if(col.r >= progress || col.a - 0.99 < 0){
    discard;
  }
  frag_colour = vec4(1);
}
