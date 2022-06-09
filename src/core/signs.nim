import vmath, pixie, opengl
import truss3D/[textures, shaders, models]
import cameras, resources

type
  Sign* = object
    pos*: Vec3
    hovered*: bool
    message*: string
    messageTexture: Texture
    progress: float

var
  messageModel: Model
  messageShader: Shader

const messageTime = 0.3f

proc makeQuad(width, height: float32): Model =
  var data: MeshData[Vec3]
  let halfPos = vec3(width / 2, height / 2, 0)
  data.appendVerts([vec3(0) - halfPos, vec3(width, height, 0) - halfPos, vec3(0, height, 0) - halfPos, vec3(width, 0, 0) - halfPos].items)
  data.appendUV([vec2(1, 1), vec2(0, 0), vec2(1, 0), vec2(0, 1)].items)
  data.append([1u32, 0, 2, 0, 1, 3].items)
  result = data.uploadData()


addResourceProc:
  messageShader = loadShader(ShaderPath"texvert.glsl", ShaderPath"alphaclip.glsl")
  messageModel = makeQuad(4, 2)



var font = readFont("assets/fonts/MarradaRegular-Yj0O.ttf")

proc makeSignTexture(sign: var Sign, width = 1024, height = 512, border = 10) =
  let
    img = newImage(width, height)
    ctx = newContext(img)
    rectWidth = width.float - border.float * 2
    rectHeight = height.float - border.float * 2
  ctx.fillStyle = color(1, 1, 1, 1)
  ctx.fillRoundedRect(rect(border.float, border.float, rectWidth, rectHeight), 20, 20, 20, 20)
  font.size = 120
  img.fillText(font.typeset(sign.message, vec2(rectWidth, rectHeight), hAlign = CenterAlign, vAlign = MiddleAlign), translate(vec2(border.float)))

  sign.messageTexture = genTexture()
  img.copyTo(sign.messageTexture)

proc init*(_: typedesc[Sign], pos: Vec3, message: string): Sign =
  var pos = pos
  pos.y = 1.25
  result = Sign(pos: pos, message: message, progress: 0)

proc update*(sign: var Sign, dt: float32) =
  if sign.hovered:
    sign.progress += dt
  else:
    sign.progress -= dt
  sign.progress = clamp(sign.progress, 0, messageTime)
  sign.hovered = false

proc render*(sign: Sign, cam: Camera) =
  if sign.progress > 0:
    with messageShader:
      let
        progress = (sign.progress / messageTime) * (sign.progress / messageTime)
        scale = vec3(progress)
        pos = mix(sign.pos, sign.pos + vec3(0, 3, 0), progress)
        targetUp = cam.up
        targetRot = fromTwoVectors(vec3(0, 0, 1), cam.forward)
        upRot = fromTwoVectors(mat4(targetRot) * vec3(0, 1, 0), targetUp)
        mat = mat4() * translate(pos) * (mat4(upRot) * mat4(targetRot)) * scale(scale)
      messageShader.setUniform("mvp", cam.orthoView * mat)
      messageShader.setUniform("tex", sign.messageTexture)
      render(messageModel)


proc load*(sign: var Sign) =
  sign.makeSignTexture()

proc free*(sign: var Sign) = 
  sign.messageTexture.delete()
