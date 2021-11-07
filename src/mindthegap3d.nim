import truss3D, vmath, chroma
import truss3D/shaders
import core/[worlds, resources, cameras]

const camDefaultSize = 8f
var
  camera: Camera
  world = World.init(10, 10)

addResourceProc do:
  let
    size = screenSize()
    aspect = float32(size.x / size.y)
  camera.pos = vec3(0, 10, 0)
  camera.size = camDefaultSize
  camera.ortho = ortho(-camera.size * aspect, camera.size * aspect, -camera.size, camera.size, 0.001f, 100f)
  camera.view = lookat(camera.pos, vec3(5, 0, 5), vec3(0, 1, 0))
  camera.orthoView = camera.ortho * camera.view

proc update(dt: float32) =
  world.updateCursor(getMousePos(), camera)
  if leftMb.isPressed:
    world.placeBlock()
  if rightMb.isPressed:
    world.placeEmpty()

  let scroll = getMouseScroll()
  if scroll != 0:
    if Keycodelshift.isPressed:
      world.nextOptional(scroll.sgn)
    else:
      world.nextTile(scroll.sgn)


  if KeyCodeQ.isDown:
    quitTruss()

proc draw =
  glEnable(GlDepthTest)
  world.render(camera)
initTruss("Something", ivec2(1280, 720), invokeResourceProcs, update, draw)
