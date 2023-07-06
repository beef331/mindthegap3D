import std/[math, options]
import vmath

type
  Direction* = enum
    up, left, down, right

proc nextDirection*(d: var Direction, val: -1..1) =
  const count = (Direction.high.ord + 1)
  d = Direction((d.ord + val + count) mod count)


proc asRot*(dir: Direction): float32 =
  case dir
  of up: 0f32
  of right: Tau / 4
  of down: Tau / 2
  of left: Tau * (0.75)

proc asVec3*(dir: Direction): Vec3 =
  case dir:
  of up: vec3(0, 0, 1)
  of right: vec3(-1, 0, 0)
  of down: vec3(0, 0, -1)
  of left: vec3(1, 0, 0)


proc directionBetween*(a, b: Vec3): Option[Direction] =
  let
    a = floor(a)
    b = floor(b)
  if a.x == b.x:
    if b.z == a.z - 1:
      some down
    elif b.z == a.z + 1:
      some up
    else:
      none(Direction)
  elif a.z == b.z:
    if b.x == a.x - 1:
      some left
    elif b.x == a.x + 1:
      some right
    else:
      none(Direction)
  else:
    none(Direction)



