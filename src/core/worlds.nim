import vmath
import truss3D, truss3D/[models, shaders, textures]
import pixie
import opengl
import resources, cameras
import std/[sequtils, fenv]

{.experimental: "overloadableEnums".}
type
  TileKind* = enum
    empty, wall, floor
  RenderedTile = TileKind.wall..TileKind.floor
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
    tiles: seq[TileKind]
    blocks: seq[Block]
    cursor: Vec3
    cursorTile: TileKind

const FloorDrawn = {wall, floor}

var
  wallModel, floorModel: Model
  levelShader: Shader
  cursorShader: Shader

addResourceProc do:
  floorModel = loadModel("assets/floor.dae")
  wallModel = loadModel("assets/wall.dae")
  levelShader = loadShader("assets/vert.glsl", "assets/frag.glsl")
  cursorShader = loadShader("assets/vert.glsl", "assets/cursorfrag.glsl")
  cursorShader.setUniform("opacity", 0.3)
  cursorShader.setUniform("invalidColour", vec4(1, 0, 0, 1))


proc init*(_: typedesc[World], width, height: int): World = 
  result.width = width
  result.height = height
  result.tiles = newSeqWith(width * height, TileKind.empty)
  result.cursorTile = floor
  result.worldState = editing
  #[
  for i, x in result.tiles:
    if i mod 5 == 0:
      result.tiles[i] = wall
    if i mod 8 == 0:
      result.tiles[i] = empty
  ]#

iterator tileKindCoords(world: World): (TileKind, Vec3) = 
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
    isEmpty = not emptyCheck or (index in 0..<world.tiles.len and world.tiles[index] == empty)
  isEmpty and world.cursorInWorld()

proc placeBlock*(world: var World) =
  if world.cursorValid(true):
    world.tiles[world.getCursorIndex] = world.cursorTile

proc placeEmpty*(world: var World) =
  if world.cursorInWorld():
    world.tiles[world.getCursorIndex] = empty

proc nextTile*(world: var World, dir: -1..1) =
  world.cursorTile = ((world.cursorTile.ord + dir + TileKind.high.ord + 1) mod (TileKind.high.ord + 1)).TileKind

proc drawBlock(tile: RenderedTile, cam: Camera, shader: Shader, pos: Vec3) =
  if tile in FloorDrawn:
    shader.setUniform("mvp", cam.orthoView * (mat4() * translate(pos)))
    render(floorModel)
  case tile:
  of wall:
    shader.setUniform("mvp", cam.orthoView * (mat4() * translate(pos + vec3(0, 0.9, 0))))
    render(wallModel)
  of floor: discard

proc render*(world: World, cam: Camera) =
  glEnable(GlDepthTest)
  with levelShader:
    for (tile, pos) in world.tileKindCoords:
      if tile in RenderedTile.low.TileKind .. RenderedTile.high.TileKind:
        drawBlock(tile, cam, levelShader, pos)
        
  if world.worldState == editing:
    glDisable(GlDepthTest)
    with cursorShader:
      if world.cursorTile in RenderedTile.low.TileKind .. RenderedTile.high.TileKind:
        cursorShader.setUniform("valid", world.cursorValid(true).ord)
        drawBlock(world.cursorTile.RenderedTile, cam, cursorShader, world.cursor)
