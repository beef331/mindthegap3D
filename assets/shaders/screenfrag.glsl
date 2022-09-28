
/* License for Aces function
Copyright (C) 2019 the internet and Damien Seguin

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
*/



#version 430
out vec4 frag_colour;

in vec2 fuv;
uniform sampler2D tex;
uniform sampler2D uiTex;
uniform float finishProgress;
uniform vec2 playerPos;

vec3 aces(vec3 x) {
  const float a = 2.51;
  const float b = 0.03;
  const float c = 2.43;
  const float d = 0.59;
  const float e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}


void main() {
  vec4 uiColor = texture(uiTex, fuv);
  vec4 col = texture(tex, fuv);
  col.rgb = aces(col.rgb);
  frag_colour.rgb = uiColor.rgb + col.rgb * (1 - uiColor.a);
  vec2 texSize = vec2(textureSize(tex, 0));
  vec2 realPlayerPos = vec2(playerPos) / texSize;
  realPlayerPos.y = 1 - realPlayerPos.y;
  vec2 offsetUv = fuv * vec2(1, (texSize.y / texSize.x)) - realPlayerPos * vec2(1, (texSize.y / texSize.x)) ;
  if(finishProgress > 0){
    frag_colour.rgb *= float(length(offsetUv) < clamp(finishProgress, 0, 1));
  }
}
