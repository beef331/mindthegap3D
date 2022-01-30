import directions, pickups

import vmath
type
  TileKind* = enum
    empty
    wall # Insert before wall for non rendered tiles
    floor
    pickup
    box
    shooter
  BlockFlag* = enum
    dropped, pushable
  ProjectileKind* = enum
    hitScan, dynamicProjectile
  Projectile = object
    pos: Vec3
    timeToMove: float32
    direction: Vec3
  Tile* = object
    isWalkable*: bool
    boxFlag*: set[BlockFlag]
    direction*: Direction
    case kind*: TileKind
    of pickup:
      pickupKind*: PickupType
      active*: bool
    of box:
      progress*: float32
      steppedOn*: bool
    of shooter:
      toggledOn*: bool
      timeToShot*: float32
      shotDelay*: float32 # Shooters and boxes are the same, but come here to make editing easier
      projectileKind*: ProjectileKind
      pool*: seq[Projectile]
    else: discard
