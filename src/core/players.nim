import truss3D/[shaders, models, textures]
import resources, cameras
import vmath
import pixie


var font = readFont("assets/fonts/NovusGraecorumRegular-Mj0w.ttf")
proc makeMoveImage(character: string, border = 20f, size = 256): Image =
  let color = rgba(0, 0, 255, 255)
  result = newImage(size, size)
  let ctx = newContext(result)
  ctx.strokeStyle = color
  ctx.lineWidth = border.float32
  let rSize = size.float32 - border * 2
  ctx.strokeRect(border, border, rSize, rSize)
  font.size = size / 2
  let
    bounds = computeBounds(font.typeSet(character))
    offset = vec2(size.float - border * 2 - bounds.x, size.float - border * 2 - bounds.y)

  font.paint = color
  result.fillText(font.typeSet(character), translate(offset))

const
  MoveTime = 0.3f
  RotationSpeed = Tau * 3
  Height = 3

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


var
  playerModel, quadModel: Model
  playerShader, alphaClipShader: Shader
  dirTex: array[Direction, Texture]

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
    let
      progress = player.moveProgress / MoveTime
      sineOffset = vec3(0, sin(progress * Pi) * Height, 0)
    player.pos = player.startPos + player.direction.toVec * progress + sineOffset
    player.moveProgress += dt



proc render*(player: Player, camera: Camera, safeDirections: set[Direction]) =
  with playerShader:
    let modelMatrix = (mat4() * translate(player.pos + vec3(0, 1.3, 0)) * rotateY(player.rotation))
    playerShader.setUniform("mvp", camera.orthoView * modelMatrix)
    playerShader.setUniform("m", modelMatrix)
    render(playerModel)

  if player.moveProgress >= MoveTime:
    with alphaClipShader:
      for x in Direction:
        if x in safeDirections:
          let modelMatrix = (mat4() * translate(player.pos + vec3(0, 1.3, 0) + x.toVec) * rotateY(90.toRadians))
          alphaClipShader.setUniform("mvp", camera.orthoView * modelMatrix)
          alphaClipShader.setUniform("tex", dirTex[x])
          render(quadModel)

proc pos*(player: Player): Vec3 = player.pos

addResourceProc:
  playerModel = loadModel("assets/models/player.dae")
  playerShader = loadShader("assets/shaders/vert.glsl", "assets/shaders/frag.glsl")
  let
    wImage = makeMoveImage("W")
    aImage = makeMoveImage("D")
    sImage = makeMoveImage("S")
    dImage = makeMoveImage("A")

  for x in dirTex.mitems:
    x = genTexture()

  wImage.copyTo(dirTex[up])
  dImage.copyTo(dirTex[right])
  sImage.copyTo(dirTex[down])
  aImage.copyTo(dirTex[left])
  alphaClipShader = loadShader("assets/shaders/vert.glsl", "assets/shaders/alphaclip.glsl")
  quadModel = loadModel("assets/models/pickup_quad.dae")


