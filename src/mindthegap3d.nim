import truss3D, vmath, chroma
import truss3D/shaders
import core/[worlds, resources, cameras, players]

const camDefaultSize = 8f
var
  camera: Camera
  world = World.init(10, 10)
  player = Player.init(vec3(5, 0, 5))

addResourceProc do:
  camera.pos = vec3(0, 8, 0)
  camera.forward = normalize(vec3(5, 0, 5) - camera.pos)
  camera.changeSize(camDefaultSize)


proc update(dt: float32) =
  world.updateCursor(getMousePos(), camera)
  if leftMb.isPressed:
    world.placeBlock()
  if rightMb.isPressed:
    world.placeEmpty()

  if KeycodeW.isPressed:
    player.move(up)

  if KeycodeD.isPressed:
    player.move(left)

  if KeycodeS.isPressed:
    player.move(down)

  if KeycodeA.isPressed:
    player.move(right)

  player.update(dt)

  let scroll = getMouseScroll()
  if scroll != 0:
    if KeycodeLShift.isPressed:
      world.nextOptional(scroll.sgn)
    elif KeycodeLCtrl.isPressed:
      camera.changeSize(camera.size + scroll.float * dt * 1000 * camera.size)
    else:
      world.nextTile(scroll.sgn)

  if KeyCodeQ.isDown:
    quitTruss()

proc draw =
  glEnable(GlDepthTest)
  world.render(camera)
  player.render(camera)
initTruss("Something", ivec2(1280, 720), invokeResourceProcs, update, draw)
