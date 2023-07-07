import truss3D/[shaders, models, inputs, audio]
import std/[options, decls, streams]
import resources, cameras, directions, pickups, shadows, consts, serializers, tiles, entities
import vmath, pixie, opengl

export entities # any module using Enemies likely needs this

type
  Enemy* = object of Entity
    path*: seq[Vec3]
    pathIndex: int
    pathingDown: bool


proc serialize*(output: var Stream; enemy: Enemy) =
  output.saveSkippingFields(enemy)

proc deserialize*(input: var Stream; enemy: var Enemy) =
  input.loadSkippingFields(enemy)

proc init*(_: typedesc[Enemy], pos: Vec3): Enemy = 
  Enemy(
    pos: pos,
    fromPos: pos,
    toPos: pos,
    path: @[pos],
    moveProgress: MoveTime,
    rotation: up.targetRotation
  )

proc pathIfSafe(enemy: var Enemy, safeDirs: set[Direction], index: int): bool =
  let dir = directionBetween(enemy.pos, enemy.path[index])
  if dir.isSome and dir.unsafeGet in safeDirs:
    discard enemy.move(dir.unsafeGet)
    enemy.pathIndex = index
    result = true

proc move(enemy: var Enemy, safeDirs: set[Direction]) =
  let nextIndex =
    if enemy.pathingDown:
      enemy.pathIndex - 1
    else:
      enemy.pathIndex + 1
  
  if not enemy.pathIfSafe(safeDirs, nextIndex):
    let nextIndex =
      if enemy.pathingDown:
        enemy.pathIndex + 1
      else:
        enemy.pathIndex - 1
    discard enemy.pathIfSafe(safeDirs, nextIndex)

proc update*(enemy: var Enemy, safeDirs: set[Direction], dt: float32, levelFinished: bool) =
  let wasFullyMoved = enemy.fullyMoved
  movementUpdate(enemy, dt)
  if not wasFullyMoved and enemy.fullyMoved:
    enemy.pos = enemy.toPos
    enemy.fromPos = enemy.pos
  if not levelFinished and not enemy.isSliding and enemy.fullyMoved and wasFullyMoved:
    enemy.move(safeDirs)


