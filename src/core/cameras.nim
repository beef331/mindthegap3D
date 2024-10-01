import vmath
import truss3D

type
  Camera* = object
    pos: Vec3
    forward*: Vec3
    ortho*: Mat4
    view*: Mat4
    orthoView*: Mat4
    size*: float32

proc calculateMatrix*(camera: var Camera, sSize: IVec2) =
  if sSize.x > sSize.y:
    let aspect = float32(sSize.x / sSize.y)
    camera.ortho = ortho(-camera.size * aspect, camera.size * aspect, -camera.size, camera.size, 0.001f, 50f)
  else:
    let aspect = float32(sSize.y / sSize.x)
    camera.ortho = ortho(-camera.size, camera.size, -camera.size * aspect, camera.size * aspect, 0.001f, 50f)

  camera.view = lookat(camera.pos, (camera.pos + camera.forward), vec3(0, 1, 0))
  camera.orthoView = camera.ortho * camera.view


proc changeSize*(camera: var Camera, size: float32, scrSize: IVec2) =
  camera.size = size
  camera.calculateMatrix(scrSize)

proc init*(_: typedesc[Camera], pos, forward: Vec3, size: float32, scrSize: IVec2): Camera =
  result = Camera(pos: pos, forward: forward, size: size)
  result.calculateMatrix(scrSize)

const globalUp = vec3(0, 1, 0)

proc up*(cam: Camera): Vec3 =
  let
    camDir = normalize(cam.forward)
    camRight = cross(camDir, globalUp).normalize
  result = cross(camRight, camDir).normalize

proc raycast*(cam: Camera, point, screenSize: IVec2): Vec3 =
  let
    camDir = normalize(cam.forward)
    camRight = cross(camDir, globalUp).normalize
    camUp = cross(camRight, camDir).normalize
    xNdc = (2 * point.x) / screenSize.x - 1
    yNdc = (2 * point.y) / screenSize.y - 1
    origin =
      if screenSize.x >= screenSize.y:
        let aspect = screenSize.x / screenSize.y
        cam.pos + camRight * xNdc * cam.size * aspect + camUp * -yNdc * cam.size
      else:
        let aspect = screenSize.y / screenSize.x
        cam.pos + camRight * xNdc * cam.size + camUp * -yNdc * cam.size * aspect
    dist = dot(origin, globalUp) / dot(camDir, globalUp)
  result = -dist * camDir + origin

proc screenPosFromWorld*(cam: Camera, pos: Vec3, screenSize: IVec2): IVec2 =
  let
    screenSpace = (cam.orthoView * vec4(pos.x, pos.y, pos.z, 1))
  var zeroToOne = (screenSpace.xy * 0.5 + 0.5).xy
  zeroToOne = vec2(zeroToOne.x, 1f - zeroToOne.y)
  result = iVec2((zeroToOne.x * screenSize.x.float).int, (zeroToOne.y * screenSize.y.float).int)

proc `pos`*(camera: var Camera): Vec3 = camera.pos

proc setPos*(camera: var Camera, pos: Vec3, screenSize: IVec2) =
  camera.pos = pos
  camera.calculateMatrix(screenSize)

