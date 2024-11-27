#version 430
out vec4 frag_colour;


in vec4 fColour;
in vec3 fNormal;
in vec3 pos;
in vec3 local;
in vec3 origColour;
uniform float time;

void main() {

  if(origColour == vec3(1)){
    float mDist = max(abs(local.x),  abs(local.z));
    float modAmount = ceil((1 - mod(mDist + time / 2, 0.2) / 0.2) + 0.5) / 2;
    frag_colour = fColour * modAmount;

  }else{
    frag_colour = fColour * (1 - dot(fNormal, normalize(vec3(-1, -1, 0))));
  }
}
