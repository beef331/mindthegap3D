#version 430
out vec4 frag_colour;

uniform sampler2D tex;
uniform mat4 mvp;
uniform float time;
in vec3 pos;
void main() {
  vec2 uv = (mvp * vec4(pos, 1)).xy * 0.5 + 0.5;
  float depth = texture(tex, uv).r;
  float foam = 1 - (abs(depth - gl_FragCoord.z) / 0.03);
  frag_colour = mix(vec4(0, 0, 1, 1), vec4(1, 1, 1, 1), foam);
}