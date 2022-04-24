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
  BlockFlag* = enum
    dropped, pushable
  ProjectileKind* = enum
    hitScan, dynamicProjectile
  Projectile = object
    pos: Vec3
    timeToMove: float32
    direction: Vec3
  Tile* = object
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
  RenderedTile* = TileKind.wall..TileKind.high



const # Gamelogic constants
  FloorDrawn* = {wall, floor, pickup, shooter}
  Walkable* = {TileKind.floor, pickup, box}
  AlwaysWalkable* = {TileKind.floor, pickup}
  AlwaysCompleted* = {TileKind.floor, wall, shooter, pickup}


proc isWalkable*(tile: Tile): bool =
  (tile.kind in AlwaysWalkable) or
  (tile.kind == Tilekind.box and not tile.steppedOn and tile.progress >= FallTime)

proc canWalk*(tile: Tile): bool = tile.kind in Walkable and tile.isWalkable

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


proc renderBlock*(tile: RenderedTile, cam: Camera, shader: Shader, pos: Vec3, dir: Direction = up) =
  if tile in FloorDrawn:
    let modelMatrix = mat4() * translate(pos)
    shader.setUniform("mvp", cam.orthoView * modelMatrix)
    shader.setUniform("m", modelMatrix)
    render(floorModel)
  case tile:
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
  of TileKind.floor: discard


proc renderBox*(tile: Tile, cam: Camera, pos: Vec3, shader: Shader) =
  var pos = pos
  pos.y =
    if tile.steppedOn:
      mix(0f, SinkHeight, easingsOutBounce(tile.progress / FallTime))
    else:
      mix(StartHeight, 0, easingsOutBounce(tile.progress / FallTime))
  glUseProgram(shader.Gluint)
  let modelMatrix = mat4() * translate(pos)
  shader.setUniform("m", modelMatrix)
  shader.setUniform("mvp", cam.orthoView * modelMatrix)
  shader.setUniform("isWalkable", (tile.isWalkable and not tile.steppedOn).ord)
  render(boxModel)

proc renderPickup*(tile: Tile, cam: Camera, pos: Vec3, shader, defaultShader: Shader) =
  renderBlock(pickup.RenderedTile, cam, defaultShader, pos)
  shader.makeActive()
  shader.setUniform("tex", getPickupTexture(tile.pickupKind))
  shader.setUniform("mvp", cam.orthoView * (mat4() * translate(pos + vec3(0, 1.1, 0))))
  render(pickupQuadModel)
  defaultShader.makeActive()
