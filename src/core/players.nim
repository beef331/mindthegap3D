import truss3D/[shaders, models, inputs, audio]
import truss3D
import std/[options, decls, streams]
import resources, cameras, directions, pickups, shadows, consts, serializers, tiles, entities
import vmath, pixie, opengl

export entities # any module using Player likely needs this

type
  Player* = object of Entity
    hasKey*: bool
    presentPickup: Option[PickupType]
    pickupRotation: Direction
   
proc serialize*(output: var Stream; player: Player) =
  output.saveSkippingFields(player)

proc deserialize*(input: var Stream; player: var Player) =
  input.loadSkippingFields(player)

var
  playerModel, dirModel: Model
  playerShader, alphaClipShader: Shader

addResourceProc do():
  playerModel = loadModel("player.dae")
  playerShader = loadShader(ShaderPath"vert.glsl", ShaderPath"frag.glsl")
  alphaClipShader = loadShader(ShaderPath"vert.glsl", ShaderPath"alphaclip.glsl")
  dirModel = loadModel("pickup_quad.dae")

proc init*(_: typedesc[Player], pos: Vec3): Player =
  result.pos = pos
  result.fromPos = pos
  result.toPos = pos
  result.moveProgress = MoveTime
  result.rotation = up.targetRotation

func hasPickup*(player: Player): bool = player.presentPickup.isSome

func givePickup*(player: var Player, pickup: PickupType) = player.presentPickup = some(pickup)

func clearPickup*(player: var Player) = player.presentPickup = none(PickupType)

func getPickup*(player: Player): PickupType = player.presentPickup.get

func pickupRotation*(player: Player): Direction = player.pickupRotation

proc move(player: var Player, truss: var Truss, safeDirs: set[Direction], camera: Camera, dt: float32, moveDir: var Option[Direction]) =

  template move(keycodes: set[TKeycode], dir: Direction) =
    var player{.byaddr.} = player
    if moveDir.isNone:
      for key in keycodes:
        if truss.inputs.isPressed(key) and dir in safeDirs and player.move(dir):
          moveDir = some(dir)

  move({KeyCodeW, KeyCodeUp}, Direction.up)
  move({KeyCodeD, KeyCodeRight}, right)
  move({KeyCodeS, KeyCodeDown}, down)
  move({KeyCodeA, KeyCodeLeft}, left)

  if truss.inputs.isPressed(rightMb):
    let hit = vec3 ivec3 camera.raycast(truss.inputs.getMousePos(), truss.windowSize)
    for dir in Direction:
      if dir in safeDirs and distSq(hit, player.pos + dir.asVec3) < 0.1:
        if player.move(dir):
          moveDir = some(dir)

proc doPlace*(player: var Player, truss: var Truss): bool =
  truss.inputs.isDown(leftMb) and player.hasPickup and not player.isSliding

proc update*(player: var Player, truss: var Truss, safeDirs: set[Direction], camera: Camera, dt: float32, moveDir: var Option[Direction], levelFinished: bool) =
  let wasFullyMoved = player.fullyMoved
  movementUpdate(player, dt)
  if not wasFullyMoved and player.fullyMoved:
    player.pos = player.toPos
    player.fromPos = player.pos
  if not levelFinished and not player.isSliding and player.fullyMoved and wasFullyMoved:
    player.move(truss, safeDirs, camera, dt, moveDir)

    if truss.inputs.isNothing(KeycodeLCtrl):
      let scroll = truss.inputs.getMouseScroll().sgn
      player.pickupRotation.nextDirection(scroll)

proc render*(player: Player, camera: Camera, safeDirs: set[Direction], thisTile, nextTile: Tile) =
  let 
    height = mix(thisTile.calcYPos(true), nextTile.calcYPos(true), player.moveProgress / MoveTime)
  with playerShader:
    let 
      modelMatrix = (mat4() * translate(player.pos + vec3(0, height, 0)) * rotateY(player.rotation)) * scale(vec3(0.9))
    playerShader.setUniform("mvp", camera.orthoView * modelMatrix)
    playerShader.setUniform("m", modelMatrix)
    render(playerModel)

  if player.moveProgress < MoveTime and not player.isSliding:
    let
      scale = vec3(abs(player.moveProgress - (MoveTime / 2)) / (MoveTime / 2) * 1.4)
      pos = vec3(player.pos.x, height - 0.3, player.pos.z)
    renderShadow(camera, pos, scale)

func pos*(player: Player): Vec3 = player.pos

func movingToPos*(player: Player): Vec3 = player.toPos + vec3(0.5, 0, 0.5)
func startPos*(player: Player): Vec3 = (player.fromPos + vec3(0.5, 0, 0.5)).floor
func dir*(player: Player): Direction = player.direction

