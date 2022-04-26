import directions, pickups, cameras, resources
import vmath, easings, opengl
import truss3D/[shaders, models]

const
  StartHeight* = 10f
  FallTime* = 1f
  SinkHeight* = -0.6

var
  floorModel, wallModel, pedestalModel, pickupQuadModel, flagModel, boxModel, signModel: Model

addResourceProc:
  floorModel = loadModel("floor.dae")
  wallModel = loadModel("wall.dae")
  pedestalModel = loadModel("pickup_platform.dae")
  pickupQuadModel = loadModel("pickup_quad.dae")
  flagModel = loadModel("flag.dae")
  boxModel = loadModel("box.dae")
  signModel = loadModel("sign.dae")

type
  TileKind* = enum
    empty
    wall # Insert before wall for non rendered tiles
    floor
    pickup
    box
    shooter
  RenderedTile* = TileKind.wall..TileKind.high
  BlockFlag* = enum
    dropped, pushable
  ProjectileKind* = enum
    hitScan, dynamicProjectile
  Projectile = object
    pos: Vec3
    timeToMove: float32
    direction: Vec3
  Tile* = object
    flags*: set[BlockFlag]
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


const # Gamelogic constants
  FloorDrawn* = {wall, floor, pickup, shooter}
  Walkable* = {TileKind.floor, pickup, box}
  AlwaysWalkable* = {TileKind.floor, pickup}
  AlwaysCompleted* = {TileKind.floor, wall, shooter, pickup}


proc isWalkable*(tile: Tile): bool =
  (tile.kind in AlwaysWalkable) or
  (tile.kind == Tilekind.box and not tile.steppedOn and tile.progress >= FallTime)

proc updateShooter*(shtr: var Tile, dt: float32) =
  assert shtr.kind == shooter
  case shtr.projectileKind
  of dynamicProjectile:
    ## Check if time to shoot another projectile
  of hitScan:
    shtr.timeToShot -= dt
    if shtr.timeToShot <= 0:
      shtr.toggledOn = not shtr.toggledOn
      shtr.timeToShot = shtr.shotDelay
      if shtr.toggledOn:
        echo "Shoot"
    ## Toggle ray

proc updateBox*(boxTile: var Tile, dt: float32) =
  assert boxTile.kind == box
  if boxTile.progress < FallTime:
    boxTile.progress += dt
  elif not boxTile.steppedOn:
    boxTile.progress = FallTime
  else:
    boxTile.progress += dt
  boxTile.progress = clamp(boxTile.progress, 0, FallTime)

proc renderBlock*(tile: Tile, cam: Camera, shader: Shader, pos: Vec3, dir: Direction = up) =
  if tile.kind in FloorDrawn or pushable in tile.flags:
    let modelMatrix = mat4() * translate(pos)
    shader.setUniform("mvp", cam.orthoView * modelMatrix)
    shader.setUniform("m", modelMatrix)
    render(floorModel)
  case tile.kind
  of wall, shooter:
    let modelMatrix = mat4() * translate(pos + vec3(0, 1, 0)) * rotateY dir.asRot
    shader.setUniform("mvp", cam.orthoView * modelMatrix)
    shader.setUniform("m", modelMatrix)
    render(wallModel)
  of pickup:
    let modelMatrix = mat4() * translate(pos + vec3(0, 1, 0))
    shader.setUniform("m", modelMatrix)
    shader.setUniform("mvp", cam.orthoView * modelMatrix)
    render(pedestalModel)
  of box:
    let modelMatrix = mat4() * translate(pos)
    shader.setUniform("mvp", cam.orthoView * modelMatrix)
    shader.setUniform("m", modelMatrix)
    render(boxModel)
  else: discard


proc renderBox*(tile: Tile, cam: Camera, pos: Vec3, shader: Shader) =
  var pos = pos
  let fallTarget =
    if pushable in tile.flags:
      1f
    else:
      0
  pos.y =
    if tile.steppedOn:
      mix(0f, SinkHeight, easingsOutBounce(tile.progress / FallTime))
    else:
      mix(StartHeight, fallTarget, easingsOutBounce(tile.progress / FallTime))
  shader.makeActive()
  if pushable in tile.flags:
    renderBlock(Tile(kind: floor), cam, shader, vec3(pos.x, 0, pos.z))
  let modelMatrix = mat4() * translate(pos)
  shader.setUniform("m", modelMatrix)
  shader.setUniform("mvp", cam.orthoView * modelMatrix)
  shader.setUniform("isWalkable", (tile.isWalkable and not tile.steppedOn).ord)
  render(boxModel)

proc renderPickup*(tile: Tile, cam: Camera, pos: Vec3, shader, defaultShader: Shader) =
  renderBlock(tile, cam, defaultShader, pos)
  shader.makeActive()
  shader.setUniform("tex", getPickupTexture(tile.pickupKind))
  shader.setUniform("mvp", cam.orthoView * (mat4() * translate(pos + vec3(0, 1.1, 0))))
  render(pickupQuadModel)
  defaultShader.makeActive()
