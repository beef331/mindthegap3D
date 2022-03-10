import std/math
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
