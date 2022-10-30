#version 430
out vec4 frag_colour;


in vec4 fColour;
in vec3 fNormal;
in vec3 pos;
in vec2 fuv;
flat in int texId;

uniform sampler2DArray textures;


void main() {
  frag_colour = texture(textures, vec3(fuv, float(texId)));
  if(frag_colour.a - 0.1 < 0){
    discard;
  }
}
