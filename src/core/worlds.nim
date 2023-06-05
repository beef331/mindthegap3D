import truss3D, truss3D/[models, textures, gui, particlesystems, audio, instancemodels]
import pixie, opengl, vmath, easings, frosty, gooey
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

    playerStart {.unserialized.}: Player ## Player stats before moving, meant for history

    finished* {.unserialized.}: bool
    finishTime* {.unserialized.}: float32

    # Editor fields
    inspecting {.unserialized.}: int
    paintKind {.unserialized.}: TileKind
    levelName* {.unserialized.}: string

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

iterator activeSign(world: var World): var Sign =
  let pos = ivec2(int32 world.inspecting mod world.width, int32 world.inspecting div world.width)
  for sign in world.signs.mitems:
    if ivec2(sign.pos.xz) == pos:
      yield sign

var
  pickupQuadModel, signModel, flagModel: Model
  levelShader, cursorShader, alphaClipShader, flagShader, boxShader, signBuffShader: Shader
  particleShader: Shader
  waterParticleSystem, dirtParticleSystem: ParticleSystem # Need to abstract these
  splashSfx: SoundEffect
  pushSfx: SoundEffect
  fallSfx: SoundEffect


proc waterParticleUpdate(particle: var Particle, dt: float32, ps: ParticleSystem) {.nimcall.} =
  particle.pos += dt * particle.velocity * 10 * ((particle.lifeTime / ps.lifeTime))
  particle.velocity.y -= dt * 3

proc dirtParticleUpdate(particle: var Particle, dt: float32, ps: ParticleSystem) {.nimcall.} =
  particle.pos += dt * particle.velocity * 5
  if particle.lifeTime > ps.lifeTime / 2:
    particle.velocity.y -= dt * 3
  else:
    particle.velocity.y += dt * 3

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

  fallSfx = loadSound("assets/sounds/blockfall.wav")
  fallSfx.sound.volume = 0.3


  particleShader = loadShader(ShaderPath"waterparticlevert.glsl", ShaderPath"waterparticlefrag.glsl")
  waterParticleSystem = initParticleSystem(
    "cube.glb",
    vec3(0),
    vec4(1)..vec4(0, 0.4, 0.6, 0.0),
    0.5,
    vec3(0.1)..vec3(0.003),
    waterParticleUpdate
  )

  dirtParticleSystem = initParticleSystem(
    "cube.glb",
    vec3(0),
    vec4(0.52,0.52,0.31,1) .. vec4(0.52,0.52,0.31,1) / 3,
    0.4,
    vec3(0.15)..vec3(0.003),
    dirtParticleUpdate
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

proc lerp[T](a, b: T, c: float32): T = T(a.ord.float32 + (b.ord - a.ord).float32 * c)
proc reverseLerp[T](f: T, rng: Slice[T]): float32 =
  (f - rng.a) / (rng.b - rng.a)

proc makeEditorGui(world: var World): auto =
  const entrySize = vec2(125, 30)

  let world = world.addr

  let saveLabel = TimedLabel(
    color: vec4(1),
    backgroundColor: vec4(0, 0, 0, 0.5),
    pos: vec3(0, 30, 0),
    size: vec2(300, 60),
    anchor: {bottom},
    time: 1)

  let topLeft = VGroup[(
        DropDown[NonEmpty],
        HGroup[(Label, HSlider[int])],
        HGroup[(Label, HSlider[int])],
        HGroup[(Label, TextInput)],
        Button,
        )](
        anchor: {top, left},
        pos: vec3(10, 10, 0),
        size: entrySize,
        margin: 10,
        color: vec4(0),
        backgroundColor: vec4(0, 0, 0, 0.3),
        entries:
        (
          DropDown[NonEmpty](
            size: entrySize,
            active: succ(TileKind.empty),
            color: vec4(0, 0, 0, 0.5),
            hoveredColor: vec4(0, 0, 0, 0.7),
            onChange: proc(kind: NonEmpty) =
              world.paintKind = kind
          ),
          HGroup[(Label, HSlider[int])](
            color: vec4(0),
            entries:(
              Label(text: "Width: ", size: entrySize),
              HSlider[int](
                color: vec4(0.5),
                hoveredColor: vec4(0.3),
                value: world.width,
                watchValue: (proc(): int = int world.width),
                rng: 3..10,
                size: entrySize,
                slideBar: MyUiElement(color: vec4(1)),
                onChange: proc(i: int) =
                  world[].resize(iVec2(i, int world.height))
              )
            )
          ),
          HGroup[(Label, HSlider[int])](
            color: vec4(0),
            entries:(
              Label(text: "Height: ", size: entrySize),
              HSlider[int](
                color: vec4(0.5),
                hoveredColor: vec4(0.3),
                value: world.height,
                watchValue: (proc(): int = int world.height),
                rng: 3..10,
                size: entrySize,
                slideBar: MyUiElement(color: vec4(1)),
                onChange: proc(i: int) =
                  world[].resize(iVec2(int world.width, i))
              )
            )
          ),
          HGroup[(Label, TextInput)](
            color: vec4(0),
            entries:(
              Label(
                size: entrySize,
                text: "World Name:"),
              TextInput(
                color: vec4(0),
                size: entrySize,
                onChange: (proc(s: string) = world[].levelName = s),
                watchValue: (proc(): string = world[].levelName),
              )
            )
          ),
          Button(
            color: vec4(0, 0, 0, 0.5),
            hoveredColor: vec4(0, 0, 0, 0.3),
            size: entrySize, label: Label(text: "Save"),
            clickCb: (proc() =
              try:
                world[].rewindTo({start})
                reset world.history
                world[].save()
                saveLabel.show("Successfully Saved the Level.")
              except CatchableError as e:
                saveLabel.show("Could not save Level. Error: " & e.msg)
            ),
          )
        )
      )

  template inspectingTile: Tile = world[].tiles[world[].inspecting]
  proc isInspecting: bool = editing in world.state and world[].inspecting in 0..world[].tiles.high

  let
    movesPerLabel = Label(size: entrySize, text: "Moves Per Shot: ") 
    movesTilLabel = Label(size: entrySize, text: "Moves Until Next Shot: ")
    topRightEntries = (
        HGroup[(Label, DropDown[PickupType])](
          visible: (proc(): bool = isInspecting() and inspectingTile().kind == pickup),
          color: vec4(0),
          entries:(
            Label(size: entrySize, text: "Pickup Type: "),
            DropDown[PickupType](
              size: entrySize,
              color: vec4(0, 0, 0, 0.5),
              hoveredColor: vec4(0, 0, 0, 0.7),
              watchValue: (proc(): PickupType = inspectingTile().pickupKind),
              onChange: proc(kind: PickupType) =
                inspectingTile().pickupKind = kind
            )
          )
        ),
        HGroup[(Label, DropDown[StackedObjectKind])](
          visible: (proc(): bool = isInspecting() and inspectingTile().kind in Walkable),
          color: vec4(0),
          entries:(
            Label(size: entrySize, text: "Stacked Kind:"),
            DropDown[StackedObjectKind](
              size: entrySize,
              color: vec4(0, 0, 0, 0.5),
              hoveredColor: vec4(0, 0, 0, 0.7),
              watchValue: (proc(): StackedObjectKind =
                if isInspecting() and inspectingTile.hasStacked:
                  inspectingTile.stacked.get.kind
                else:
                  none
              ),
              onChange: proc(kind: StackedObjectKind) =
                if kind != none:
                  let pos = world[].getPos(world[].inspecting) + vec3(0, 1, 0)
                  inspectingTile.giveStackedObject(some(StackedObject(kind: kind)), pos, pos)
                else:
                  inspectingTile.clearStack()
            )
          )
        ),
        HGroup[(Label, DropDown[Direction])](
          visible: (proc(): bool = isInspecting() and inspectingTile().hasStacked and inspectingTile.stacked.get.kind == turret),
          color: vec4(0),
          entries:(
            Label(size: entrySize, text: "Stacked Direction:"),
            DropDown[Direction](
              size: entrySize,
              color: vec4(0, 0, 0, 0.5),
              hoveredColor: vec4(0, 0, 0, 0.7),
              watchValue: (proc(): Direction = inspectingTile.stacked.get.direction),
              onChange: (proc(dir: Direction) = inspectingTile.stacked.get.direction = dir)
            )
          )
        ),
        HGroup[(Label, TextInput)](
          visible: (proc(): bool =  inspectingTile.isWalkable),
          color: vec4(0),
          backgroundColor: vec4(0),
          entries:(
            Label(size: entrySize, text: "Sign Message: "),
            TextInput(
              size: entrySize * vec2(2, 3),
              color: vec4(0, 0, 0, 0.3),
              watchValue: (proc(): string =
                for sign in world[].activeSign:
                  return sign.message
                ""
              ),
              onChange: (proc(str: string) =
                for sign in world[].activeSign:
                  sign.message = str
                  return

                let pos = ivec2(int32 world[].inspecting mod world[].width, int32 world[].inspecting div world[].width)
                var newSign = Sign.init(vec3(float32 pos.x, 0, float32 pos.y), str)
                newSign.load()
                world[].signs.add newSign
              )

            )
          )
        ),
        HGroup[(Label, HSlider[ShotRange])](
          visible: (proc(): bool = isInspecting() and inspectingTile().hasStacked and inspectingTile.stacked.get.kind == turret),
          color: vec4(0),
          backgroundColor: vec4(0),
          entries: (
            movesPerLabel,
            HSlider[ShotRange](
              size: entrySize,
              rng: ShotRange.low..ShotRange.high,
              color: vec4(0.5),
              hoveredColor: vec4(0.3),
              slideBar: MyUiElement(color: vec4(1)),
              watchValue: (proc(): ShotRange = inspectingTile.stacked.get.turnsPerShot),
              onChange: proc(val: ShotRange) =
                inspectingTile.stacked.get.turnsPerShot = val
                movesPerLabel.text = "Moves Per Shot: " & $val
            )
          )
        ),
        HGroup[(Label, HSlider[ShotRange])](
          visible: (proc(): bool = isInspecting() and inspectingTile().hasStacked and inspectingTile.stacked.get.kind == turret),
          color: vec4(0),
          backgroundColor: vec4(0),
          entries: (
            movesTilLabel,
            HSlider[ShotRange](
              size: entrySize,
              rng: ShotRange.low..ShotRange.high,
              color: vec4(0.5),
              hoveredColor: vec4(0.3),
              slideBar: MyUiElement(color: vec4(1)),
              watchValue: (proc(): ShotRange = inspectingTile.stacked.get.turnsToNextShot),
              onChange: proc(val: ShotRange) =
                inspectingTile.stacked.get.turnsToNextShot = val
                movesTilLabel.text = "Moves Until Next Shot: " & $val
            )
          )
        )

      )

    topRight = VGroup[typeof(topRightEntries)](
      anchor: {top, right},
      pos: vec3(10, 10, 0),
      margin: 10,
      color: vec4(0),
      backgroundColor: vec4(0, 0, 0, 0.3),
      visible: isInspecting,
      entries: topRightEntries
    )


  (
    topLeft,
    topRight,
    saveLabel
  )

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
    let pos = ivec3(proj.toPos.floor)
    if pos.xz.ivec2 == world.player.mapPos().xz.ivec2:
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

  if KeycodeZ.isDown:
    world.rewindTo({start, checkpoint})

  for i, tile in enumerate world.tiles.mitems:
    let startY =
      if tile.kind == box:
        tile.calcYPos()
      else:
        0f32
    tile.update(world.projectiles, dt, moveDir.isSome)

    case tile.kind
    of box:
      if startY > 1 and tile.calcYPos() <= 1:
        splashSfx.play()
        waterParticleSystem.spawn(100, some(world.getPos(i) + vec3(0, 1, 0)))
    else:
      if tile.hasStacked() and tile.shouldSpawnParticle:
        fallSfx.play()
        dirtParticleSystem.spawn(100, some(world.getPos(i) + vec3(0, 1, 0)))


var ui: typeof(makeEditorGui((var wrld = default(World); wrld)))

proc setupEditorGui*(world: var World) = ui = makeEditorGui(world)


proc editorUpdate*(world: var World, cam: Camera, dt: float32, state: var MyUiState, renderTarget: var UiRenderTarget) =
  ## Update for world editor logic

  ui.layout(vec3(0), state)
  ui.interact(state)
  ui.upload(state, renderTarget)

  if state.currentElement.isNil: 
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


proc updateModels(world: World, instance: var renderinstances.RenderInstance) =
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


proc update*(
  world: var World;
  cam: Camera;
  dt: float32;
  renderInstance: var renderInstances.RenderInstance;
  uiState: var UiState;
  target: var UiRenderTarget
  ) = # Maybe make camera var...?
  updateModels(world, renderInstance)


  if playing in world.state:
    for sign in world.signs.mitems:
      sign.update(dt)

    var moveDir = options.none(Direction)


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
    world.editorUpdate(cam, dt, uiState, target)

  waterParticleSystem.update(dt)
  dirtParticleSystem.update(dt)


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

proc render*(world: World, cam: Camera, renderInstance: renderinstances.RenderInstance, state: UiState) =
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
    if state.currentElement.isNil:
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
  with particleShader:
    glDisable GlDepthTest
    glEnable(GlBlend)
    glBlendFunc(GlSrcAlpha, GlOneMinusSrcAlpha)
    particleShader.setUniform("VP", cam.orthoView)
    waterParticleSystem.render()

    particleShader.setUniform("VP", cam.orthoView)
    dirtParticleSystem.render()
    glDisable(GlBlend)


iterator tiles*(world: World): (int, int, Tile) =
  for i, tile in world.tiles:
    yield (int i mod world.width, int i div world.width, tile)
