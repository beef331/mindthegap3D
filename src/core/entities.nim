import truss3D/[models, audio]
import vmath
import directions, serializers, consts, resources

type
  Entity* = object of RootObj
    fromPos*: Vec3
    toPos*: Vec3
    pos*: Vec3
    moveProgress*: float32
    direction*: Direction
    rotation*: float32
    lastSound* {.unserialized.}: Sound
    isSliding* {.unserialized.}: bool

var entjump, slidesfx: SoundEffect

addresourceproc do():
  entjump = loadsound("assets/sounds/jump.wav")
  entJump.sound.volume = 0.3


  slideSfx = loadSound("assets/sounds/push.wav")
  slideSfx.sound.volume = 0.3

proc moveTime(ent: Entity): float32 = MoveTime

func fullyMoved*[T: Entity](ent: T): bool =
  mixin moveTime
  ent.moveProgress >= moveTime(ent)

proc skipMoveAnim*[T: Entity](ent: var T) =
  ## For moving the entity without causing an animation
  mixin moveTime
  ent.moveProgress = moveTime(ent)

proc move*[T: Entity](ent: var T, direction: Direction): bool =
  mixin moveTime

  if ent.moveProgress >= moveTime(ent):
    ent.direction = direction
    ent.toPos = direction.asVec3 + ent.pos
    ent.moveProgress = 0
    let sfx = 
      if ent.isSliding:
        slideSfx
      else:
        entJump
        
    sfx.sound.volume =
      if ent.lastSound != nil and not bool(atEnd(ent.lastSound)):
        0.05f
      else:
        0.3f
    ent.lastSound = sfx.play()
    result = true

proc posOffset*(ent: Entity): Vec3 = ent.pos + vec3(0.5, 0, 0.5) # Models are centred in centre of mass not corner

proc targetRotation*(d: Direction): float32 =
  case d
  of right: Tau / 2f
  of Direction.up: Tau / 4f
  of left: 0f
  of down: 3f / 4f * Tau

proc movementUpdate*[T: Entity](ent: var T, dt: float32) =
  mixin moveTime

  let
    rotTarget = ent.direction.targetRotation
  var
    rotDiff = (ent.rotation mod Tau) - rotTarget
  if rotDiff > Pi:
    rotDiff -= Tau
  if rotDiff < -Pi:
    rotDiff += Tau

  if abs(rotDiff) <= 0.1:
    ent.rotation = rotTarget
  else:
    ent.rotation += dt * RotationSpeed * -sgn(rotDiff).float32

  if not ent.fullyMoved():
    let
      progress = ent.moveProgress / moveTime(ent)
      sineOffset =
        if ent.isSliding:
          vec3(0)
        else:
          vec3(0, sin(progress * Pi) * Height, 0)
    ent.pos = ent.frompos + ent.direction.asVec3 * progress + sineOffset
    ent.moveProgress += dt

proc startSliding*[T](ent: var T) =
  mixin move
  ent.isSliding = true
  discard ent.move(ent.direction)

proc stopSliding*[T](ent: var T) =
  mixin moveTime
  ent.isSliding = false
  ent.toPos = ent.fromPos
  ent.moveProgress = moveTime(ent)

func mapPos*(ent: Entity): Vec3 =
  let pos = ent.posOffset()
  vec3(pos.x.floor, pos.y.floor, pos.z.floor)

