#version 430
out vec4 frag_colour;

uniform float time;

in vec4 fColour;
in vec3 fNormal;
in vec3 pos;
in vec2 fuv;



mat4 threshold = mat4
(
    1.0 / 17.0,   9.0 / 17.0,   3.0 / 17.0,   11.0 / 17.0,
    13.0 / 17.0,  5.0 / 17.0,   15.0 / 17.0,  7.0 / 17.0,
    4.0 / 17.0,   12.0 / 17.0,  2.0 / 17.0,   10.0 / 17.0,
    16.0 / 17.0,  8.0 / 17.0,   14.0 / 17.0,  6.0 / 17.0
);

void main() {
  int x = int(gl_FragCoord.x - 0.5);
  int y = int(gl_FragCoord.y - 0.5);


  frag_colour.a += 1 - abs(sin(pos.y + time * 3));

  frag_colour.a = clamp(frag_colour.a, 0.3, 1);

  if(frag_colour.a < threshold[x % 4][y % 4] || abs(1 - pos.y) < 0.1)
      discard;

  float oldAlpha = frag_colour.a;
  frag_colour = fColour;
  frag_colour.rgb += frag_colour.rgb * (1 + oldAlpha);
 
  }
