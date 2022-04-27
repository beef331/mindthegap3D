import directions, pickups, cameras, resources
import vmath, easings, opengl
import truss3D/[shaders, models]
import std/[options]

const
  StartHeight* = 10f
  FallTime* = 1f
  SinkHeight* = -0.6
  MoveTime = 0.3f
  RotationSpeed = Tau * 3
  Height = 2
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
  RenderedTile* = TileKind.wall..TileKind.high

  StackedObjectKind* = enum
    turret, box

  StackedObject* = object
    startPos: Vec3
    toPos: Vec3
    moveTime: float32
    case  kind*: StackedObjectKind
    of turret:
      direction*: Direction
      toggledOn*: bool
      timeToShot*: float32
      shotDelay*: float32
      projectileKind*: ProjectileKind
      #pool*: seq[Projectile] # Flatty doesnt like this for whatever reason
    of box:
      discard

  ProjectileKind* = enum
    hitScan, dynamicProjectile

  Projectile = object
    pos: Vec3
    timeToMove: float32
    direction: Vec3

  Tile* = object
    stacked*: Option[StackedObject]
    direction*: Direction
    case kind*: TileKind
    of pickup:
      pickupKind*: PickupType
      active*: bool
    of box:
      progress*: float32
      steppedOn*: bool
    else: discard


const # Gamelogic constants
  FloorDrawn* = {wall, floor, pickup}
  Walkable* = {TileKind.floor, pickup, box}
  AlwaysWalkable* = {TileKind.floor, pickup}
  AlwaysCompleted* = {TileKind.floor, wall, pickup}


proc hasStacked*(tile: Tile): bool = tile.stacked.isSome()


proc isWalkable*(tile: Tile): bool =
  if tile.hasStacked():
    (tile.stacked.get.moveTime >= MoveTime)
  else:
    (tile.kind in AlwaysWalkable) or
    (tile.kind == Tilekind.box and not tile.steppedOn and tile.progress >= FallTime)


proc stackBox*(tile: var Tile, pos: Vec3) = tile.stacked =
  some(StackedObject(kind: box, startPos: pos + vec3(0, 10, 0), toPos: pos))

proc giveStackedObject*(tile: var Tile, stackedObj: Option[StackedObject], fromPos, toPos: Vec3) =
  tile.stacked = stackedObj
  if tile.hasStacked():
    tile.stacked.get.moveTime = 0
    tile.stacked.get.startPos = fromPos
    tile.stacked.get.toPos = toPos

proc clearStack*(frm: var Tile) = frm.stacked = none(StackedObject)

proc updateBox*(boxTile: var Tile, dt: float32) =
  assert boxTile.kind == box
  if boxTile.progress < FallTime:
    boxTile.progress += dt
  elif not boxTile.steppedOn:
    boxTile.progress = FallTime
  else:
    boxTile.progress += dt
  boxTile.progress = clamp(boxTile.progress, 0, FallTime)

proc update*(tile: var Tile, dt: float32) =
  case tile.kind
  of box:
    tile.updateBox(dt)
  else: discard

  if tile.hasStacked():
    tile.stacked.get.moveTime += dt


proc renderBlock*(tile: Tile, cam: Camera, shader: Shader, pos: Vec3)

proc renderStack*(tile: Tile, cam: Camera, shader: Shader, pos: Vec3) =
  if tile.hasStacked():
    let
      stacked = tile.stacked.get
      pos = lerp(stacked.startPos, stacked.toPos, clamp(stacked.moveTime / MoveTime, 0f..1f))
    case tile.stacked.get.kind
    of box:
      renderBlock(Tile(kind: box), cam, shader, pos)
    of turret:
      ##renderBlock(Tile(kind: shooter), cam)

proc renderBlock*(tile: Tile, cam: Camera, shader: Shader, pos: Vec3) =
  if tile.kind in FloorDrawn:
    let modelMatrix = mat4() * translate(pos)
    shader.setUniform("mvp", cam.orthoView * modelMatrix)
    shader.setUniform("m", modelMatrix)
    render(floorModel)
  case tile.kind
  of wall:
    let modelMatrix = mat4() * translate(pos + vec3(0, 1, 0)) * rotateY tile.direction.asRot
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
  pos.y =
    if tile.steppedOn:
      mix(0f, SinkHeight, easingsOutBounce(tile.progress / FallTime))
    else:
      mix(StartHeight, 0, easingsOutBounce(tile.progress / FallTime))
  shader.makeActive()

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
