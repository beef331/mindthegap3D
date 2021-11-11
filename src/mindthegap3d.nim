import truss3D, vmath, chroma
import truss3D/[shaders, textures]
import core/[worlds, resources, cameras, players, directions]

const camDefaultSize = 8f
var
  camera: Camera
  world = World.init(10, 10)
  player = Player.init(vec3(5, 0, 5))
  depthBuffer: FrameBuffer
  depthShader, waterShader: Shader
  waterQuad: Model

proc makeRect(w, h: float32): Model =
  var data: MeshData[Vec3]
  data.appendVerts:
    [
      vec3(0, 0, 0), vec3(w, 3, h),
      vec3(0, 0, h),
      vec3(w, 0, 0)
    ].items
  data.append([0u32, 1, 2, 0, 3, 1].items)
  data.appendUV([vec2(1, 1), vec2(0, 0), vec2(1, 0), vec2(0, 1)].items)
  result = data.uploadData()

addResourceProc do:
  camera.pos = vec3(0, 8, 0)
  camera.forward = normalize(vec3(5, 0, 5) - camera.pos)
  camera.changeSize(camDefaultSize)
  depthBuffer = genFrameBuffer(screenSize(), tfRGB, {colour, depth})
  waterQuad = makeRect(10, 10)
  depthShader = loadShader("assets/shaders/vert.glsl", "assets/shaders/depthfrag.glsl")
  waterShader = loadShader("assets/shaders/texvert.glsl", "assets/shaders/texfrag.glsl")
  depthBuffer.clearColor = color(0, 0, 0, 1)

var
  cameraDragPos, cameraStartPos: Vec3
  mouseStartPos, mouseOffset: Ivec2
  lastScreenSize: IVec2

proc update(dt: float32) =
  if lastScreenSize != screenSize():
    lastScreenSize = screenSize()
    camera.calculateMatrix()
    depthBuffer.resize(screenSize())

  if middleMb.isDown:
    cameraDragPos = camera.raycast(getMousePos())
    cameraStartPos = camera.pos
    mouseStartPos = getMousePos()
    mouseOffset = ivec2(0)
  
  if middleMb.isPressed:
    mouseOffset += getMouseDelta()
    let
      newMousePos = mouseOffset + mouseStartPos
      hitPos = camera.raycast(newMousePos)
      offset = hitPos - cameraDragPos
    camera.pos = cameraStartPos + offset
    moveMouse(camera.screenPosFromWorld(cameraDragPos))

  player.update(world, camera, dt)
  world.update(camera, dt)

  let scroll = getMouseScroll()
  if scroll != 0:
    if KeycodeLCtrl.isPressed:
      camera.changeSize(clamp(camera.size + -scroll.float * 1000 * camera.size, 3, 20))

  if KeyCodeQ.isDown:
    quitTruss()

proc draw =
  glEnable(GlDepthTest)
  with depthBuffer:
    depthBuffer.clear()
    glEnable(GlDepthTest)
    world.renderDepth(camera, depthShader)

  world.render(camera)
  player.render(camera, world)
  with texShader:
    texShader.setUniform("tex", depthBuffer.texture)
    texShader.setUniform("mvp", camera.orthoView * mat4())
    render(waterQuad)

initTruss("Something", ivec2(1280, 720), invokeResourceProcs, update, draw)
