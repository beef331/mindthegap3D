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
    a = a.xz.ivec2
    b = b.xz.ivec2
    xDiff = a.x - b.x
    yDiff = a.y - b.y

  if xDiff == 0 and abs(yDiff) == 1:
    if yDiff < 0:
      some up
    else:
      some down
  elif yDiff == 0 and abs(xDiff) == 1:
    if xDiff < 0:
      some left
    else:
      some right
  else:
    none Direction


