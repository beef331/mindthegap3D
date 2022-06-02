import truss3D
import vmath
import chroma
import pixie
import truss3D/[shaders, textures, gui]
import core/[worlds, resources, cameras, players, directions, tiles]
import std/[os, sugar]

shaderPath = "assets/shaders"
modelPath = "assets/models"

const camDefaultSize = 8f
var
  camera: Camera
  world: World
  mainBuffer, signBuffer, uiBuffer: FrameBuffer
  depthShader, waterShader, screenShader: Shader
  waterQuad, screenQuad: Model
  waterTex: Texture


proc makeRect(w, h: float32): Model =
  var data: MeshData[Vec3]
  data.appendVerts:
    [
      vec3(0, 0, 0), vec3(w, 0, h),
      vec3(0, 0, h),
      vec3(w, 0, 0)
    ].items
  data.append([0u32, 1, 2, 0, 3, 1].items)
  data.appendUv([vec2(0, 0), vec2(1, 1), vec2(0, 1), vec2(1, 0)].items)
  result = data.uploadData()

proc makeScreenQuad(): Model =
  var data: MeshData[Vec2]
  data.appendVerts([vec2(0), vec2(0, 1), vec2(1, 1), vec2(1, 0)].items)
  data.append([0u32, 1, 2, 0, 2, 3].items)
  data.appendUv([vec2(0, 0), vec2(0, 1), vec2(1, 1), vec2(1, 0)].items)
  result = data.uploadData()

addResourceProc do:
  camera.pos = vec3(0, 8, 0)
  camera.forward = normalize(vec3(5, 0, 5) - camera.pos)
  camera.pos = camera.pos - camera.forward * 20
  camera.changeSize(camDefaultSize)
  mainBuffer = genFrameBuffer(screenSize(), tfRgba, hasDepth = true)
  uiBuffer = genFrameBuffer(screenSize(), tfRgba, hasDepth = true)
  signBuffer = genFrameBuffer(screenSize(), tfR, hasDepth = true)
  waterQuad = makeRect(300, 300)
  screenQuad = makeScreenQuad()
  depthShader = loadShader(ShaderPath "vert.glsl", ShaderPath"depthfrag.glsl")
  waterShader = loadShader(ShaderPath"watervert.glsl", ShaderPath"waterfrag.glsl")
  screenShader = loadShader(ShaderPath"screenvert.glsl", ShaderPath"screenfrag.glsl")
  waterTex = genTexture()
  readImage("assets/water.png").copyTo(waterTex)
  mainBuffer.clearColor = color(0, 0, 0, 0)
  uiBuffer.clearColor = color(0, 0, 0, 0)

  gui.init()
  world = World.init(10, 10)

var
  lastScreenSize: IVec2

proc cameraMovement =
  var
    cameraDragPos {.global.}: Vec3
    cameraStartPos {.global.}: Vec3
    mouseStartPos {.global.}: IVec2
    mouseOffset {.global.} : IVec2

  case middleMb.state()
  of pressed:
    cameraDragPos = camera.raycast(getMousePos())
    cameraStartPos = camera.pos
    mouseStartPos = getMousePos()
    mouseOffset = ivec2(0)
    setMouseMode(MouseRelative)
  of held:
    let
      frameOffset = getMouseDelta()
      hitPos = camera.raycast(frameOffset + mouseStartPos)
      offset = hitPos - cameraDragPos
    camera.pos = cameraStartPos + offset
    mouseOffset -= frameOffset
    grabWindow()
  of released:
    setMouseMode(MouseAbsolute)
    releaseWindow()
    moveMouse(mouseStartPos + mouseOffset)
  else:
    discard

proc update(dt: float32) =

  let scrSize = screenSize()
  if lastScreenSize != scrSize:
    lastScreenSize = scrSize
    camera.calculateMatrix()
    mainBuffer.resize(scrSize)
    signBuffer.resize(scrSize)

  cameraMovement()

  with signBuffer:
    let
      mousePos = getMousePos()
      colData = 0u8
    glReadPixels(mousePos.x, screenSize().y - mousePos.y, 1, 1, GlRed, GlUnsignedByte, colData.unsafeAddr)
    let selected = world.getSignIndex(colData / 255)
    if selected >= 0:
      world.hoverSign(selected)

  world.update(camera, dt)

  let scroll = getMouseScroll()
  if scroll != 0:
    if KeycodeLCtrl.isPressed and not middleMb.isPressed:
      camera.changeSize(clamp(camera.size + -scroll.float * dt * 1000, 3, 20))

  if KeyCodeQ.isDown:
    quitTruss()
  guiState = nothing

proc draw =
  glEnable(GlDepthTest)
  with signBuffer:
    signBuffer.clear()
    world.renderSignBuff(camera)

  with uiBuffer:
    uiBuffer.clear()
    world.renderUi()
  glEnable(GlDepthTest)

  with mainBuffer:
    mainBuffer.clear()
    world.render(camera)
    with waterShader:
      let waterMatrix = mat4() * translate(vec3(-150, 0.9, -150))
      waterShader.setUniform("modelMatrix", waterMatrix)
      waterShader.setUniform("worldSize", vec2(world.width.float - 1, world.height.float - 1))
      waterShader.setUniform("depthTex", mainBuffer.depthTexture)
      waterShader.setUniform("colourTex", mainBuffer.colourTexture)
      waterShader.setUniform("waterTex", waterTex)
      watershader.setUniform("time", getTime())
      waterShader.setUniform("mvp", camera.orthoView * waterMatrix)
      glEnable GlDepthTest
      glDepthMask false
      render(waterQuad)
      glDepthMask true
    glColorMask false, false, false, false
    render(waterQuad)
    glColorMask true, true, true, true
    renderWaterSplashes(camera)


  with screenShader:
    let scrSize = screenSize()
    screenShader.setUniform("matrix", scale(vec3(2)) * translate(vec3(-0.5, -0.5, 0f)))
    screenShader.setUniform("tex", mainBuffer.colourTexture)
    screenShader.setUniform("uiTex", uiBuffer.colourTexture)
    render(screenQuad)

initTruss("Mind The Gap", ivec2(1280, 720), invokeResourceProcs, update, draw)
