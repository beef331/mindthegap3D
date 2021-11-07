import vmath
import truss3D, truss3D/[models, shaders, textures]
import pixie
import opengl
import resources, cameras, pickups
import std/[sequtils, fenv]

{.experimental: "overloadableEnums".}
type
  TileKind* = enum
    empty, wall, floor, pickup
  Tile = object
    case kind: TileKind
    of pickup:
      pickupKind*: PickupType
    else: discard

  RenderedTile = TileKind.wall..TileKind.pickup
  BlockFlag* = enum
    dropped, pushable, shooter
  Block* = object
    flags: set[BlockFlag]
    index: int
    worldPos: Vec3
  WorldState = enum
    playing, editing, previewing
  World* = object
    worldState: WorldState
    width, height: int
    tiles: seq[Tile]
    blocks: seq[Block]
    cursor: Vec3
    cursorTile: TileKind

const FloorDrawn = {wall, floor, pickup}

var
  wallModel, floorModel, pedestalModel, pickupQuadModel: Model
  levelShader, cursorShader, alphaClipShader: Shader

addResourceProc do:
  floorModel = loadModel("assets/models/floor.dae")
  wallModel = loadModel("assets/models/wall.dae")
  pedestalModel = loadModel("assets/models/pickup_platform.dae")
  pickupQuadModel = loadModel("assets/models/pickup_quad.dae")
  levelShader = loadShader("assets/shaders/vert.glsl", "assets/shaders/frag.glsl")
  cursorShader = loadShader("assets/shaders/vert.glsl", "assets/shaders/cursorfrag.glsl")
  alphaClipShader = loadShader("assets/shaders/vert.glsl", "assets/shaders/alphaclip.glsl")
  cursorShader.setUniform("opacity", 0.3)
  cursorShader.setUniform("invalidColour", vec4(1, 0, 0, 1))


proc init*(_: typedesc[World], width, height: int): World = 
  result.width = width
  result.height = height
  result.tiles = newSeqWith(width * height, Tile(kind: empty))
  result.cursorTile = floor
  result.worldState = editing
  #[
  for i, x in result.tiles:
    if i mod 5 == 0:
      result.tiles[i] = wall
    if i mod 8 == 0:
      result.tiles[i] = empty
  ]#

iterator tileKindCoords(world: World): (Tile, Vec3) = 
  for i, tile in world.tiles:
    let
      x = i mod world.width
      z = i div world.width
    yield (tile, vec3(x.float, 0, z.float))


proc updateCursor*(world: var World, mouse: IVec2, cam: Camera) =
  world.cursor = cam.raycast(mouse)

proc getCursorIndex(world: World): int = world.cursor.x.int + world.cursor.z.int * world.width
proc cursorInWorld(world: World): bool = world.cursor.x.int in 0..<world.width and world.cursor.z.int in 0..<world.height

proc cursorValid(world: World, emptyCheck = false): bool =
  let
    index = world.getCursorIndex
    isEmpty = not emptyCheck or (index in 0..<world.tiles.len and world.tiles[index].kind == empty)
  isEmpty and world.cursorInWorld()

proc placeBlock*(world: var World) =
  if world.cursorValid(true):
    world.tiles[world.getCursorIndex] = Tile(kind: world.cursorTile)

proc placeEmpty*(world: var World) =
  if world.cursorInWorld():
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
    shader.setUniform("mvp", cam.orthoView * (mat4() * translate(pos)))
    render(floorModel)
  case tile:
  of wall:
    shader.setUniform("mvp", cam.orthoView * (mat4() * translate(pos + vec3(0, 1, 0))))
    render(wallModel)
  of pickup:
    shader.setUniform("mvp", cam.orthoView * (mat4() * translate(pos + vec3(0, 1, 0))))
    render(pedestalModel)
  of floor: discard

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

  if world.worldState == editing:
    glDisable(GlDepthTest)
    with cursorShader:
      if world.cursorTile in RenderedTile.low.TileKind .. RenderedTile.high.TileKind:
        cursorShader.setUniform("valid", world.cursorValid(true).ord)
        drawBlock(world.cursorTile.RenderedTile, cam, cursorShader, world.cursor)
