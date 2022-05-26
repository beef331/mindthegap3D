#version 430
out vec4 frag_colour;

uniform vec4 invalidColour;
uniform float opacity;
uniform bool valid;


in vec4 fColour;
in vec3 fNormal;
in vec3 pos;


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
  if (opacity < threshold[x % 4][y % 4])
      discard;
  float light = (1 - dot(fNormal, normalize(vec3(-1, -1, 0))));
  frag_colour = (valid ? fColour: invalidColour) * light;
}
