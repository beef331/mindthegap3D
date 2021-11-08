import vmath
import truss3D, truss3D/[models, shaders, textures]
import pixie
import opengl
import resources, cameras, pickups, directions
import std/[sequtils, options]

{.experimental: "overloadableEnums".}
type
  TileKind* = enum
    empty, wall, floor, pickup
  Tile = object
    case kind: TileKind
    of pickup:
      pickupKind*: PickupType
      active: bool
    else: discard

  RenderedTile = TileKind.wall..TileKind.pickup
  BlockFlag* = enum
    dropped, pushable, shooter
  Block* = object
    flags: set[BlockFlag]
    index: int
    worldPos: Vec3
  WorldState* = enum
    playing, editing, previewing
  World* = object
    state*: WorldState
    width, height: int
    tiles: seq[Tile]
    blocks: seq[Block]
    cursor: Vec3
    cursorTile: TileKind

const
  FloorDrawn = {wall, floor, pickup}
  Walkable = {TileKind.floor, TileKind.pickup}

var
  wallModel, floorModel, pedestalModel, pickupQuadModel: Model
  levelShader, cursorShader, alphaClipShader: Shader

addResourceProc:
  floorModel = loadModel("assets/models/floor.dae")
  wallModel = loadModel("assets/models/wall.dae")
  pedestalModel = loadModel("assets/models/pickup_platform.dae")
  pickupQuadModel = loadModel("assets/models/pickup_quad.dae")
  levelShader = loadShader("assets/shaders/vert.glsl", "assets/shaders/frag.glsl")
  cursorShader = loadShader("assets/shaders/vert.glsl", "assets/shaders/cursorfrag.glsl")
  alphaClipShader = loadShader("assets/shaders/vert.glsl", "assets/shaders/alphaclip.glsl")
  cursorShader.setUniform("opacity", 0.2)
  cursorShader.setUniform("invalidColour", vec4(1, 0, 0, 1))


proc init*(_: typedesc[World], width, height: int): World =
  result.width = width
  result.height = height
  result.tiles = newSeqWith(width * height, Tile(kind: empty))
  result.cursorTile = floor
  result.state = editing

iterator tileKindCoords(world: World): (Tile, Vec3) = 
  for i, tile in world.tiles:
    let
      x = i mod world.width
      z = i div world.width
    yield (tile, vec3(x.float, 0, z.float))


proc updateCursor*(world: var World, mouse: IVec2, cam: Camera) =
  let pos = cam.raycast(mouse)
  world.cursor = vec3(pos.x.floor, pos.y, pos.z.floor)

proc contains(world: World, vec: Vec3): bool = vec.x.int in 0..<world.width and vec.z.int in 0..<world.height

proc getCursorIndex(world: World): int =
  if world.cursor in world:
    world.cursor.x.int + world.cursor.z.int * world.width
  else:
    -1

proc getPointIndex(world: World, point: Vec3): int =
  if point in world:
    floor(point.x).int + floor(point.z).int * world.width
  else:
    -1

proc cursorValid(world: World, emptyCheck = false): bool =
  let
    index = world.getCursorIndex
    isEmpty = not emptyCheck or (index in 0..<world.tiles.len and world.tiles[index].kind == empty)
  isEmpty and world.cursor in world

proc placeBlock*(world: var World) =
  if world.cursorValid(true):
    case world.cursorTile
    of pickup:
      world.tiles[world.getCursorIndex] = Tile(kind: pickup, active: true)
    else:
      world.tiles[world.getCursorIndex] = Tile(kind: world.cursorTile)

proc placeEmpty*(world: var World) =
  if world.cursor in world:
    world.tiles[world.getCursorIndex] = Tile(kind: empty)

proc nextTile*(world: var World, dir: -1..1) =
  world.cursorTile = ((world.cursorTile.ord + dir + TileKind.high.ord + 1) mod (TileKind.high.ord + 1)).TileKind

proc nextOptional*(world: var World, dir: -1..1) = 
  let index = world.getCursorIndex
  case world.tiles[index].kind
  of pickup:
    let pickupKind = world.tiles[index].pickupKind
    world.tiles[index].pickupKind = ((pickupKind.ord + dir + PickupType.high.ord + 1) mod (PickupType.high.ord + 1)).PickupType
  else:
    discard

proc drawBlock(tile: RenderedTile, cam: Camera, shader: Shader, pos: Vec3) =
  if tile in FloorDrawn:
    let modelMatrix = mat4() * translate(pos)
    shader.setUniform("mvp", cam.orthoView * modelMatrix)
    shader.setUniform("m", modelMatrix)
    render(floorModel)
  case tile:
  of wall:
    let modelMatrix = mat4() * translate(pos + vec3(0, 1, 0))
    shader.setUniform("mvp", cam.orthoView * modelMatrix)
    shader.setUniform("m", modelMatrix)
    render(wallModel)
  of pickup:
    let modelMatrix = mat4() * translate(pos + vec3(0, 1, 0))
    shader.setUniform("m", modelMatrix)
    shader.setUniform("mvp", cam.orthoView * modelMatrix)
    render(pedestalModel)
  of floor: discard

proc getSafeDirections*(world: World, index: Natural): set[Direction] =
  if index > world.width and world.tiles[index - world.width].kind in Walkable:
    result.incl down
  if index + world.width < world.tiles.len and world.tiles[index + world.width].kind in Walkable:
    result.incl up
  if index mod world.width > 0 and world.tiles[index - 1].kind in Walkable:
    result.incl left
  if index mod world.width < world.width - 1 and world.tiles[index + 1].kind in Walkable:
    result.incl right

proc getSafeDirections*(world: World, pos: Vec3): set[Direction] =
  if pos in world:
    world.getSafeDirections(world.getPointIndex(pos))
  else:
    {}

proc getPickups*(world: var World, pos: Vec3): Option[PickupType] =
  if pos in world:
    let index = world.getPointIndex(pos)
    if world.tiles[index].kind == pickup and world.tiles[index].active:
      world.tiles[index].active = false
      result = some(world.tiles[index].pickupKind)

proc render*(world: World, cam: Camera) =
  glEnable(GlDepthTest)
  with levelShader:
    for (tile, pos) in world.tileKindCoords:
      if tile.kind in RenderedTile.low.TileKind .. RenderedTile.high.TileKind:
        drawBlock(tile.kind, cam, levelShader, pos)
        if tile.kind == pickup:
          glUseProgram(alphaClipShader.Gluint)
          alphaClipShader.setUniform("tex", getPickupTexture(tile.pickupKind))
          alphaClipShader.setUniform("mvp", cam.orthoView * (mat4() * translate(pos + vec3(0, 1.1, 0))))
          render(pickupQuadModel)
          glUseProgram(levelShader.Gluint)

  if world.state == editing:
    glDisable(GlDepthTest)
    with cursorShader:
      if world.cursorTile in RenderedTile.low.TileKind .. RenderedTile.high.TileKind:
        cursorShader.setUniform("valid", world.cursorValid(true).ord)
        drawBlock(world.cursorTile.RenderedTile, cam, cursorShader, world.cursor)
    glEnable(GlDepthTest)

proc renderDrop*(world: World, cam: Camera, pickup: PickupType, pos: IVec2, dir: Direction) =
  if world.state == playing:
    glDisable(GlDepthTest)
    let start = ivec3(cam.raycast(pos))
    with cursorShader:
      for x in pickup.positions:
        let
          pos = vec3(start) + x
          isValid = pos in world and world.tiles[world.getPointIndex(pos)].kind == empty
        cursorShader.setUniform("valid", isValid.ord)
        drawBlock(floor, cam, cursorShader, pos)
    glEnable(GlDepthTest)

