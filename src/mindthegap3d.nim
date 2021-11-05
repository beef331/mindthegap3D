import truss3D, vmath, chroma
import truss3D/shaders
const camSize = 10f
var
  ortho = ortho(-camSize, camSize, -camSize, camSize, 0f, 10f)
  view = lookat(vec3(0), vec3(0, 0, 1), vec3(0, 1, 0))

proc init =
  let xAspect = (screenSize().x / screenSize().y).float32
  ortho = ortho(-camSize * xAspect, camSize * xAspect, -camSize, camSize, 0f, 10f)
  view = lookat(vec3(0), vec3(0, 0, 1), vec3(0, -1, 0))

proc update(dt: float32) =
  if KeyCodeQ.isDown:
    quitTruss()

proc draw =
  let ov = ortho * view
initTruss("Something", ivec2(1280, 720), init, update, draw)
