import truss3D/[shaders, models, textures, inputs]
import std/[options, decls]
import resources, cameras, directions, pickups, shadows
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
  font.paint = rgba(255, 165, 0, 255)

  result.strokeText(font.typeset(character), translate(offset), strokeWidth = 20)

const
  MoveTime = 0.3f
  RotationSpeed = Tau * 3
  Height = 2

type
  Player* = object
    fromPos: Vec3
    toPos: Vec3
    pos: Vec3
    moveProgress: float32
    direction: Direction
    presentPickup: Option[PickupType]
    pickupRotation: Direction
    rotation: float32

var
  playerModel, dirModel: Model
  playerShader, alphaClipShader: Shader
  dirTex: array[Direction, Texture]

proc init*(_: typedesc[Player], pos: Vec3): Player =
  result.pos = pos
  result.fromPos = pos
  result.toPos = pos
  result.moveProgress = MoveTime + 0.01 # epsilon offset
  result.rotation = up.targetRotation

proc toVec*(d: Direction): Vec3 =
  case d
  of Direction.up: vec3(0, 0, 1)
  of right: vec3(1, 0, 0)
  of down: vec3(0, 0, -1)
  of left: vec3(-1, 0, 0)

proc targetRotation*(d: Direction): float32 =
  case d
  of right: 0f
  of Direction.up: Tau / 4f
  of left: Tau / 2f
  of down: 3f / 4f * Tau

func move(player: var Player, direction: Direction): bool =
  if player.moveProgress >= MoveTime:
    player.direction = direction
    player.fromPos = player.pos
    player.toPos = direction.toVec + player.pos
    player.moveProgress = 0
    result = true

func isMoving*(player: Player): bool = player.moveProgress < 1

func hasPickup*(player: Player): bool = player.presentPickup.isSome

func givePickup*(player: var Player, pickup: PickupType) = player.presentPickup = some(pickup)

func clearPickup*(player: var Player) = player.presentPickup = none(PickupType)

func getPickup*(player: Player): PickupType = player.presentPickup.get

func pickupRotation*(player: Player): Direction = player.pickupRotation

proc movementUpdate(player: var Player, dt: float32) =
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
    player.pos = player.toPos
  else:
    let
      progress = player.moveProgress / MoveTime
      sineOffset = vec3(0, sin(progress * Pi) * Height, 0)
    player.pos = player.frompos + player.direction.toVec * progress + sineOffset
    player.moveProgress += dt

proc posOffset(player: Player): Vec3 = player.pos + vec3(0.5, 0, 0.5) # Models are centred in centre of mass not corner

proc move(player: var Player, safeDirs: set[Direction], camera: Camera, dt: float32, didMove: var bool) =
  movementUpdate(player, dt)
  didMove = false

  template move(keycodes: set[TKeycode], dir: Direction) =
    var player{.byaddr.} = player
    if not didMove:
      for key in keycodes:
        if key.isPressed:
          if dir in safeDirs:
            didMove = player.move(dir)

  move({KeyCodeW, KeyCodeUp}, Direction.up)
  move({KeyCodeD, KeyCodeRight}, left)
  move({KeyCodeS, KeyCodeDown}, down)
  move({KeyCodeA, KeyCodeLeft}, right)

  if leftMb.isDown:
    let hit = vec3 ivec3 camera.raycast(getMousePos())
    for dir in Direction:
      if dir in safeDirs and distSq(hit, player.pos + dir.toVec) < 0.1:
        didMove = player.move(dir)

proc doPlace*(player: var Player): bool =
  leftMb.isDown and player.hasPickup

proc update*(player: var Player, safeDirs: set[Direction], camera: Camera, dt: float32, didMove: var bool) =
  player.move(safeDirs, camera, dt, didMove)

  if KeycodeR.isPressed:
    player.presentPickup = none(PickupType)

  if KeycodeLCtrl.isNothing:
    let scroll = getMouseScroll().sgn
    player.pickupRotation.nextDirection(scroll)

proc render*(player: Player, camera: Camera, safeDirs: set[Direction]) =
  with playerShader:
    let modelMatrix = (mat4() * translate(player.pos + vec3(0, 1.3, 0)) * rotateY(player.rotation))
    playerShader.setUniform("mvp", camera.orthoView * modelMatrix)
    playerShader.setUniform("m", modelMatrix)
    render(playerModel)

  if player.moveProgress >= MoveTime:
    with alphaClipShader:
      for x in Direction:
        if x in safeDirs:
          let modelMatrix = (mat4() * translate(player.pos + vec3(0, 1.3, 0) + x.toVec) * rotateY(90.toRadians))
          alphaClipShader.setUniform("mvp", camera.orthoView * modelMatrix)
          alphaClipShader.setUniform("tex", dirTex[x])
          render(dirModel)
  else:
    let
      scale = vec3(abs(player.moveProgress - (MoveTime / 2)) / (MoveTime / 2) * 1.4)
      pos = vec3(player.pos.x, 1, player.pos.z)
    renderShadow(camera, pos, scale)

func pos*(player: Player): Vec3 = player.pos
func mapPos*(player: Player): Vec3 = player.posOffset
func toPos*(player: Player): Vec3 = player.toPos

addResourceProc:
  playerModel = loadModel("player.dae")
  playerShader = loadShader(ShaderPath"vert.glsl", ShaderPath"frag.glsl")
  let
    wImage = makeMoveImage("W")
    aImage = makeMoveImage("D")
    sImage = makeMoveImage("S")
    dImage = makeMoveImage("A")

  for x in dirTex.mitems:
    x = genTexture()

  wImage.copyTo(dirTex[Direction.up])
  dImage.copyTo(dirTex[right])
  sImage.copyTo(dirTex[down])
  aImage.copyTo(dirTex[left])
  alphaClipShader = loadShader(ShaderPath"vert.glsl", ShaderPath"alphaclip.glsl")
  dirModel = loadModel("pickup_quad.dae")
