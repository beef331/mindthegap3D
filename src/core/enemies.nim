import truss3D/[shaders, models, inputs, audio]
import std/[options, decls, streams]
import resources, cameras, directions, pickups, shadows, consts, serializers, tiles, entities, tiledatas, directions
import vmath, pixie, opengl

export entities # any module using Enemies likely needs this

type
  Enemy* = object of Entity
    path*: seq[Vec3]
    pathIndex: int
    pathingDown: bool

proc moveTime(enemy: Enemy): float32 = EnemyMoveTime 

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
    moveProgress: moveTime(result),
    rotation: up.targetRotation
  )

proc pathIfSafe(enemy: var Enemy, safeDirs: set[Direction], index: int): bool =
  if index in 0..enemy.path.high:
    let dir = directionBetween(enemy.pos, enemy.path[index])
    if dir.isSome and dir.unsafeGet in safeDirs:
      discard enemy.move(dir.unsafeGet)
      enemy.pathIndex = index
      result = true

proc move(enemy: var Enemy, safeDirs: set[Direction]) =
  if enemy.path.len > 1:
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
      if enemy.pathIfSafe(safeDirs, nextIndex):
        enemy.pathingDown = not enemy.pathingDown

proc update*(enemy: var Enemy, safeDirs: set[Direction], dt: float32, levelFinished: bool, tileData: TileData, playerMoved: bool) =
  let wasFullyMoved = enemy.fullyMoved
  movementUpdate(enemy, dt)
  if not wasFullyMoved and enemy.fullyMoved:
    enemy.pos = enemy.toPos
    enemy.fromPos = enemy.pos

    let
      startInd = tileData.getPointIndex(enemy.mapPos)
      tile = tileData[startInd]
      enemyNextPos = enemy.direction.asVec3() + enemy.mapPos
      nextIndex = tileData.getPointIndex(enemyNextPos)
    
    if tile.kind == ice:
      if enemyNextPos in tileData:
        enemy.startSliding()


    if tile.kind != ice or enemyNextPos notin tileData or not tileData[nextIndex].isSlidable:
      enemy.stopSliding()

    
  if not levelFinished and not enemy.isSliding and enemy.fullyMoved and wasFullyMoved and playerMoved:
    enemy.move(safeDirs)


