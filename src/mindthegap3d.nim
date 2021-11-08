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


var
  cameraDragPos, cameraStartPos: Vec3
  mouseStartPos, mouseOffset: Ivec2

proc update(dt: float32) =
  world.updateCursor(getMousePos(), camera)
  if leftMb.isPressed:
    world.placeBlock()
  if rightMb.isPressed:
    world.placeEmpty()

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

  let safeDirs = world.getSafeDirections(player.pos + vec3(0.5, 0, 0.5))
  if KeycodeW.isPressed and up in safeDirs:
    player.move(up)

  if KeycodeD.isPressed and left in safeDirs:
    player.move(left)

  if KeycodeS.isPressed and down in safeDirs:
    player.move(down)

  if KeycodeA.isPressed and right in safeDirs:
    player.move(right)

  player.update(dt)

  let scroll = getMouseScroll()
  if scroll != 0:
    if KeycodeLShift.isPressed:
      world.nextOptional(scroll.sgn)
    elif KeycodeLCtrl.isPressed:
      camera.changeSize(clamp(camera.size + -scroll.float * dt * 1000 * camera.size, 3, 20))
    else:
      world.nextTile(scroll.sgn)

  if KeyCodeQ.isDown:
    quitTruss()

proc draw =
  glEnable(GlDepthTest)
  world.render(camera)
  player.render(camera, world.getSafeDirections(player.pos + vec3(0.5, 0, 0.5)))
initTruss("Something", ivec2(1280, 720), invokeResourceProcs, update, draw)
