#version 430
out vec4 frag_colour;

uniform sampler2D depthTex;
uniform sampler2D colourTex;
uniform sampler2D waterTex;
uniform mat4 mvp;
uniform float time;

in vec3 pos;
in vec2 fUv;
void main() {
  vec2 uv = (mvp * vec4(pos, 1)).xy * 0.5 + 0.5;
  float depth = texture(depthTex, uv).r;
  float foam = 1 - (abs(gl_FragCoord.z - depth) / (0.02 + sin(time * 2 + pos.x + pos.y) * 0.01));
  frag_colour = mix(vec4(0, 0, 1, 1), vec4(0, 0.6, 1, 1), foam);
  frag_colour += vec4(clamp(float(foam > 0.7) * round(foam / 0.3) * 0.3, 0.0, 1.0));
}