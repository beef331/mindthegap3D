import truss3D, truss3D/[models, shaders, textures]
import pixie, opengl, vmath, easings
import resources, cameras, pickups, directions
import std/[sequtils, options, decls]

{.experimental: "overloadableEnums".}

const
  StartHeight = 10f
  FallTime = 1f
  SinkHeight = -1
type
  TileKind* = enum
    empty, wall, floor, pickup, box
  BlockFlag* = enum
    dropped, pushable, shooter
  Tile = object
    isWalkable: bool
    case kind: TileKind
    of pickup:
      pickupKind*: PickupType
      active: bool
    of box:
      boxFlag: set[BlockFlag]
      progress: float32
      steppedOn: bool
    else: discard

  RenderedTile = TileKind.wall..TileKind.box
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
    playerSpawn: int

const
  FloorDrawn = {wall, floor, pickup}
  Paintable = {Tilekind.floor, wall, empty, pickup}
  Walkable = {TileKind.floor, pickup, box}

var
  wallModel, floorModel, pedestalModel, pickupQuadModel, flagModel, boxModel: Model
  levelShader, cursorShader, alphaClipShader, flagShader, boxShader: Shader

addResourceProc:
  floorModel = loadModel("assets/models/floor.dae")
  wallModel = loadModel("assets/models/wall.dae")
  pedestalModel = loadModel("assets/models/pickup_platform.dae")
  pickupQuadModel = loadModel("assets/models/pickup_quad.dae")
  flagModel = loadModel("assets/models/flag.dae")
  levelShader = loadShader("assets/shaders/vert.glsl", "assets/shaders/frag.glsl")
  cursorShader = loadShader("assets/shaders/vert.glsl", "assets/shaders/cursorfrag.glsl")
  alphaClipShader = loadShader("assets/shaders/vert.glsl", "assets/shaders/alphaclip.glsl")
  flagShader = loadShader("assets/shaders/flagvert.glsl", "assets/shaders/frag.glsl")
  boxShader = loadShader("assets/shaders/boxvert.glsl", "assets/shaders/frag.glsl")
  boxModel = loadModel("assets/models/box.dae")
  cursorShader.setUniform("opacity", 0.2)
  cursorShader.setUniform("invalidColour", vec4(1, 0, 0, 1))
  boxShader.setUniform("walkColour", vec4(1, 1, 0, 1))
  boxShader.setUniform("notWalkableColour", vec4(0.3, 0.3, 0.3, 1))


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

proc indexToWorld(world: World, ind: int): Vec3 = vec3((ind mod world.width).float, 0, (ind div world.width).float)

proc cursorValid(world: World, emptyCheck = false): bool =
  let
    index = world.getCursorIndex
    isEmpty = not emptyCheck or (index in 0..<world.tiles.len and world.tiles[index].kind == empty)
  isEmpty and world.cursor in world

proc posValid(world: World, pos: Vec3): bool =
  if pos in world and world.tiles[world.getPointIndex(pos)].kind == empty:
    result = true

proc placeTile*(world: var World) =
  if world.cursorValid(true) and world.state == editing:
    case world.cursorTile
    of pickup:
      world.tiles[world.getCursorIndex] = Tile(kind: pickup, active: true)
    else:
      world.tiles[world.getCursorIndex] = Tile(kind: world.cursorTile)
    world.tiles[world.getCursorIndex].isWalkable = true

proc placeBlock*(world: var World, pos: Vec3, kind: PickupType, dir: Direction): bool =
  block placeBlock:
    for x in kind.positions:
      if not world.posValid(pos + x):
        break placeBlock
    result = true
    for x in kind.positions:
      let index = world.getPointIndex(pos + vec3(x))
      world.tiles[index] = Tile(kind: box, isWalkable: false)

proc placeEmpty*(world: var World) =
  if world.cursor in world:
    world.tiles[world.getCursorIndex] = Tile(kind: empty)

proc nextTile*(world: var World, dir: -1..1) =
  world.cursorTile = ((world.cursorTile.ord + dir + TileKind.high.ord + 1) mod (TileKind.high.ord + 1)).TileKind
  while world.cursorTile notin Paintable:
    world.cursorTile = ((world.cursorTile.ord + dir + TileKind.high.ord + 1) mod (TileKind.high.ord + 1)).TileKind

proc nextOptional*(world: var World, dir: -1..1) = 
  let index = world.getCursorIndex
  case world.tiles[index].kind
  of pickup:
    let pickupKind = world.tiles[index].pickupKind
    world.tiles[index].pickupKind = ((pickupKind.ord + dir + PickupType.high.ord + 1) mod (PickupType.high.ord + 1)).PickupType
  else:
    discard

proc renderBlock(tile: RenderedTile, cam: Camera, shader: Shader, pos: Vec3) =
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
  of box:
    let modelMatrix = mat4() * translate(pos)
    shader.setUniform("mvp", cam.orthoView * modelMatrix)
    shader.setUniform("m", modelMatrix)
    render(boxModel)
  of floor: discard

proc canWalk(tile: Tile): bool = tile.kind in Walkable and tile.isWalkable

proc steppedOff*(world: var World, pos: Vec3) =
  if pos in world:
    var tile {.byaddr.} = world.tiles[world.getPointIndex(pos)]
    case tile.kind
    of box:
      tile.isWalkable = false
      tile.steppedOn = true
      tile.progress = 0
    else: discard

proc getSafeDirections*(world: World, index: Natural): set[Direction] =
  if index > world.width and world.tiles[index - world.width].canWalk():
    result.incl down
  if index + world.width < world.tiles.len and world.tiles[index + world.width].canWalk():
    result.incl up
  if index mod world.width > 0 and world.tiles[index - 1].canWalk():
    result.incl left
  if index mod world.width < world.width - 1 and world.tiles[index + 1].canWalk():
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

proc renderBox(tile: Tile, cam: Camera, pos: Vec3, shader: Shader) =
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
  glUseProgram(levelShader.Gluint)

proc renderDepth*(world: World, cam: Camera, shader: Shader) =
  for (tile, pos) in world.tileKindCoords:
    if tile.kind in RenderedTile.low.TileKind .. RenderedTile.high.TileKind:
      case tile.kind:
      of box:
        renderBox(tile, cam, pos, shader)
      else:
        renderBlock(tile.kind.RenderedTile, cam, shader, pos)

proc render*(world: World, cam: Camera) =
  with levelShader:
    for (tile, pos) in world.tileKindCoords:
      if tile.kind in RenderedTile.low.TileKind .. RenderedTile.high.TileKind:
        case tile.kind
        of box:
          renderBox(tile, cam, pos, boxShader)
        else:
          renderBlock(tile.kind, cam, levelShader, pos)
        if tile.kind == pickup:
          glUseProgram(alphaClipShader.Gluint)
          alphaClipShader.setUniform("tex", getPickupTexture(tile.pickupKind))
          alphaClipShader.setUniform("mvp", cam.orthoView * (mat4() * translate(pos + vec3(0, 1.1, 0))))
          render(pickupQuadModel)
          glUseProgram(levelShader.Gluint)
          

  if world.state == editing:
    with flagShader:
      let
        pos = world.indexToWorld(world.playerSpawn) + vec3(0, 1, 0)
        flagMatrix = mat4() * translate(pos)
      flagShader.setUniform("mvp", cam.orthoView * flagMatrix)
      flagShader.setUniform("m", flagMatrix)
      flagShader.setUniform("time", getTime())
      render(flagModel)

    glDisable(GlDepthTest)
    with cursorShader:
      if world.cursorTile in RenderedTile.low.TileKind .. RenderedTile.high.TileKind:
        cursorShader.setUniform("valid", world.cursorValid(true).ord)
        renderBlock(world.cursorTile.RenderedTile, cam, cursorShader, world.cursor)
    glEnable(GlDepthTest)

proc renderDropCursor*(world: World, cam: Camera, pickup: PickupType, pos: IVec2, dir: Direction) =
  if world.state == playing:
    glDisable(GlDepthTest)
    let start = ivec3(cam.raycast(pos))
    with cursorShader:
      for x in pickup.positions:
        let
          pos = vec3(start) + x
          isValid = pos in world and world.tiles[world.getPointIndex(pos)].kind == empty
        cursorShader.setUniform("valid", isValid.ord)
        renderBlock(box, cam, cursorShader, pos)
    glEnable(GlDepthTest)

proc update*(world: var World, cam: Camera, dt: float32) = # Maybe make camera var...?
  case world.state
  of playing:
    for x in world.tiles.mitems:
      if x.kind == box:
        if x.progress < FallTime:
          x.progress += dt
        elif not x.steppedOn:
          x.progress = FallTime
          x.isWalkable = true
        else:
          x.progress += dt
        x.progress = clamp(x.progress, 0, FallTime)
  of editing:
    world.updateCursor(getMousePos(), cam)
    let scroll = getMouseScroll()
    if scroll != 0:
      if KeycodeLShift.isPressed:
        world.nextOptional(scroll.sgn)
      else:
        world.nextTile(scroll.sgn)

    if leftMb.isPressed:
      world.placeTile()
    if rightMb.isPressed:
      world.placeEmpty()
  of previewing:
    discard
