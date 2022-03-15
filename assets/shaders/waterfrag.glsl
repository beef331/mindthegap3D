#version 430
out vec4 frag_colour;

uniform sampler2D depthTex;
uniform sampler2D colourTex;
uniform sampler2D waterTex;
uniform mat4 modelMatrix;
uniform mat4 mvp;
uniform float time;
uniform vec2 worldSize;

in vec3 pos;
in vec2 fUv;
in vec3 worldPos;

float rectangle(vec2 samplePosition, vec2 halfSize){
    vec2 componentWiseEdgeDistance = abs(samplePosition) - halfSize;
    float outsideDistance = length(max(componentWiseEdgeDistance, 0));
    float insideDistance = min(max(componentWiseEdgeDistance.x, componentWiseEdgeDistance.y), 0);
    return outsideDistance + insideDistance;
}


void main() {
  vec2 uv = (mvp * vec4(pos, 1)).xy * 0.5 + 0.5;
  float depth = texture(depthTex, uv).r;
  float sineVal = (0.02 + sin(time * 2 + pos.x + pos.y) * 0.01);
  float foam = 1 - (abs(gl_FragCoord.z - depth) / sineVal);
  float rectDist = rectangle(worldPos.xz - worldSize / 2, worldSize / 2 + vec2(0.4) + vec2(sineVal * 10));
  if(rectDist >= 0.5 && rectDist < 1){
    foam = rectDist;
    vec2 newVs = worldPos.xz + (0.02 + sin(time * 2 + pos.x + pos.y) * 0.1);
    newVs += vec2(time * 0.1);
    float foamSample = texture(waterTex, newVs).r;
    newVs.x += -time * 0.3;
    newVs.y += -time * 0.2;
    foamSample += texture(waterTex, newVs).r * 0.3;
    foamSample = abs(0.75 - rectDist) > 0.2 ? 1: foamSample;
    frag_colour = mix(vec4(1, 1, 1, 1), vec4(0, 0, 1, 1), 1 - foamSample);
  }else{
    frag_colour = mix(vec4(0, 0, 1, 1), vec4(0, 0.6, 1, 1), foam);
    frag_colour += vec4(clamp(float(foam > 0.7) * round(foam / 0.3) * 0.3, 0.0, 1.0));
  }
}
