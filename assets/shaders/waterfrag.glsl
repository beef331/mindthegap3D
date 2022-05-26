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

const vec4 waterColor = vec4(0, 0.3, 0.7, 1);

void main() {
  vec2 uv = (mvp * vec4(pos, 1)).xy * 0.5 + 0.5;
  float depth = texture(depthTex, uv).r;
  float sineVal = (0.02 + sin(time * 2 + pos.x + pos.y) * 0.01);
  float foam = 1 - (abs(gl_FragCoord.z - depth) / sineVal);
  float rectDist = rectangle(worldPos.xz - worldSize / 2, worldSize / 2 + vec2(0.4) + vec2(sineVal * 10));
  if(abs(0.75 - rectDist) < 0.25){
    foam = rectDist;
    vec2 newVs = worldPos.xz + (0.02 + sin(time * 2 + pos.x + pos.y) * 0.1);
    newVs += vec2(time * 0.1);
    float foamSample = texture(waterTex, newVs).r;
    newVs.x += -time * 0.3;
    newVs.y += -time * 0.2;
    foamSample += texture(waterTex, newVs).r * 0.3;
    foamSample = abs(0.75 - rectDist) > 0.2 ? 1: foamSample;
    frag_colour = mix(vec4(1), waterColor, 1 - foamSample);
  }else if(rectDist >= 1){
    frag_colour =  waterColor + texture(waterTex, worldPos.xz + vec2(0, sineVal * 5) + vec2(time / 2, time / 4)).r * 0.3;
  }else{
    foam = clamp(foam, 0, 1);
    frag_colour = mix(texture(colourTex, uv) * 0.6 + vec4(0, 0.2, 0.7, 1), waterColor,  (1 - foam) * (1 - foam));
    float foamStepDist = 0.3;
    float foamRound = round(foam / foamStepDist) * foamStepDist;
    frag_colour += vec4(clamp(float(foam > 0.7) * foamRound, 0.0, 1.0));
  }
}
