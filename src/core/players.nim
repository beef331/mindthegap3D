import truss3D/[shaders, models]
import resources, cameras
import vmath
import constructor/constructor

var
  playerModel: Model
  playerShader: Shader

const
  MoveTime = 0.3f
  RotationSpeed = Tau

type
  Direction* = enum
    up, right, down, left
  Player* = object
    startPos: Vec3
    targetPos: Vec3
    pos: Vec3
    moveProgress: float32
    direction: Direction
    rotation: float32



proc init*(_: typedesc[Player], pos: Vec3): Player =
  result.pos = pos
  result.startPos = pos
  result.targetPos = pos
  result.moveProgress = MoveTime

proc toVec*(d: Direction): Vec3 =
  case d
  of up: vec3(0, 0, 1)
  of right: vec3(1, 0, 0)
  of down: vec3(0, 0, -1)
  of left: vec3(-1, 0, 0)

proc targetRotation*(d: Direction): float32 = 
  case d
  of right: 0f
  of up: Tau / 4f
  of left: Tau / 2f
  of down: 3f / 4f * Tau

proc move*(player: var Player, direction: Direction) =
  if player.moveProgress >= MoveTime:
    player.direction = direction
    player.startPos = player.pos
    player.targetPos = direction.toVec + player.pos
    player.moveProgress = 0

proc update*(player: var Player, dt: float32) =
  let
    rotTarget = player.direction.targetRotation
  var
    rotDiff = (player.rotation mod Tau) - rotTarget
  if rotDiff > Pi:
    rotDiff -= Tau
  if rotDiff < -Pi:
    rotDiff += Tau

  if abs(rotDiff) <= 0.1:
    player.rotation = rotTarget
  else:
    player.rotation += dt * RotationSpeed * -sgn(rotDiff).float32

  if player.moveProgress >= MoveTime:
    player.pos = player.targetPos
  else:
    player.pos = mix(player.startPos, player.targetPos, player.moveProgress / MoveTime)
    player.moveProgress += dt



proc render*(player: Player, camera: Camera) =
  with playerShader:
    playerShader.setUniform("mvp", camera.orthoView * (mat4() * translate(player.pos + vec3(0, 1.3, 0)) * rotateY(player.rotation)))
    render(playerModel)


addResourceProc do:
  playerModel = loadModel("assets/models/player.dae")
  playerShader = loadShader("assets/shaders/vert.glsl", "assets/shaders/frag.glsl")

