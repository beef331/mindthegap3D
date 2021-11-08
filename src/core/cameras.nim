import vmath
import truss3D
import constructor/constructor
type 
  Camera* = object
    pos: Vec3
    forward*: Vec3
    ortho*: Mat4
    view*: Mat4
    orthoView*: Mat4
    size*: float32

proc calculateMatrix(camera: var Camera) =
  let
    sSize = screenSize()
    aspect = float32(sSize.x / sSize.y)
  camera.ortho = ortho(-camera.size * aspect, camera.size * aspect, -camera.size, camera.size, 0.001f, 100f)
  camera.view = lookat(camera.pos, (camera.pos + camera.forward), vec3(0, 1, 0))
  camera.orthoView = camera.ortho * camera.view


proc changeSize*(camera: var Camera, size: float32) =
  camera.size = size
  camera.calculateMatrix()

proc init*(_: typedesc[Camera], pos, forward: Vec3) {.constr.} = discard

const up = vec3(0, 1, 0)

proc raycast*(cam: Camera, point: IVec2): Vec3 =
  let
    camDir = normalize(cam.forward)
    camRight = cross(camDir, up).normalize
    camUp = cross(camRight, camDir).normalize
    screenSize = screenSize()
    aspect = screenSize.x / screenSize.y
    xNdc = (2 * point.x) / screenSize.x - 1
    yNdc = (2 * point.y) / screenSize.y - 1
    rayOrigin = cam.pos + camRight * xNdc * cam.size * aspect + camUp * -yNdc * cam.size
    dist = dot(rayOrigin, up) / dot(camDir, up)
  result = -dist * camDir + rayOrigin


proc screenPosFromWorld*(cam: Camera, pos: Vec3): IVec2 = 
  let
    size = screenSize()
    screenSpace = (cam.orthoView * vec4(pos.x, pos.y, pos.z, 1))
  var zeroToOne = (screenSpace.xy * 0.5 + 0.5).xy
  zeroToOne = vec2(zeroToOne.x, 1f - zeroToOne.y)
  result = iVec2((zeroToOne.x * size.x.float).int, (zeroToOne.y * size.y.float).int)


proc `pos`*(camera: var Camera): Vec3 = camera.pos

proc `pos=`*(camera: var Camera, pos: Vec3) =
  camera.pos = pos
  camera.calculateMatrix()

