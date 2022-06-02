#version 430
layout(location = 0) in vec3 vertex_position;


uniform mat4 VP;

layout(std430) struct data{
  vec4 color;
  vec3 pos;
  float lifeTime;
  vec4 scale; // Last float is reserved
  vec3 velocity;
  float reserved; // Not needed but here to match the CPU side
};

layout(std430, binding = 1) buffer instanceData{
  data instData[];
};

out float time;
out vec4 color;

void main(){
  data theData = instData[gl_InstanceID];
  vec3 newPos = theData.scale.xyz * vertex_position + theData.pos.xyz;
  gl_Position = VP * vec4(newPos, 1);
  color = theData.color;
}
