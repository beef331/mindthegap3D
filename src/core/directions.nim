import std/math
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
  of right: Tau * (0.75)
  of down: Tau / 2
  of left: Tau / 4

proc asVec3*(dir: Direction): Vec3 =
  case dir:
  of up: vec3(0, 0, 1)
  of right: vec3(1, 0, 0)
  of down: vec3(0, 0, -1)
  of left: vec3(-1, 0, 0)
