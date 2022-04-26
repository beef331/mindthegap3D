import truss3D, truss3D/[models, textures]
import pixie, opengl, vmath, easings
import resources, cameras, pickups, directions, shadows, signs, enumutils, tiles, players
import std/[sequtils, options, decls, options]

{.experimental: "overloadableEnums".}

type
  Block* = object
    flags: set[BlockFlag]
    index: int64
    worldPos: Vec3
  WorldState* = enum
    playing, previewing
  World* = object
    width*, height*: int64
    tiles*: seq[Tile]
    blocks: seq[Block]
    cursor: Vec3
    signs*: seq[Sign]
    playerSpawn*: int64
    state*: WorldState
    player*: Player

var
  pickupQuadModel, signModel: Model
  levelShader, cursorShader, alphaClipShader, flagShader, boxShader, signBuffShader: Shader

addResourceProc:
  pickupQuadModel = loadModel("pickup_quad.dae")
  signModel = loadModel("sign.dae")

  levelShader = loadShader(ShaderPath"vert.glsl", ShaderPath"frag.glsl")
  cursorShader = loadShader(ShaderPath"vert.glsl", ShaderPath"cursorfrag.glsl")
  alphaClipShader = loadShader(ShaderPath"vert.glsl", ShaderPath"alphaclip.glsl")
  flagShader = loadShader(ShaderPath"flagvert.glsl", ShaderPath"frag.glsl")
  boxShader = loadShader(ShaderPath"boxvert.glsl", ShaderPath"frag.glsl")
  signBuffShader = loadShader(ShaderPath"vert.glsl", ShaderPath"signbufffrag.glsl")
  cursorShader.setUniform("opacity", 0.6)
  cursorShader.setUniform("invalidColour", vec4(1, 0, 0, 1))
  boxShader.setUniform("walkColour", vec4(1, 1, 0, 1))
  boxShader.setUniform("notWalkableColour", vec4(0.3, 0.3, 0.3, 1))

iterator tileKindCoords(world: World): (Tile, Vec3) =
  for i, tile in world.tiles:
    let
      x = i mod world.width
      z = i div world.width
    yield (tile, vec3(x.float, 0, z.float))

iterator tilesInDir(world: World, startIndex: int, dir: Direction): Tile =
  assert startIndex in 0..<world.tiles.len
  var index = startIndex
  yield world.tiles[startIndex]
  case dir
  of Direction.up:
    while index < world.tiles.len:
      index += world.width.int
      yield world.tiles[index]
  of down:
    while index > 0:
      index -= world.width.int
      yield world.tiles[index]
  of left:
    while index mod world.width > 0:
      index -= 1
      yield world.tiles[index]
  of right:
    while index mod world.width < world.width:
      index += 1
      yield world.tiles[index]


iterator tilesInDir(world: var World, startIndex: int, dir: Direction): var Tile =
  assert startIndex in 0..<world.tiles.len
  var index = startIndex
  yield world.tiles[startIndex]
  case dir
  of Direction.up:
    while index < world.tiles.len:
      index += world.width.int
      yield world.tiles[index]
  of down:
    while index > 0:
      index -= world.width.int
      yield world.tiles[index]
  of left:
    while index mod world.width > 0:
      index -= 1
      yield world.tiles[index]
  of right:
    while index mod world.width < world.width:
      index += 1
      yield world.tiles[index]


proc init*(_: typedesc[World], width, height: int): World =
  World(width: width, height: height, tiles: newSeq[Tile](width * height))

proc isFinished*(world: World): bool =
  for x in world.tiles:
    case x.kind
    of empty:
      return false
    of box:
      if not x.steppedOn:
        return false
    of AlwaysCompleted:
      discard
  result = true

proc contains*(world: World, vec: Vec3): bool =
  floor(vec.x).int in 0..<world.width and floor(vec.z).int in 0..<world.height

proc getPointIndex*(world: World, point: Vec3): int =
  if point in world:
    int floor(point.x).int + floor(point.z).int * world.width
  else:
    -1

proc getPos*(world: World, ind: int): Vec3 = vec3(float ind mod world.width, 0, float ind div world.width)

proc posValid(world: World, pos: Vec3): bool =
  if pos in world and world.tiles[world.getPointIndex(pos)].kind == empty:
    result = true

proc placeBlock(world: var World, cam: Camera) =
  var player {.byaddr.} = world.player
  let
    pos = cam.raycast(getMousePos())
    dir = player.pickupRotation
  for x in player.getPickup.positions(dir, pos):
    if not world.posValid(x):
      return
  for x in player.getPickup.positions(dir, pos):
    let index = world.getPointIndex(vec3(x))
    world.tiles[index] = Tile(kind: box)
  player.clearPickup()

proc resize*(world: var World, newSize: IVec2) =
  var newWorld = World(width: newSize.x, height: newSize.y, tiles: newSeq[Tile](newSize.x * newSize.y))
  for x in 0..<newWorld.width:
    if x < world.width:
      for y in 0..<newWorld.height:
        if y < world.height:
          newWorld.tiles[x + y * newWorld.width] = world.tiles[x + y * world.width]
  world = newWorld

proc placeTile*(world: var World, tile: Tile, pos: IVec2) =
  let
    newWidth = max(world.width, pos.x)
    newHeight = max(world.height, pos.y)
  if newWidth notin 0..<world.width or newHeight notin 0..<world.height:
    world.resize(ivec2(int newWidth, int newHeight))
  let ind = world.getPointIndex(vec3(float pos.x, 0, float pos.y))
  if ind >= 0:
    world.tiles[ind] = tile

proc steppedOff(world: var World, pos: Vec3) =
  if pos in world:
    var tile {.byaddr.} = world.tiles[world.getPointIndex(pos)]
    case tile.kind
    of box:
      tile.steppedOn = true
      tile.progress = 0
    else: discard
    if world.isFinished:
      echo "Donezo"

proc canPush(world: World, index: int, dir: Direction): bool =
  for tile in world.tilesInDir(index, dir):
    case tile.kind
    of box:
      result = pushable in tile.boxFlag
    of TileKind.floor:
      return true
    else:
      result = false
    if not result:
      return

proc canWalk(world: World, index: int, dir: Direction): bool =
  let tile = world.tiles[index]
  result =
    case tile.kind
    of AlwaysWalkable:
      tile.isWalkable()
    of box:
      if pushable in tile.boxFlag:
        world.canPush(index, dir)
      else:
        tile.isWalkable()
    else: false

proc getSafeDirections(world: World, index: Natural): set[Direction] =
  if index > world.width and world.canWalk(index - world.width.int, down):
    result.incl down
  if index + world.width < world.tiles.len and world.canWalk(index + world.width.int, up):
    result.incl up
  if index mod world.width > 0 and world.canWalk(index - 1, left):
    result.incl left
  if index mod world.width < world.width - 1 and world.canWalk(index + 1, right):
    result.incl right

proc pushBlockIfCan(world: var World, direction: Direction) =
  let
    start = world.getPointIndex(world.player.mapPos)
    startTile = world.tiles[start]
  if startTile.kind == box and pushable in startTile.boxFlag:
    world.tiles[start] = Tile(kind: floor)
    for tile in world.tilesInDir(start, direction):
      if tile.kind == floor:
        tile = startTile # Move first to last
        break

proc getSafeDirections(world: World, pos: Vec3): set[Direction] =
  if pos in world:
    world.getSafeDirections(world.getPointIndex(pos))
  else:
    {}

proc playerSafeDirections(world: World): set[Direction] = world.getSafeDirections(world.player.mapPos)

proc givePickupIfCan(world: var World) =
  ## If the player can get the pickup give it to them else do nothing
  let pos = world.player.movingToPos
  if not world.player.hasPickup and pos in world:
    let index = world.getPointIndex(pos)
    if world.tiles[index].kind == pickup and world.tiles[index].active:
      world.tiles[index].active = false
      world.player.givePickup world.tiles[index].pickupKind

proc hoverSign*(world: var World, index: int) =
  world.signs[index].hovered = true

proc getSignColor(index, num: int): float = (index + 1) / num

proc getSignIndex*(world: World, val: float): int = (val * world.signs.len.float).int - 1

proc getSign*(world: World, pos: Vec3): Sign =
  let index = world.getPointIndex(pos)
  for sign in world.signs.items:
    if world.getPointIndex(sign.pos) == index:
      result = sign
      break

proc unload*(world: var World) =
  for sign in world.signs.mitems:
    sign.free()

proc load*(world: var World) =
  for sign in world.signs.mitems:
    sign.load()

proc update*(world: var World, cam: Camera, dt: float32) = # Maybe make camera var...?
  case world.state
  of playing:
    for sign in world.signs.mitems:
      sign.update(dt)
    for x in world.tiles.mitems:
      case x.kind
      of box:
        x.updateBox(dt)
      of shooter:
        x.updateShooter(dt)
      else:
        discard
    var moveDir = none(Direction)
    let playerStartPos = world.player.mapPos
    world.player.update(world.playerSafeDirections(), cam, dt, moveDir)
    if moveDir.isSome:
      world.steppedOff(playerStartPos)
      world.givePickupIfCan()
      world.pushBlockIfCan(moveDir.get)
    if world.player.doPlace():
      world.placeBlock(cam)
  of previewing:
    discard

# RENDER LOGIC BELOW

proc renderDepth*(world: World, cam: Camera, shader: Shader) =
  for (tile, pos) in world.tileKindCoords:
    if tile.kind in RenderedTile.low.TileKind .. RenderedTile.high.TileKind:
      case tile.kind:
      of box:
        renderBox(tile, cam, pos, shader)
      else:
        renderBlock(tile.kind.RenderedTile, cam, shader, pos)

proc renderSignBuff*(world: World, cam: Camera) =
  for i, x in world.signs:
    let mat = mat4() * translate(x.pos)
    signBuffShader.setUniform("mvp", cam.orthoView * mat)
    signBuffShader.setUniform("signColour", i.getSignColor(world.signs.len))
    render(signModel)

proc renderSigns(world: World, cam: Camera) =
  for sign in world.signs:
    renderShadow(cam, sign.pos, vec3(0.5), 0.9)
    sign.render(cam)
    levelShader.makeActive()
    let mat = mat4() * translate(sign.pos)
    levelShader.setUniform("mvp", cam.orthoView * mat)
    levelShader.setUniform("m", mat)
    render(signModel)

proc renderDropCursor*(world: World, cam: Camera, pickup: PickupType, pos: IVec2, dir: Direction) =
  if world.state == playing:
    let start = ivec3(cam.raycast(pos))
    with cursorShader:
      for pos in pickup.positions(dir, vec3 start):
        let isValid = pos in world and world.tiles[world.getPointIndex(pos)].kind == empty
        if not isValid:
          glDisable(GlDepthTest)
        cursorShader.setUniform("valid", isValid.ord)
        renderBlock(box, cam, cursorShader, pos)
        glEnable(GlDepthTest)

proc render*(world: World, cam: Camera) =
  with levelShader:
    for (tile, pos) in world.tileKindCoords:
      if tile.kind in RenderedTile.low.TileKind .. RenderedTile.high.TileKind:
        case tile.kind
        of box:
          renderBox(tile, cam, pos, boxShader)
        of pickup:
          renderPickup(tile, cam, pos, alphaClipShader, levelShader)
        else:
          renderBlock(tile.kind, cam, levelShader, pos)

  renderSigns(world, cam)
  world.player.render(cam, world.playerSafeDirections)
  if world.player.hasPickup:
      world.renderDropCursor(cam, world.player.getPickup, getMousePos(), world.player.pickupRotation)

iterator tiles*(world: World): (int, int, Tile) =
  for i, tile in world.tiles:
    yield (int i mod world.width, int i div world.width, tile)
