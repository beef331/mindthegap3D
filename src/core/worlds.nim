import vmath, truss3D/[models, shaders, textures]
import pixie
import opengl
import resources
import std/sequtils

{.experimental: "overloadableEnums".}
type
  TileKind* = enum
    empty, wall, floor
  RenderedTile = range[TileKind.wall..TileKind.floor]
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


const floorDrawn = {wall, floor}

var
  wallModel, floorModel: Model
  levelShader: Shader

addResourceProc do:
  floorModel = loadModel("assets/floor.dae")
  wallModel = loadModel("assets/wall.dae")
  levelShader = loadShader("assets/vert.glsl", "assets/frag.glsl")


proc init*(_: typedesc[World], width, height: int): World = 
  result.width = width
  result.height = height
  result.tiles = newSeqWith(width * height, TileKind.floor)
  var i = 0
  for x in result.tiles.mitems:
    if i mod 5 == 0:
      x = wall
    if i mod 8 == 0:
      x = empty
    inc i


proc render*(world: World, viewProj: Mat4) =
  with levelShader:
    for i, tile in world.tiles:
      if tile != empty:
        let
          tile = RenderedTile(tile)
          x = i mod world.width
          y = i div world.height
          pos = vec3(x.float, 0, y.float)
        if tile in floorDrawn:
          levelShader.setUniform("mvp", viewProj * (mat4() * translate(pos) * rotateY(90.toRadians)))
          render(floorModel)
        case tile:
        of wall:
          levelShader.setUniform("mvp", viewProj * (mat4() * translate(pos + vec3(0, 0.9, 0))))
          render(wallModel)
        of floor: discard
