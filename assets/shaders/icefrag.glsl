#version 430
out vec4 frag_colour;


in vec4 fColour;
in vec3 fNormal;
in vec3 pos;
in vec2 fuv;
in vec2 samplePos;

uniform sampler2D screenTex;

void main() {
  vec2 uv = samplePos;// / vec2(textureSize(screenTex, 0));
  frag_colour = texture(screenTex, uv) * 0.3 + fColour;
  frag_colour = mix(frag_colour, frag_colour * (1 - dot(fNormal, normalize(vec3(-1, -1, 0)))), 0.7);
}
