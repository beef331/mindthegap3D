import truss3D
import vmath
import chroma
import pixie
import truss3D/[shaders, textures]
import core/[worlds, resources, cameras, players, directions, editorbridge]
import std/os

shaderPath = "assets/shaders"
modelPath = "assets/models"

const camDefaultSize = 8f
var
  camera: Camera
  world: World
  depthBuffer, signBuffer: FrameBuffer
  depthShader, waterShader: Shader
  waterQuad: Model
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

addResourceProc do:
  camera.pos = vec3(0, 8, 0)
  camera.forward = normalize(vec3(5, 0, 5) - camera.pos)
  camera.pos = camera.pos - camera.forward * 20
  camera.changeSize(camDefaultSize)
  depthBuffer = genFrameBuffer(screenSize(), tfRgba, hasDepth = true)
  signBuffer = genFrameBuffer(screenSize(), tfR, hasDepth = true)
  waterQuad = makeRect(300, 300)
  depthShader = loadShader(ShaderPath "vert.glsl", ShaderPath"depthfrag.glsl")
  waterShader = loadShader(ShaderPath"watervert.glsl", ShaderPath"waterfrag.glsl")
  waterTex = genTexture()
  readImage("assets/water.png").copyTo(waterTex)
  depthBuffer.clearColor = color(0, 0, 0, 1)

var
  lastScreenSize: IVec2
  editorSocket: Socket

if paramCount() >= 1:
  editorSocket = createGameSocket()

proc cameraMovement =
  var
    cameraDragPos {.global.}: Vec3
    cameraStartPos {.global.}: Vec3
    mouseCamDrag {.global.}: IVec2
    mouseStartPos {.global.}: IVec2

  case middleMb.state()
  of pressed:
    cameraDragPos = camera.raycast(getMousePos())
    cameraStartPos = camera.pos
    mouseStartPos = getMousePos()
    mouseCamDrag = iVec2 0
    setMouseMode(MouseRelative)
  of held:
    mouseCamDrag += getMouseDelta()
    let
      hitPos = camera.raycast(getMouseDelta() + mouseStartPos)
      offset = hitPos - cameraDragPos
    camera.pos = cameraStartPos + offset
    moveMouse(mouseStartPos - mouseCamDrag)
  of released:
    setMouseMode(MouseAbsolute)
    moveMouse(mouseStartPos - mouseCamDrag)
  else:
    discard

proc update(dt: float32) =
  if paramCount() >= 1:
    let newWorld = editorSocket.getWorld()
    if newWorld.isSome:
      world.unload()
      world = newWorld.get
      world.load()
      if world.playerSpawn in 0..<world.tiles.len:
        world.player = Player.init(world.getPos(int world.playerSpawn))


  let scrSize = screenSize()
  if lastScreenSize != scrSize:
    lastScreenSize = scrSize
    camera.calculateMatrix()
    depthBuffer.resize(scrSize)
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
    if KeycodeLCtrl.isPressed:
      camera.changeSize(clamp(camera.size + -scroll.float * dt * 1000, 3, 20))

  if KeyCodeQ.isDown:
    quitTruss()

proc draw =
  glEnable(GlDepthTest)
  glCullFace(GlBack)
  with depthBuffer:
    depthBuffer.clear()
    world.render(camera)

  with signBuffer:
    signBuffer.clear()
    world.renderSignBuff(camera)

  glClear(GLDepthBufferBit or GlColorBufferBit)
  with waterShader:
    let waterMatrix = mat4() * translate(vec3(-150, 0.9, -150))
    glEnable(GlDepthTest)
    waterShader.setUniform("modelMatrix", waterMatrix)
    waterShader.setUniform("worldSize", vec2(world.width.float - 1, world.height.float - 1))
    waterShader.setUniform("depthTex", depthBuffer.depthTexture)
    waterShader.setUniform("colourTex", depthBuffer.colourTexture)
    waterShader.setUniform("waterTex", waterTex)
    watershader.setUniform("time", getTime())
    waterShader.setUniform("mvp", camera.orthoView * waterMatrix)
    render(waterQuad)
  world.render(camera)


initTruss("Something", ivec2(1280, 720), invokeResourceProcs, update, draw)
