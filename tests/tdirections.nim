import vmath
import core/directions
import std/[unittest, options]

check vec3(0, 0, 0).directionBetween(vec3(1, 0, 0)) == some Direction.left
check vec3(0, 0, 0).directionBetween(vec3(-1, 0, 0)) == some Direction.right
check vec3(0, 0, 0).directionBetween(vec3(0, 0, 1)) == some Direction.up
check vec3(0, 0, 0).directionBetween(vec3(0, 0, -1)) == some Direction.down
check vec3(0, 0, 0).directionBetween(vec3(-11)) == none Direction


for x in 0..10:
  for y in 0..10:
    let 
      x = float32 x
      y = float32 y
    check vec3(x, 0, y).directionBetween(vec3(x + 1, 0, y)) == some Direction.left
    check vec3(x, 0, y).directionBetween(vec3(x - 1, 0, y)) == some Direction.right
    check vec3(x, 0, y).directionBetween(vec3(x, 0, y + 1)) == some Direction.up
    check vec3(x, 0, y).directionBetween(vec3(x, 0, y - 1)) == some Direction.down

    check vec3(x, 0, y).directionBetween(vec3(x + 2, 0, y)) == none Direction 
    check vec3(x, 0, y).directionBetween(vec3(x - 2, 0, y)) == none Direction 
    check vec3(x, 0, y).directionBetween(vec3(x, 0, y + 2)) == none Direction 
    check vec3(x, 0, y).directionBetween(vec3(x, 0, y - 2)) == none Direction 
