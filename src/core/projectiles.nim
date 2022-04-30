import vmath
import directions, tiles

const projectileCount = 1024 # Cmon we're not making a bullet hell

type
  Projectile = object
    pos*: Vec3
    direction: Direction
  ProjectileRange = 0 .. projectileCount - 1
  Projectiles* = object
    active*, inactive*: set[ProjectileRange]
    projectiles: array[projectileCount, Projectile]

iterator mitems(projs: var Projectiles): var Projectile =
  for x in projs.active:
    yield projs.projectiles[x]

iterator items(projs: Projectiles): Projectile =
  for x in projs.active:
    yield projs.projectiles[x]

proc getNextId*(projs: var Projectiles): int =
  for x in projs.inactive:
    return x

proc init*(_: typedesc[Projectiles]): Projectiles =
  result.inactive = {ProjectileRange.low .. ProjectileRange.high}
  result.active = {}

proc spawnProjectile*(projs: var Projectiles, pos: Vec3, direction: Direction) =
  let id = projs.getNextId()
  projs.projectiles[id] = Projectile(pos: pos, direction: direction)

proc destroyProjectile*(projs: var Projectiles, id: int) =
  projs.active.excl id
  projs.inactive.incl id

proc update*(projs: var Projectiles, dt: float32) =
  for proj in projs.mitems:
    proj.pos += proj.direction.asVec3 * dt



