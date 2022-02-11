import truss3D/[models, shaders, textures]
import resources, cameras
import pixie

proc makeShadow(radiusPercent = 0.75, size = 256): Image =
  result = newImage(size, size)
  let ctx = newContext(result)
  ctx.fillStyle = rgba(0, 0, 0, 255)
  ctx.fillCircle(circle(vec2(size / 2), size / 2 * radiusPercent))

var
  shadowModel: Model
  shadowShader: Shader
  shadowTex: Texture

addResourceProc:
  shadowShader = loadShader("vert.glsl", "shadow.glsl")
  shadowModel = loadModel("pickup_quad.dae")
  shadowTex = genTexture()
  makeShadow(1).copyTo shadowTex

proc renderShadow*(camera: Camera, pos, scale: Vec3, opacity = 0.75) = 
  with shadowShader:
    shadowShader.setUniform("opacity", opacity)
    let 
      pos = vec3(pos.x, pos.y, pos.z)
      shadowMatrix = (mat4() * translate(pos)) * scale(scale)
    shadowShader.setUniform("mvp", camera.orthoView * shadowMatrix)
    shadowShader.setUniform("tex", shadowTex)
    render(shadowModel)