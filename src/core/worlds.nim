import truss3D, truss3D/[models, textures, gui, particlesystems, audio, instancemodels]
import pixie, opengl, vmath, easings, frosty
import frosty/streams as froststreams
import resources, cameras, pickups, directions, shadows, signs, enumutils, tiles, players, projectiles, consts, renderinstances, serializers
import std/[sequtils, options, decls, options, strformat, sugar, enumerate, os, streams, macros]

type
  WorldState* = enum
    playing, previewing, editing
  World* = object
    width*, height*: int64
    tiles*: seq[Tile]
    signs*: seq[Sign]
    playerSpawn*: int64
    state*: set[WorldState]
    player*: Player
    projectiles*: Projectiles
    pastProjectiles: seq[Projectile]
    history: seq[History]
    levelName*: string


    playerStart {.unserialized.}: Player ## Player stats before moving, meant for history

    finished* {.unserialized.}: bool
    finishTime* {.unserialized.}: float32

    # Editor fields
    inspecting {.unserialized.}: int
    paintKind {.unserialized.}: TileKind
    editorGui* {.unserialized.}: seq[UIElement]
    nameInput* {.unserialized.}: TextArea

  HistoryKind* = enum
    nothing, start, checkpoint, ontoBox, pushed, placed
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
  waterParticleShader: Shader
  waterParticleSystem: ParticleSystem
  splashSfx: SoundEffect
  pushSfx: SoundEffect


proc particleUpdate(particle: var Particle, dt: float32, ps: ParticleSystem) {.nimcall.} =
  particle.pos += dt * particle.velocity * 10 * ((particle.lifeTime / ps.lifeTime))
  particle.velocity.y -= dt * 3


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

  splashSfx = loadSound("assets/sounds/blocksplash.wav")
  splashSfx.sound.volume = 0.1

  pushSfx = loadSound("assets/sounds/push.wav")
  pushSfx.sound.volume = 0.3


  waterParticleShader = loadShader(ShaderPath"waterparticlevert.glsl", ShaderPath"waterparticlefrag.glsl")
  waterParticleSystem = initParticleSystem(
    "cube.glb",
    vec3(5, 0, 5),
    vec4(1)..vec4(0, 0.4, 0.6, 0.0),
    0.5,
    vec3(0.1)..vec3(0.003),
    particleUpdate
  )

iterator tileKindCoords(world: World): (Tile, Vec3) =
  for i, tile in world.tiles:
    let
      x = i mod world.width
      z = i div world.width
    yield (tile, vec3(x.float, 0, z.float))

iterator tilesInDir(world: World, index: int, dir: Direction, isLast: var bool): Tile =
  assert index in 0..<world.tiles.len
  case dir
  of Direction.up:
    isLast = index div world.width >= world.height - 1
    for index in countUp(index + world.width.int, world.tiles.high, world.width):
      yield world.tiles[index]
      isLast = index div world.width >= world.height - 1

  of down:
    isLast = index div world.width == 0
    for index in countDown(index - world.width.int, 0, world.width):
      yield world.tiles[index]
      isLast = index div world.width == 0

  of left:
    isLast = index mod world.width >= world.width - 1
    for index in countUp(index, index + (world.width - index mod world.width)):
      yield world.tiles[index]
      isLast = index mod world.width >= world.width - 1

  of right:
    isLast = index mod world.width == 0
    for index in countDown(index, index - index mod world.width):
      yield world.tiles[index]
      isLast = index mod world.width == 0

iterator tilesInDir(world: var World, start: int, dir: Direction): (int, int)=
  ## Yields present and next index
  assert start in 0..<world.tiles.len
  case dir
  of Direction.up:
    for index in countUp(start, world.tiles.high, world.width):
      yield (index, index + world.width.int)

  of down:
    for index in countDown(start, 0, world.width):
      yield (index, index - world.width.int)

  of left:
    for i, _ in enumerate countUp(int start mod world.width, world.width - 1):
      yield (start + i, start + i + 1)

  of right:
    for i, _ in enumerate countDown(int start mod world.width, 0):
      yield (start - i, start - i - 1)

proc isFinished*(world: World): bool =
  result = true
  for x in world.tiles:
    result = x.completed()
    if not result:
      return

proc playedTransition*(world: World): bool = world.isFinished and abs(world.finishTime) <= 0.00001

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
  for i, tile in world.tiles.pairs:
    let (x, y) = (i mod world.width, i div world.width)
    if x < newSize.x and y < newSize.y:
      newTileData[x + y * newSize.x] = tile
  let (playerX, playerY) = (world.playerSpawn mod world.width, world.playerSpawn div world.width)
  world.playerSpawn =
    if playerX in 0..<newSize.x and playerY in 0..<newSize.y:
      playerX + playerY * newSize.x
    else:
      0


  world.width = newSize.x
  world.height = newSize.y
  world.tiles = newTileData
  world.history.setLen(0)

# History Procs
proc saveHistoryStep(world: var World, kind = HistoryKind.nothing) =
  var player = world.playerStart
  case kind
  of HistoryKind.start:
    player = world.player
  else: discard

  world.history.add History(kind: kind, tiles: world.tiles, projectiles: world.pastProjectiles, player: player)

proc rewindTo*(world: var World, targetStates: set[HistoryKind], skipFirst = false) =
  var
    ind: int = -1
    skipped = false

  for i in countDown(world.history.high, 0):
    if not skipFirst or skipped:
      if world.history[i].kind in targetStates:
          ind = i
          break
    skipped = true

  if ind >= 0:
    let targetHis {.cursor.} = world.history[ind]
    world.tiles = targetHis.tiles
    world.projectiles = Projectiles.init
    world.projectiles.spawnProjectiles(targetHis.projectiles)
    world.player = targetHis.player
    world.player.skipMoveAnim()
    world.history.setLen(ind + 1)

proc unload*(world: var World) =
  for sign in world.signs.mitems:
    sign.free()

proc load*(world: var World) =
  for sign in world.signs.mitems:
    sign.load()

  if world.history.len == 0:
    world.saveHistoryStep(start)
  world.finishTime = LevelCompleteAnimationTime


proc serialize*[S](output: var S; world: World) =
  output.saveSkippingFields(world)

proc deserialize*[S](input: var S; world: var World) =
  input.loadSkippingFields(world)
  world.unload()
  world.load()


proc save*(world: World) =
  discard existsOrCreateDir(userLevelPath)
  let path = userLevelPath / world.levelname & ".lvl"
  try:
    let fs = newFileStream(path, fmWrite)
    defer: fs.close()
    fs.freeze(world)
  except Exception as e:
    echo e.msg
    echo userLevelPath

proc fetchUserLevelNames*(): seq[string] =
  for dir in walkDir(userLevelPath, false):
    if dir.kind == pcFile:
      result.add dir.path

proc steppedOn(world: var World, pos: Vec3) =
  if pos in world:
    var tile {.byaddr.} = world.tiles[world.getPointIndex(pos)]
    let hadSteppedOn = tile.steppedOn
    if tile.kind != box:
      tile.steppedOn = true
    case tile.kind
    of checkpoint:
      if not hadSteppedOn:
        world.playerStart = world.player
        world.saveHistoryStep(checkpoint)
    else:
      world.saveHistoryStep(nothing)
    if not world.finished:
      world.finished = world.isFinished
      if world.finished:
        world.finishTime = LevelCompleteAnimationTime


proc steppedOff(world: var World, pos: Vec3) =
  if pos in world:
    var tile {.byaddr.} = world.tiles[world.getPointIndex(pos)]
    case tile.kind
    of box:
      tile.progress = 0
      tile.steppedOn = true
    else: discard

proc givePickupIfCan(world: var World) =
  ## If the player can get the pickup give it to them else do nothing
  let pos = world.player.movingToPos
  if not world.player.hasPickup and pos in world:
    let index = world.getPointIndex(pos)
    if world.tiles[index].kind == pickup and world.tiles[index].active:
      world.tiles[index].active = false
      world.player.givePickup world.tiles[index].pickupKind

proc reload*(world: var World) =
  ## Used to reload the world state and reposition player
  world.unload()
  world.load()
  if world.history.len > 1:
    world.rewindTo({HistoryKind.start})
  world.finished = false
  world.history.setLen(0)
  world.saveHistoryStep(start)
  world.player = Player.init(world.getPos(world.playerSpawn.int))
  world.playerStart = world.player
  world.projectiles = Projectiles.init()
  world.steppedOn(world.player.pos)
  world.givePickupIfCan()

emitDropDownMethods(PickupType)
emitDropDownMethods(StackedObjectKind)
emitDropDownMethods(Direction)

proc lerp(a, b: int, c: float32): int = (a.float32 + (b - a).float32 * c).int
emitScrollbarMethods(int)

proc setupEditorGui*(world: var World) =
  world.editorGui.setLen(0)
  let
    wrld = world.addr
    nineSliceTex = genTexture()
  readImage("assets/uiframe.png").copyTo nineSliceTex

  world.nameInput = makeUi(TextArea):
    size = ivec2(200, 50)
    fontsize = 50
    backgroundColor = vec4(0, 0, 0, 0.5)
    vAlign = MiddleAlign
    onTextChange = proc(s: string) = wrld[].levelName = s

  world.editorGui.add:
    makeUi(LayoutGroup):
      pos = ivec2(10)
      size = ivec2(400, 500)
      centre = false
      layoutDirection = vertical
      children:
        makeUi(LayoutGroup):
          size = ivec2(400, 50)
          centre = false
          margin = 5
          children:
            collect:
              for placeable in succ(empty) .. TileKind.high:
                capture(placeable):
                  makeUi(Button):
                    pos = ivec2(10)
                    size = ivec2(70, 55)
                    text = $placeable
                    backgroundColor = vec4(1)
                    nineSliceSize = 16f32
                    backgroundTex = nineSliceTex
                    fontColor = vec4(1)
                    onClick = proc() =
                      wrld.paintKind = placeable
        makeUi(LayoutGroup):
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
              color = vec4(1)
              backgroundColor = vec4(0.1, 0.1, 0.1, 1)
              startPercentage = (world.width - 3).float32 / (30 - 3).float32
              onValueChange =  proc(i: int) =
                wrld[].resize(ivec2(i, wrld.height.int))
                wrld[].reload()
        makeUi(LayoutGroup):
          size = ivec2(400, 40)
          centre = false
          children:
            makeUi(Label):
              size = ivec2(60, 50)
              text = "Height: "
            makeUi(ScrollBar[int]):
              size = ivec2(100, 20)
              minMax = 3..30
              color = vec4(1)
              backgroundColor = vec4(0.1, 0.1, 0.1, 1)
              startPercentage = (world.height - 3).float32 / (30 - 3).float32
              onValueChange = proc(i: int) =
                wrld[].resize(ivec2(wrld.width.int, i))
        makeUi(LayoutGroup):
          size = ivec2(400, 50)
          centre = false
          margin = 5
          children:
            makeUi(Label):
              size = ivec2(100, 50)
              text = "Level Name: "
            world.nameInput

        makeUi(LayoutGroup):
          size = ivec2(400, 50)
          centre = false
          margin = 5
          children:
            makeUI(Button):
              size = ivec2(100, 50)
              text = "Save"
              backgroundColor = vec4(1)
              nineSliceSize = 16f32
              backgroundTex = nineSliceTex
              onClick = proc() =
                reset wrld[].history
                wrld[].save()


  template inspectingTile: Tile = wrld.tiles[wrld.inspecting]

  const
    labelSize = ivec2(150, 40)
    buttonSize = ivec2(75, 40)

  world.editorGui.add: ## Inspector
    makeUi(LayoutGroup):
      pos = ivec2(10)
      size = ivec2(200, 500)
      layoutDirection = vertical
      margin = 0
      centre = false
      anchor = {top, right}
      visibleCond = proc: bool = wrld.inspecting in 0..wrld.tiles.high
      children:
        makeUi(LayoutGroup): # Pickup selector
          size = ivec2(200, 50)
          centre = false
          margin = 0
          visibleCond = proc: bool = inspectingTile.kind == pickup
          children:
            makeUi(Label):
              size = labelSize
              text = "Pickup:"
              horizontalAlignment = RightAlign
            makeUi(Dropdown[PickupType]):
              size = buttonSize
              margin = 1
              nineSliceSize = 16f32
              backgroundTex = nineSliceTex
              values = PickupType.toSeq
              backgroundColor = vec4(1)
              watchValue = proc: PickupType = inspectingTile.pickupKind
              onValueChange = proc(p: PickupType) = inspectingTile.pickupKind = p

        makeUi(LayoutGroup): # Stacked selector
          size = ivec2(200, 50)
          centre = false
          margin = 0
          visibleCond = proc: bool = inspectingTile.kind in Walkable
          children:
            makeUi(Label):
              size = labelSize
              text = "Stacked:"
              horizontalAlignment = RightAlign
            makeUi(Dropdown[StackedObjectKind]):
              size = buttonSize
              margin = 1
              values = StackedObjectKind.toSeq
              nineSliceSize = 16f32
              backgroundTex = nineSliceTex
              backgroundColor = vec4(1)
              watchValue = proc: StackedObjectKind =
                if inspectingTile.hasStacked:
                  inspectingTile.stacked.get.kind
                else:
                  none
              onValueChange = proc(p: StackedObjectKind) =
                if p != none:
                  let pos = wrld[].getPos(wrld.inspecting) + vec3(0, 1, 0)
                  inspectingTile.giveStackedObject(some(StackedObject(kind: p)), pos, pos)
                else:
                  inspectingTile.clearStack()

        makeUi(LayoutGroup): # Direction selector
          size = ivec2(200, 50)
          centre = false
          margin = 0
          visibleCond = proc: bool = inspectingTile.hasStacked() and inspectingTile.stacked.get.kind == turret
          children:
            makeUi(Label):
              size = labelSize
              text = "Stacked Direction:"
              horizontalAlignment = RightAlign
            makeUi(Dropdown[Direction]):
              size = buttonSize
              margin = 1
              backgroundColor = vec4(1)
              nineSliceSize = 16f32
              backgroundTex = nineSliceTex
              values = Direction.toSeq
              watchValue = proc: Direction =
                inspectingTile.stacked.get.direction
              onValueChange = proc(dir: Direction) =
                inspectingTile.stacked.get.direction = dir
        makeUI(TextArea):
          size = ivec2(200, 100)
          fontsize = 50
          backgroundColor = vec4(0, 0, 0, 0.5)
          vAlign = MiddleAlign
          onTextChange = proc(s: string) =
            let pos = ivec2(int32 wrld.inspecting mod wrld.width, int32 wrld.inspecting div wrld.width)
            for sign in wrld.signs.mitems:
              if ivec2(sign.pos.xz) == pos:
                sign.message = s
                sign.load()
                return # Exit if we already have a sign
            var newSign = Sign.init(vec3(float32 pos.x, 0, float32 pos.y), s)
            newSign.load()
            wrld.signs.add newSign

proc cursorPos(world: World, cam: Camera): Vec3 = cam.raycast(getMousePos()).floor

proc init*(_: typedesc[World], width, height: int): World =
  result = World(
    width: width,
    height: height,
    tiles: newSeq[Tile](width * height),
    projectiles: Projectiles.init(),
    inspecting: -1,
    state: {previewing},
    finishTime : LevelCompleteAnimationTime,
    finished : false,
  )
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

proc canPush(world: World, index: int, dir: Direction): bool =
  result = false
  var isLast = false
  for tile in world.tilesInDir(index, dir, isLast):
    if isLast:
      return false
    case tile.kind
    of Walkable:
      if not tile.hasStacked():
        return tile.isWalkable()
    of empty:
      return not tile.hasStacked()
    else: discard

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
  if index mod world.width < world.width - 1 and world.canWalk(index + 1, left):
    result.incl left
  if index mod world.width > 0 and world.canWalk(index - 1, right):
    result.incl right


proc pushBlock(world: var World, direction: Direction) =
  let start = world.getPointIndex(world.player.movingToPos())
  var buffer = world.tiles[start].stacked
  if world.tiles[start].hasStacked():
    for (lastIndex, nextIndex) in world.tilesInDir(start, direction):
      template nextTile: auto = world.tiles[nextIndex]
      let hadStack = nextTile.hasStacked
      let temp = nextTile.stacked
      nextTile.giveStackedObject(buffer, world.getPos(lastIndex) + vec3(0, 1, 0), world.getPos(nextIndex) + vec3(0, 1, 0))
      buffer = temp
      if not hadStack:
        break
    pushSfx.play()
    world.tiles[start].clearStack()

proc getSafeDirections(world: World, pos: Vec3): set[Direction] =
  if pos in world:
    world.getSafeDirections(world.getPointIndex(pos))
  else:
    {}

proc playerSafeDirections(world: World): set[Direction] = world.getSafeDirections(world.player.mapPos)

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

proc projectileUpdate(world: var World, dt: float32, playerDidMove: bool) =
  if playerDidMove:
    world.pastProjectiles.setLen(0)
    for proj in world.projectiles.items:
      world.pastProjectiles.add proj

  var projRemoveBuffer: seq[int]
  for id, proj in world.projectiles.idProj:
    let pos = ivec3(proj.pos + vec3(0.5))
    if pos.xz == world.player.mapPos().ivec3.xz or ivec2(proj.pos.xz) == ivec2(world.player.mapPos.xz):
      world.rewindTo({HistoryKind.checkpoint, start})
      break

    if pos.x notin 0..<world.width.int or pos.z notin 0..<world.height.int:
      projRemoveBuffer.add id
    else:
      let tile = world.tiles[world.getPointIndex(pos.vec3)]
      if tile.kind in projectilesAlwaysCollide or (tile.kind != empty and tile.hasStacked()):
        projRemoveBuffer.add id

  world.projectiles.destroyProjectiles(projRemoveBuffer.items)
  world.projectiles.update(dt, playerDidMove)

proc playerMovementUpdate*(world: var World, cam: Camera, dt: float, moveDir: var Option[Direction]) =
  ## Orchestrates player movement and historyWriting for movement
  # Top down game dev
  let playerStartPos = world.player.mapPos
  world.playerStart = world.player
  world.player.update(world.playerSafeDirections(), cam, dt, moveDir, world.finished)
  if world.player.doPlace():
    world.placeBlock(cam)
    world.saveHistoryStep(placed)
  if moveDir.isSome:
    world.pushBlock(moveDir.get)
    world.steppedOff(playerStartPos)
    world.steppedOn(world.player.movingToPos)
    world.givePickupIfCan()
  if KeycodeP.isDown:
    world.reload()

  for i, tile in enumerate world.tiles.mitems:
    let startY =
      if tile.kind == box:
        tile.calcYPos()
      else:
        0f32
    tile.update(world.projectiles, dt, moveDir.isSome)

    if tile.kind == box:
      if startY > 1 and tile.calcYPos() <= 1:
        splashSfx.play()
        waterParticleSystem.spawn(100, some(world.getPos(i) + vec3(0, 1, 0)))


proc editorUpdate*(world: var World, cam: Camera, dt: float32) =
  ## Update for world editor logic
  for element in world.editorGui:
      element.update(dt)

  if guiState == nothing:
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
            world.history.setLen(0)
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

      if rightMb.isPressed:
        world.placeTile(Tile(kind: empty), pos.xz.ivec2)

    if (KeyCodeF11.isDown or KeyCodeEscape.isDown) and world.state == {editing}:
      world.history.setLen(0)
      world.saveHistoryStep(start)
      world.state.incl playing
      world.reload()


proc updateModels(world: World, instance: var RenderInstance) =
  for buffer in instance.buffer.mitems:
    buffer.clear()

  for sign in world.signs:
    instance.buffer[RenderedModel.signs].push translate(sign.pos)
  let safeDirs = world.playerSafeDirections()
  for i, (tile, pos) in enumerate world.tileKindCoords:
    case tile.kind
    of FloorDrawn:
      let
        playerXZ = ivec2(int32 ceil(world.player.mapPos.x), int32 ceil(world.player.mapPos.z))
        floorState = block:
          var res = 2i32
          for dir in safeDirs:
            if playerXZ + dir.asVec3.xz.ivec2 == ivec2 pos.xz:
              res = 1
              break
          res
        blockInstance = BlockInstanceData(state: floorState, matrix: translate(pos))

      instance.buffer[RenderedModel.floors].push blockInstance
    of TileKind.checkpoint:
      let
        isWalkable = tile.steppedOn
        blockInstance = BlockInstanceData(state: int32 isWalkable, matrix: translate(pos))
      instance.buffer[RenderedModel.checkpoints].push blockInstance
    else: discard
    updateTileModel(tile, pos, instance)

  for buff in instance.buffer:
    buff.reuploadSsbo


proc update*(world: var World, cam: Camera, dt: float32, renderInstance: var RenderInstance) = # Maybe make camera var...?
  updateModels(world, renderInstance)


  if playing in world.state:
    for sign in world.signs.mitems:
      sign.update(dt)

    var moveDir = none(Direction)

    world.playerMovementUpdate(cam, dt, moveDir)
    world.projectileUpdate(dt, moveDir.isSome)

    if KeyCodeF11.isDown and world.state == {playing, editing}:
      world.state = {editing}
      world.reload()
    if world.finished:
      world.finishTime -= dt
      world.finishTime = clamp(world.finishTime, 0.000001, LevelCompleteAnimationTime)
  elif previewing in world.state:
    discard
  elif {editing} == world.state:
    world.editorUpdate(cam, dt)

  waterParticleSystem.update(dt)

# RENDER LOGIC BELOW

proc renderDepth*(world: World, cam: Camera) =
  for (tile, pos) in world.tileKindCoords:
    if tile.kind in RenderedTile.low.TileKind .. RenderedTile.high.TileKind:
      renderBlock(tile, cam, levelShader, alphaClipShader, pos)

proc renderSignBuff*(world: World, cam: Camera) =
  with signBuffShader:
    for i, x in world.signs:
      let mat = mat4() * translate(x.pos)
      signBuffShader.setUniform("mvp", cam.orthoView * mat)
      signBuffShader.setUniform("signColour", i.getSignColor(world.signs.len))
      render(signModel)

proc renderSigns(world: World, cam: Camera) =
  for sign in world.signs:
    renderShadow(cam, sign.pos, vec3(0.6), 0.7)
    glEnable(GlDepthTest)
    sign.render(cam)

proc renderDropCursor*(world: World, cam: Camera, pickup: PickupType, pos: IVec2, dir: Direction) =
  if playing in world.state:
    let start = ivec3(cam.raycast(pos))
    with cursorShader:
      for pos in pickup.positions(dir, vec3 start):
        let placeState = world.placeStateAt(pos)
        var
          yPos = 0f
          canPlace = true

        case placeState
        of cannotPlace:
          yPos = 0
          canPlace = false
        of placeEmpty:
          yPos = 0
        of placeStacked:
          yPos = 1

        cursorShader.setUniform("valid", canPlace.ord)
        let pos = pos + vec3(0, yPos, 0)
        renderBlock(Tile(kind: box), cam, cursorShader, alphaClipShader, pos, true)
        glEnable(GlDepthTest)

proc render*(world: World, cam: Camera, renderInstance: RenderInstance) =
  for kind in RenderedModel:
    with renderInstance.shaders[kind]:
      setUniform("vp", cam.orthoView)
      const
        activeColour = vec4(1, 1, 0, 1)
        inactiveColour = vec4(0.3, 0.3, 0.3, 1)
      case kind
      of blocks:
        setUniform("activeColour", activeColour)
        setUniform("inactiveColour", inActiveColour)
      of floors:
        const baseColour = vec4(0.49, 0.369, 0.302, 1)

        setUniform("activeColour", mix(activeColour, baseColour, abs(sin(getTime() * 4))))
        setUniform("inactiveColour", baseColour)
      of pickupIcons:
        setUniform("textures", textureArray)
      else: discard


      renderInstance.buffer[kind].render()

  world.player.render(cam, world.playerSafeDirections)
  renderSigns(world, cam)


  if world.player.hasPickup:
    world.renderDropCursor(cam, world.player.getPickup, getMousePos(), world.player.pickupRotation)
  if world.state == {editing}:
    with flagShader:
      var pos = world.getPos(world.playerSpawn.int)
      pos.y = 1
      let modelMatrix = mat4() * translate(pos)
      flagShader.setUniform("mvp", cam.orthoView * modelMatrix)
      flagShader.setUniform("m", modelMatrix)
      render(flagModel)
    if guiState == nothing:
      with cursorShader:
        cursorShader.setUniform("valid", ord(world.cursorPos(cam) in world))
        if KeycodeLShift.isPressed:
          var pos = world.cursorPos(cam)
          pos.y = 1
          let modelMatrix = mat4() * translate(pos)
          cursorShader.setUniform("mvp", cam.orthoView * modelMatrix)
          cursorShader.setUniform("m", modelMatrix)
          render(flagModel)
        else:
          renderBlock(Tile(kind: world.paintKind), cam, cursorShader, cursorShader, world.cursorPos(cam), true)

  world.projectiles.render(cam, levelShader)



proc renderWaterSplashes*(cam: Camera) =
  with waterParticleShader:
    glEnable GlDepthTest
    waterParticleShader.setUniform("VP", cam.orthoView)
    waterParticleSystem.render()

proc renderUI*(world: World) =
  if world.state == {editing}:
    for element in world.editorGui:
      element.draw()

iterator tiles*(world: World): (int, int, Tile) =
  for i, tile in world.tiles:
    yield (int i mod world.width, int i div world.width, tile)
