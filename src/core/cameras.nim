import vmath
import truss3D
import constructor/constructor
type 
  Camera* = object
    pos*: Vec3
    ortho*: Mat4
    view*: Mat4
    orthoView*: Mat4
    size*: float32

proc init*(_: typedesc[Camera], pos: Vec3, ortho, view: Mat4, size: float32 ) {.constr.} = discard


proc raycast*(cam: Camera, point: IVec2): Vec3 =
  const up = vec3(0, 1, 0)
  let
    camDir = normalize(vec3(5, 0, 5) - cam.pos)
    camRight = cross(camDir, up).normalize
    camUp = cross(camRight, camDir).normalize
    screenSize = screenSize()
    aspect = screenSize.x / screenSize.y
    xNdc = (2 * point.x) / screenSize.x - 1
    yNdc = (2 * point.y) / screenSize.y - 1
    rayOrigin = cam.pos + camRight * xNdc * cam.size * aspect + camUp * -yNdc * cam.size
    dist = dot(rayOrigin, up) / dot(camDir, up)
    pos = -dist * camDir + rayOrigin
  result = vec3(pos.x.floor, 0, pos.z.floor)