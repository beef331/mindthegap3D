import truss3D, vmath, chroma
import truss3D/shaders
import core/[worlds, resources]

const camSize = 8f
var
  orth: Mat4
  view: Mat4
  cameraPos = vec3(0, 7, 0)
  world = World.init(10, 10)

addResourceProc do:
  let
    size = screenSize()
    aspect = float32(size.x / size.y)
  orth = ortho(-camSize * aspect, camSize * aspect, -camSize, camSize, 0f, 100f)
  view = lookat(cameraPos, vec3(5, 0, 5), vec3(0, 1, 0))

proc update(dt: float32) =
  if KeyCodeQ.isDown:
    quitTruss()

proc draw =
  let ov = orth * view
  glEnable(GlDepthTest)
  world.render(ov)
initTruss("Something", ivec2(1280, 720), invokeResourceProcs, update, draw)
