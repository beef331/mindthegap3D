import truss3D/[shaders, models, inputs, audio]
import std/[options, decls]
import resources, cameras, directions, pickups, shadows, consts, serializers, tiles, entities
import vmath, pixie, opengl

export entities # any module using Enemies likely needs this

type
  Enemy* = object of Entity
    path: seq[Direction]
    pathIndex: int
    pathingDown: bool
    lastPos* {.unserialized.}: Vec3

proc serialize*[S](output: var S; enemy: Enemy) =
  output.saveSkippingFields(enemy)

proc deserialize*[S](input: var S; enemy: var Enemy) =
  input.loadSkippingFields(enemy)

proc init*(_: typedesc[Enemy], pos: Vec3): Entity = 
  Entity(pos: pos, fromPos: pos, toPos: pos, moveProgress: MoveTime, rotation = up.targetRotation)

proc pathIfSafe(enemy: var Enemy, safeDirs: set[Direction], index: int): bool =
  if enemy.path[index] in safeDirs:
    discard enemy.move(enemy.path[index])
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


