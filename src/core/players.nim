import truss3D/[shaders, models, textures, inputs, audio]
import std/[options, decls]
import resources, cameras, directions, pickups, shadows, consts
import vmath, pixie, opengl


var font = readFont("assets/fonts/SigmarOne-Regular.ttf")
proc makeMoveImage(character: string, border = 20f, size = 256): Image =
  let color = rgba(32, 127, 255, 255)
  result = newImage(size, size)
  let ctx = newContext(result)
  ctx.strokeStyle = color
  ctx.lineWidth = border.float32
  let rSize = size.float32 - border * 2
  ctx.strokeRect(border, border, rSize, rSize)
  font.size = size.float - border * 4
  font.paint = color
  result.fillText(font, character, transform = translate(vec2(border)), bounds = vec2(size.float - border * 2), hAlign = CenterAlign, vAlign = MiddleAlign)

  font.paint = rgba(255, 127, 0, 255)
  result.strokeText(font, character, strokeWidth = 10, transform = translate(vec2(border)), bounds = vec2(size.float - border * 2), hAlign = CenterAlign, vAlign = MiddleAlign)

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
  playerJump: SoundEffect

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
  playerJump = loadSound("assets/sounds/jump.wav")
  playerJump.sound.volume = 0.3

proc init*(_: typedesc[Player], pos: Vec3): Player =
  result.pos = pos
  result.fromPos = pos
  result.toPos = pos
  result.moveProgress = MoveTime
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

proc move(player: var Player, direction: Direction): bool =
  if player.moveProgress >= MoveTime:
    player.direction = direction
    player.fromPos = player.pos
    player.toPos = direction.toVec + player.pos
    player.moveProgress = 0
    playerJump.play()
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

proc skipMoveAnim*(player: var Player) =
  ## For moving the player without causing an animation
  player.moveProgress = MoveTime

proc move(player: var Player, safeDirs: set[Direction], camera: Camera, dt: float32, moveDir: var Option[Direction]) =
  movementUpdate(player, dt)

  template move(keycodes: set[TKeycode], dir: Direction) =
    var player{.byaddr.} = player
    if moveDir.isNone:
      for key in keycodes:
        if key.isPressed and dir in safeDirs and player.move(dir):
          moveDir = some(dir)

  move({KeyCodeW, KeyCodeUp}, Direction.up)
  move({KeyCodeD, KeyCodeRight}, left)
  move({KeyCodeS, KeyCodeDown}, down)
  move({KeyCodeA, KeyCodeLeft}, right)

  if rightMb.isPressed():
    let hit = vec3 ivec3 camera.raycast(getMousePos())
    for dir in Direction:
      if dir in safeDirs and distSq(hit, player.pos + dir.toVec) < 0.1:
        if player.move(dir):
          moveDir = some(dir)

proc doPlace*(player: var Player): bool =
  leftMb.isDown and player.hasPickup

proc update*(player: var Player, safeDirs: set[Direction], camera: Camera, dt: float32, moveDir: var Option[Direction]) =
  player.move(safeDirs, camera, dt, moveDir)

  if KeycodeR.isPressed:
    player.presentPickup = none(PickupType)

  if KeycodeLCtrl.isNothing:
    let scroll = getMouseScroll().sgn
    player.pickupRotation.nextDirection(scroll)

proc render*(player: Player, camera: Camera, safeDirs: set[Direction]) =
  with playerShader:
    glShadeModel(GL_FLAT);
    let modelMatrix = (mat4() * translate(player.pos + vec3(0, 1.0, 0)) * rotateY(player.rotation))
    playerShader.setUniform("mvp", camera.orthoView * modelMatrix)
    playerShader.setUniform("m", modelMatrix)
    render(playerModel)

  if player.moveProgress >= MoveTime:
    with alphaClipShader:
      glDisable(GlDepthTest)
      for x in Direction:
        if x in safeDirs:
          let modelMatrix = (mat4() * translate(player.pos + vec3(0, 1.3, 0) + x.toVec) * rotateY(90.toRadians))
          alphaClipShader.setUniform("mvp", camera.orthoView * modelMatrix)
          alphaClipShader.setUniform("tex", dirTex[x])
          render(dirModel)
      glEnable(GlDepthTest)
  else:
    let
      scale = vec3(abs(player.moveProgress - (MoveTime / 2)) / (MoveTime / 2) * 1.4)
      pos = vec3(player.pos.x, 1, player.pos.z)
    renderShadow(camera, pos, scale)

func pos*(player: Player): Vec3 = player.pos
func mapPos*(player: Player): Vec3 =
  let pos = player.posOffset()
  vec3(pos.x.floor, pos.y.floor, pos.z.floor)
func movingToPos*(player: Player): Vec3 = player.toPos + vec3(0.5, 0, 0.5)
