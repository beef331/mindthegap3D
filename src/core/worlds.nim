import truss3D, truss3D/[models, textures, gui]
import pixie, opengl, vmath, easings, flatty
import resources, cameras, pickups, directions, shadows, signs, enumutils, tiles, players, projectiles, consts
import std/[sequtils, options, decls, options, strformat, sugar, enumerate]
export toFlatty, fromFlatty

type
  WorldState* = enum
    playing, previewing, editing
  World* = object
    width*, height*: int64
    tiles*: seq[Tile]
    signs*: seq[Sign]
    playerSpawn*: int64
    state*: WorldState
    player*: Player
    projectiles*: Projectiles
    history: seq[History]

    # Editor fields
    inspecting: int
    paintKind: TileKind
    editorGui: seq[UIElement]

  HistoryKind = enum
    nothing, start, checkpoint
  History = object
    kind: HistoryKind
    player: Player
    tiles: seq[Tile]
    projectiles: seq[Projectile]

  PlaceState = enum
    cannotPlace
    placeEmpty
    placeStacked

const projectilesAlwaysCollide = {wall}

var
  pickupQuadModel, signModel, flagModel: Model
  levelShader, cursorShader, alphaClipShader, flagShader, boxShader, signBuffShader: Shader

addResourceProc:
  pickupQuadModel = loadModel("pickup_quad.dae")
  signModel = loadModel("sign.dae")
  flagModel = loadModel("flag.dae")
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
  case dir
  of Direction.up:
    index += world.width.int
    while index < world.tiles.len:
      yield world.tiles[index]
      index += world.width.int

  of down:
    index -= world.width.int
    while index >= 0:
      yield world.tiles[index]
      index -= world.width.int

  of left:
    while (index mod world.width) > 0:
      index -= 1
      yield world.tiles[index]

  of right:
    while (index mod world.width) < world.width - 1:
      index += 1
      yield world.tiles[index]

iterator tilesInDir(world: var World, start: int, dir: Direction): (int, int)=
  ## Yields present and next index
  assert start in 0..<world.tiles.len
  var index = start
  case dir
  of Direction.up:
    while index + world.width.int < world.tiles.len:
      yield (index, index + world.width.int)
      index += world.width.int

  of down:
    while index - world.width.int >= 0:
      yield (index, index - world.width.int)
      index -= world.width.int

  of left:
    while ((index - 1) mod world.width) >= 0:
      yield (index, index - 1)
      dec index

  of right:
    while ((index + 1) mod world.width) < world.width:
      yield (index, index + 1)
      index += 1

emitDropDownMethods(PickupType)

proc lerp(a, b: int, c: float32): int = (a.float32 + (b - a).float32 * c).int
emitScrollbarMethods(int)

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

proc resize*(world: var World, newSize: IVec2) =
  var newTileData = newSeq[Tile](newSize.x * newSize.y)
  for x in 0..<newSize.x:
    if x < world.width:
      for y in 0..<newSize.y:
        if y < world.height:
          newTileData[x + y * newSize.x] = world.tiles[x + y * world.width]
  world.width = newSize.x
  world.height = newSize.y
  world.tiles = newTileData

proc reload(world: var World) =
  ## Used to reload the world state and reposition player
  world.history.setLen(0)
  world.player = Player.init(world.getPos(world.playerSpawn.int))

proc setupEditorGui(world: var World) =
  world.editorGui.setLen(0)
  let wrld = world.addr


  world.editorGui.add:
    makeUi(LayoutGroup):
      size = ivec2(400, 500)
      centre = false
      layoutDirection = vertical
      children:
        makeUi(LayoutGroup):
          size = ivec2(400, 50)
          centre = false
          margin = 0
          children:
            collect:
              for placeable in succ(empty) .. TileKind.high:
                capture(placeable):
                  makeUi(Button):
                    pos = ivec2(10)
                    size = ivec2(50)
                    text = $placeable
                    onClick = proc() =
                      wrld.paintKind = placeable
        makeUi(LayoutGroup):
          pos = ivec2(20, 0)
          size = ivec2(400, 40)
          centre = false
          children:
            makeUi(Label):
              size = ivec2(60, 50)
              text = "Width: "
            makeUi(ScrollBar[int]):
              pos = ivec2(0, 15)
              size = ivec2(100, 20)
              minMax = 3..30
              color = vec4(10)
              backgroundColor = vec4(0.1)
              startPercentage = (world.width - 3).float32 / (30 - 3).float32
              onValueChange =  proc(i: int) =
                wrld[].resize(ivec2(i, wrld.height.int))
                wrld[].reload()
        makeUi(LayoutGroup):
          pos = ivec2(20, 0)
          size = ivec2(400, 40)
          centre = false
          children:
            makeUi(Label):
              size = ivec2(60, 50)
              text = "Height: "
            makeUi(ScrollBar[int]):
              pos = ivec2(0, 15)
              size = ivec2(100, 20)
              minMax = 3..30
              color = vec4(10)
              backgroundColor = vec4(0.1)
              startPercentage = (world.height - 3).float32 / (30 - 3).float32
              onValueChange = proc(i: int) =
                wrld[].resize(ivec2(wrld.width.int, i))
                wrld[].reload()



  world.editorGui.add:
    makeUi(LayoutGroup):
      pos = ivec2(10)
      size = ivec2(200, 500)
      layoutDirection = vertical
      centre = false
      anchor = {top, right}
      visibleCond = proc: bool = wrld.inspecting in 0..wrld.tiles.high
      children:
        makeUi(LayoutGroup):
          size = ivec2(200, 50)
          centre = false
          margin = 0
          visibleCond = proc: bool = wrld.tiles[wrld.inspecting].kind == pickup
          children:
            makeUi(Label):
              size = ivec2(75, 25)
              text = "Pickup: "
            makeUi(Dropdown[PickupType]):
              size = ivec2(75, 25)
              values = PickupType.toSeq
              onValueChange = proc(p: PickupType) = wrld.tiles[wrld.inspecting].pickupKind = p


proc cursorPos(world: World, cam: Camera): Vec3 = cam.raycast(getMousePos()).floor

proc init*(_: typedesc[World], width, height: int): World =
  result = World(width: width, height: height, tiles: newSeq[Tile](width * height), projectiles: Projectiles.init(), inspecting: -1)
  result.setupEditorGui()

proc placeStateAt(world: World, pos: Vec3): PlaceState =
  if pos in world and world.getPointIndex(pos) != world.getPointIndex(world.player.mapPos):
    let tile = world.tiles[world.getPointIndex(pos)]
    case tile.kind:
    of empty:
      placeEmpty
    else:
      if tile.isWalkable() and not tile.hasStacked():
        placeStacked
      else:
        cannotPlace
  else:
    cannotPlace

proc placeBlock(world: var World, cam: Camera) =
  var player {.byaddr.} = world.player
  let
    pos = cam.raycast(getMousePos())
    dir = player.pickupRotation
  for x in player.getPickup.positions(dir, pos):
    if world.placeStateAt(x) == cannotPlace:
      return
  for x in player.getPickup.positions(dir, pos):
    let index = world.getPointIndex(vec3(x))
    if world.tiles[index].kind != empty:
      world.tiles[index].stackBox(world.getPos(index) + vec3(0, 1, 0))
    else:
      world.tiles[index] = Tile(kind: box)
  player.clearPickup()

proc placeTile*(world: var World, tile: Tile, pos: IVec2) =
  let
    newWidth = max(world.width, pos.x)
    newHeight = max(world.height, pos.y)
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
  result = false
  for tile in world.tilesInDir(index, dir):
    case tile.kind
    of Walkable:
      if not tile.hasStacked():
        return tile.isWalkable()
    of empty:
      return true
    else: discard

proc saveHistoryStep(world: var World, kind = HistoryKind.nothing) =
  let projectiles = collect(for x in world.projectiles.items: x)
  world.history.add History(kind: kind, tiles: world.tiles, projectiles: projectiles, player: world.player)

proc saveHistoryStep(world: var World, player: Player, kind = HistoryKind.nothing) =
  let projectiles = collect(for x in world.projectiles.items: x)
  world.history.add History(kind: kind, tiles: world.tiles, projectiles: projectiles, player: player)

proc popHistoryStep(world: var World) =
  if world.history.len > 0:
    let history = world.history.pop
    world.tiles = history.tiles
    world.projectiles = Projectiles.init
    world.projectiles.spawnProjectiles(history.projectiles)
    world.player = history.player
    world.player.skipMoveAnim()
    if history.kind == start:
      world.history.add history

proc rewindTo*(world: var World, targetStates: set[HistoryKind]) =
  world.popHistoryStep()
  while world.history[^1].kind notin targetStates:
    world.popHistoryStep()

proc canWalk(world: World, index: int, dir: Direction): bool =
  let tile = world.tiles[index]
  result = tile.isWalkable()
  if result and tile.hasStacked():
    result = world.canPush(index, dir)

proc getSafeDirections(world: World, index: Natural): set[Direction] =
  if index >= world.width and world.canWalk(index - world.width.int, down):
    result.incl down
  if index + world.width < world.tiles.len and world.canWalk(index + world.width.int, up):
    result.incl up
  if index mod world.width > 0 and world.canWalk(index - 1, left):
    result.incl left
  if index mod world.width < world.width - 1 and world.canWalk(index + 1, right):
    result.incl right

proc pushBlock(world: var World, direction: Direction) =
  let start = world.getPointIndex(world.player.movingToPos())
  var buffer = world.tiles[start].stacked
  if world.tiles[start].hasStacked():
    for (lastIndex, nextIndex) in world.tilesInDir(start, direction):
      template nextTile: auto = world.tiles[nextIndex]
      let hadStack = nextTile.hasStacked
      if nextTile.kind == empty:
        if (buffer.isSome and buffer.get.kind == box):
          nextTile = Tile(kind: box)
        break
      else:
        let temp = nextTile.stacked
        nextTile.giveStackedObject(buffer, world.getPos(lastIndex) + vec3(0, 1, 0), world.getPos(nextIndex) + vec3(0, 1, 0))
        buffer = temp
      if not hadStack:
        break
    world.tiles[start].clearStack()

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
  world.saveHistoryStep(start)

proc update*(world: var World, cam: Camera, dt: float32) = # Maybe make camera var...?
  case world.state
  of playing:
    for sign in world.signs.mitems:
      sign.update(dt)

    var moveDir = none(Direction)
    let
      playerStartPos = world.player.mapPos
      startPlayer = world.player
    world.player.update(world.playerSafeDirections(), cam, dt, moveDir)
    if world.player.doPlace or moveDir.isSome:
      world.saveHistoryStep(startPlayer)
    if world.player.doPlace():
      world.placeBlock(cam)
    if moveDir.isSome:
      world.pushBlock(moveDir.get)
      world.steppedOff(playerStartPos)
      world.givePickupIfCan()
    if KeycodeP.isDown:
      world.popHistoryStep()

    var projRemoveBuffer: seq[int]
    for x in world.tiles.mitems:
      x.update(world.projectiles, dt, moveDir.isSome)


    for id, proj in world.projectiles.idProj:
      let pos = ivec3(proj.pos + vec3(0.5))
      if pos.xz == world.player.mapPos().ivec3.xz:
        world.rewindTo({start, checkpoint})
        break

      if pos.x notin 0..<world.width.int or pos.z notin 0..<world.height.int:
        projRemoveBuffer.add id
      else:
        let tile = world.tiles[world.getPointIndex(pos.vec3)]
        if tile.kind in projectilesAlwaysCollide or (tile.kind != empty and tile.hasStacked()):
          projRemoveBuffer.add id

    world.projectiles.destroyProjectiles(projRemoveBuffer.items)
    world.projectiles.update(dt, moveDir.isSome())
    if KeyCodeF11.isDown:
      world.state = editing

  of previewing:
    discard
  of editing:
    for element in world.editorGui:
      element.update(dt)

    if not overGui:
      let
        pos = world.cursorPos(cam)
        ind = world.getPointIndex(pos)

      if pos in world:
        if leftMb.isPressed:
          if KeycodeLCtrl.isPressed:
            let selectedPos = world.cursorPos(cam)
            if selectedPos in world:
              world.inspecting = world.getPointIndex(selectedPos)
          elif KeycodeLShift.isPressed:
            if pos in world:
              world.playerSpawn = ind
              world.reload()
          else:
            world.placeTile(Tile(kind: world.paintKind), pos.xz.ivec2)
            case world.paintKind:
            of box:
              world.tiles[ind].progress = FallTime
            of pickup:
              world.tiles[ind].active = true
            else:
              discard
            world.reload()
        if rightMb.isPressed:
          world.placeTile(Tile(kind: empty), pos.xz.ivec2)
          world.reload()



    if KeyCodeF11.isDown or KeyCodeEscape.isDown:
      world.state = playing


# RENDER LOGIC BELOW

proc renderDepth*(world: World, cam: Camera) =
  for (tile, pos) in world.tileKindCoords:
    if tile.kind in RenderedTile.low.TileKind .. RenderedTile.high.TileKind:
      case tile.kind:
      of box:
        renderBox(tile, cam, pos, levelShader)
      else:
        renderBlock(tile, cam, levelShader, pos)

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
        let placeState = world.placeStateAt(pos)
        var
          yPos = 0f
          canPlace = true

        case placeState
        of cannotPlace:
          glDisable(GlDepthTest)
          yPos = 0
          canPlace = false
        of placeEmpty:
          yPos = 0
        of placeStacked:
          yPos = 1

        cursorShader.setUniform("valid", canPlace.ord)
        let pos = pos + vec3(0, yPos, 0)
        renderBlock(Tile(kind: box), cam, cursorShader, pos)
        glEnable(GlDepthTest)

proc render*(world: World, cam: Camera) =
  with levelShader:
    for (tile, pos) in world.tileKindCoords:
      if tile.kind in RenderedTile.low.TileKind .. RenderedTile.high.TileKind:
        renderStack(tile, cam, levelShader, pos)
        case tile.kind
        of box:
          renderBox(tile, cam, pos, boxShader)
        of pickup:
          renderPickup(tile, cam, pos, alphaClipShader, levelShader)
        else:
          renderBlock(tile, cam, levelShader, pos)

  renderSigns(world, cam)
  world.player.render(cam, world.playerSafeDirections)
  if world.player.hasPickup:
      world.renderDropCursor(cam, world.player.getPickup, getMousePos(), world.player.pickupRotation)
  world.projectiles.render(cam, levelShader)

  if world.state == editing:
    with flagShader:
      var pos = world.getPos(world.playerSpawn.int)
      pos.y = 1
      let modelMatrix = mat4() * translate(pos)
      flagShader.setUniform("mvp", cam.orthoView * modelMatrix)
      flagShader.setUniform("m", modelMatrix)
      render(flagModel)

    cursorShader.setUniform("valid", ord(world.cursorPos(cam) in world))
    if KeycodeLShift.isPressed:
      var pos = world.cursorPos(cam)
      pos.y = 1
      let modelMatrix = mat4() * translate(pos)
      cursorShader.setUniform("mvp", cam.orthoView * modelMatrix)
      cursorSHader.setUniform("m", modelMatrix)
      render(flagModel)
    else:
      renderBlock(Tile(kind: world.paintKind), cam, cursorShader, world.cursorPos(cam))
    for element in world.editorGui:
      element.draw()

iterator tiles*(world: World): (int, int, Tile) =
  for i, tile in world.tiles:
    yield (int i mod world.width, int i div world.width, tile)
