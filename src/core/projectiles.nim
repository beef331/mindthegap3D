import vmath
import directions, resources, consts, cameras
import truss3D/[models, shaders]

const projectileCount = 1024 # Cmon we're not making a bullet hell

var arrowmodel: Model

addResourceProc:
  arrowmodel = loadModel("arrow.dae")

type
  Projectile* = object
    fromPos: Vec3
    toPos: Vec3
    direction: Direction
    moveTime: float32
  ProjectileRange = 0 .. projectileCount - 1
  Projectiles* = object
    active*, inactive*: set[ProjectileRange]
    projectiles: array[projectileCount, Projectile]

iterator mitems(projs: var Projectiles): var Projectile =
  for x in projs.active:
    yield projs.projectiles[x]

iterator items*(projs: Projectiles): Projectile =
  for x in projs.active:
    yield projs.projectiles[x]

iterator idProj*(projs: Projectiles): (int, Projectile) =
  for x in projs.active:
    yield (x, projs.projectiles[x])

proc pos*(projectile: Projectile): Vec3 = mix(projectile.fromPos, projectile.toPos, clamp(projectile.moveTime / MoveTime, 0f..1f))
proc toPos*(projectile: Projectile): Vec3 = projectile.toPos

proc getNextId(projs: var Projectiles): int =
  for x in projs.inactive:
    return x

proc init*(_: typedesc[Projectiles]): Projectiles =
  result.inactive = {ProjectileRange.low .. ProjectileRange.high}
  result.active = {}

proc spawnProjectile*(projs: var Projectiles, pos: Vec3, direction: Direction) =
  let id = projs.getNextId()
  projs.projectiles[id] = Projectile(fromPos: pos + direction.asVec3, toPos: pos + direction.asVec3, direction: direction)
  projs.active.incl id
  projs.inactive.excl id

proc spawnProjectiles*(projs: var Projectiles, toSpawn: seq[Projectile]) =
  for proj in toSpawn:
    projs.spawnProjectile(proj.fromPos, proj.direction)

proc destroyProjectile*(projs: var Projectiles, id: int) =
  projs.active.excl id
  projs.inactive.incl id

template destroyProjectiles*(projs: var Projectiles, i: iterable[int]) =
  for x in i:
    projs.destroyProjectile(x)

proc update*(projs: var Projectiles, dt: float32, playerMoved: bool) =
  for proj in projs.mitems:
    proj.moveTime += dt
    if proj.moveTime >= MoveTime and playerMoved:
      proj.moveTime = 0
      proj.fromPos = proj.toPos
      proj.toPos += proj.direction.asVec3

proc render*(projs: Projectiles, cam: Camera, shader: Shader) =
  with shader:
    for proj in projs:
      let m = mat4() * translate(proj.pos) * rotateY(proj.direction.asRot)
      shader.setUniform("m", m)
      shader.setUniform("mvp", cam.orthoView * m)
      render(arrowmodel)

