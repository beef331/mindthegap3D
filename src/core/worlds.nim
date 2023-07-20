import truss3D, truss3D/[models, textures, gui, particlesystems, audio, instancemodels]
import pixie, opengl, vmath, frosty, gooey
import frosty/streams as froststreams
import resources, cameras, pickups, directions, shadows, signs, tiles, players, projectiles, consts, renderinstances, serializers, fishes, tiledatas, enemies
import std/[options, decls, enumerate, os, streams, macros]


type
  WorldState* = enum
    playing
    previewing
    editing
    enemyEditing ## Placing/editing enemies, should always be on with `editing`
    playerMoving
    enemyMoving

  World* = object
    tiles*: TileData
    signs*: seq[Sign]
    playerSpawn*: int64
    state*: set[WorldState]
    player*: Player
    projectiles*: Projectiles
    history: seq[History]
    enemies: seq[Enemy]

    playerStart {.unserialized.}: Player ## Player stats before moving, meant for history

    finished* {.unserialized.}: bool
    finishTime* {.unserialized.}: float32

    # Editor fields
    inspecting {.unserialized.}: int
    paintKind {.unserialized.}: TileKind = succ(TileKind.low)
    levelName* {.unserialized.}: string

  HistoryKind* = enum
    nothing
    start
    checkpoint

  History = object
    kind: HistoryKind
    player: Player
    tiles: seq[Tile]
    projectiles: Projectiles
    enemies: seq[Enemy]

  PlaceState = enum
    cannotPlace
    placeEmpty
    placeStacked

proc width*(world: World): int64 = world.tiles.width
proc height*(world: World): int64 = world.tiles.height
proc `width=`*(world: var World, newWidth: int64) = world.tiles.width = newWidth
proc `height=`*(world: var World, newHeight: int64) = world.tiles.height = newHeight


iterator activeSign(world: var World): var Sign =
  let pos = ivec2(int32 world.inspecting mod world.width, int32 world.inspecting div world.width)
  for sign in world.signs.mitems:
    if ivec2(sign.pos.xz) == pos:
      yield sign

var
  pickupQuadModel, signModel, flagModel, selectionModel: Model
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

addResourceProc do():
  pickupQuadModel = loadModel("pickup_quad.dae")
  signModel = loadModel("sign.dae")
  flagModel = loadModel("flag.dae")
  selectionModel = loadModel("selection.glb")
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

proc isFinished(world: World): bool =
  result = true
  for x in world.tiles:
    result = x.completed()
    if not result:
      return

proc contains*(world: World, vec: Vec3): bool = vec in world.tiles

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
  world.tiles.data = newTileData
  world.history.setLen(0)

proc enterEnemyEdit(world: var World) =
  world.state.incl {editing, enemyEditing}
  world.inspecting = -1

proc exitEnemyEdit(world: var World) =
  world.state.excl enemyEditing
  world.inspecting = -1

# History Procs
proc saveHistoryStep(world: var World, kind: HistoryKind) =
  var player = world.playerStart
  case kind
  of HistoryKind.start:
    player = world.player
  else: discard

  world.history.add History(kind: kind, tiles: world.tiles.data, projectiles: world.projectiles, player: player, enemies: world.enemies)

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
    world.tiles.data = targetHis.tiles
    world.projectiles = targetHis.projectiles
    world.player = targetHis.player
    world.player.skipMoveAnim()
    world.history.setLen(ind + 1)
    world.enemies = targetHis.enemies

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
    var tile {.byaddr.} = world.tiles[pos]
    let hadSteppedOn = tile.steppedOn
    if tile.kind notin {TileKind.box, ice, key}:
      tile.steppedOn = true
    let 
      playerNextPos = world.player.dir.asVec3() + world.player.mapPos
      nextIndex = world.tiles.getPointIndex(playerNextPos)

    if tile.kind == ice:
      if playerNextPos in world:
        world.player.startSliding()


    if tile.kind != ice or playerNextPos notin world or not world.tiles[nextIndex].isSlidable:
      world.player.stopSliding()

    if tile.isLocked():
      assert world.player.hasKey
      world.player.hasKey = false
      tile.lockState = Unlocked


    case tile.kind
    of checkpoint:
      if not hadSteppedOn:
        world.playerStart = world.player
        world.saveHistoryStep(checkpoint)
    of key:
      if not hadSteppedOn and not world.player.hasKey:
        world.player.hasKey = true
        tile.steppedOn = true
      world.saveHistoryStep(nothing)
    else:
      if tile.isLocked:
        tile.lockState = Unlocked
        world.player.hasKey = false
      world.saveHistoryStep(nothing)

    if not world.finished:
      world.finished = world.isFinished
      if world.finished:
        world.finishTime = LevelCompleteAnimationTime


proc steppedOff(world: var World, pos: Vec3) =
  if pos in world:
    var tile {.byaddr.} = world.tiles[pos]
    case tile.kind
    of box:
      tile.progress = 0
      tile.steppedOn = true
    of ice:
      tile.progress += PI
    else: discard

proc givePickupIfCan(world: var World) =
  ## If the player can get the pickup give it to them else do nothing
  let pos = world.player.movingToPos
  if not world.player.hasPickup and pos in world:
    let index = world.tiles.getPointIndex(pos)
    if world.tiles[index].kind == pickup and world.tiles[index].active:
      world.tiles[index].active = false
      world.player.givePickup world.tiles[index].pickupKind

proc reload*(world: var World, skipStepOn = false) =
  ## Used to reload the world state and reposition player
  if world.history.len > 1:
    world.rewindTo({HistoryKind.start})
  world.unload()
  world.load()
  world.finished = false
  world.history.setLen(0)
  world.saveHistoryStep(start)
  world.player = Player.init(world.getPos(world.playerSpawn.int))
  world.playerStart = world.player
  world.projectiles = Projectiles.init()
  if not skipStepOn:
    world.steppedOn(world.player.pos)
    world.givePickupIfCan()

proc lerp[T](a, b: T, c: float32): T = T(a.ord.float32 + (b.ord - a.ord).float32 * c)
proc reverseLerp[T](f: T, rng: Slice[T]): float32 =
  (f - rng.a) / (rng.b - rng.a)

include worldui # Some times in our lives we all have pain, this is ugly

proc cursorPos(world: World, cam: Camera): Vec3 = cam.raycast(getMousePos()).floor

proc init*(_: typedesc[World], width, height: int): World =
  result = World(
    tiles: TileData(width: width, height: height, data: newSeq[Tile](width * height)),
    projectiles: Projectiles.init(),
    inspecting: -1,
    state: {previewing},
    finishTime : LevelCompleteAnimationTime,
    finished : false,
  )

proc placeStateAt(world: World, pos: Vec3): PlaceState =
  if pos in world and world.tiles.getPointIndex(pos) != world.tiles.getPointIndex(world.player.mapPos):
    let tile = world.tiles[pos]
    case tile.kind:
    of empty:
      placeEmpty
    else:
      if tile.isWalkable() and not tile.hasStacked() and not tile.isLocked:
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
    let index = world.tiles.getPointIndex(vec3(x))
    if world.tiles[index].kind != empty:
      world.tiles[index].stackBox(world.getPos(index) + vec3(0, 1, 0))
    else:
      world.tiles[index] = Tile(kind: box)
  player.clearPickup()

proc placeTile*(world: var World, tile: Tile, pos: IVec2) =
  let ind = world.tiles.getPointIndex(vec3(float pos.x, 0, float pos.y))
  if ind >= 0:
    world.tiles[ind] = tile

proc canPush(world: World, index: int, dir: Direction): bool =
  result = false
  var isLast = false
  var firstIter = true
  for tile in world.tiles.tilesInDir(index, dir, isLast):
    if isLast:
      return false
    case tile.kind
    of Walkable:
      if tile.isLocked():
        return (firstIter and world.player.hasKey)
      if not tile.hasStacked():
        return tile.isWalkable()
    of empty:
      return not tile.hasStacked()
    else: discard
    firstIter = false

proc canWalk(world: World, index: int, dir: Direction, isPlayer: bool): bool =
  let tile = world.tiles[index]
  result = 
    if isPlayer:
      tile.isWalkable and (not tile.isLocked or world.player.hasKey)
    else:
      tile.isWalkable and not tile.isLocked and not tile.hasStacked # enemies cannot push
  if result and tile.hasStacked():
    result = world.canPush(index, dir)

proc getSafeDirections(world: World, index: Natural, isPlayer: bool): set[Direction] =
  if index >= world.width and world.canWalk(index - world.width.int, down, isPlayer):
    result.incl down
  if index + world.width < world.tiles.len and world.canWalk(index + world.width.int, up, isPlayer):
    result.incl up
  if index mod world.width < world.width - 1 and world.canWalk(index + 1, left, isPlayer):
    result.incl left
  if index mod world.width > 0 and world.canWalk(index - 1, right, isPlayer):
    result.incl right


proc pushBlock(world: var World, direction: Direction) =
  let start = world.tiles.getPointIndex(world.player.movingToPos())
  var buffer = world.tiles[start].stacked
  if world.tiles[start].hasStacked():
    for (lastIndex, nextIndex) in world.tiles.tilesInDir(start, direction):
      template nextTile: auto = world.tiles[nextIndex]
      let hadStack = nextTile.hasStacked
      let temp = nextTile.stacked
      nextTile.giveStackedObject(buffer, world.getPos(lastIndex) + vec3(0, 1, 0), world.getPos(nextIndex) + vec3(0, 1, 0))
      buffer = temp
      if not hadStack:
        break
    pushSfx.play()
    world.tiles[start].clearStack()

proc getSafeDirections(world: World, pos: Vec3, isPlayer: bool): set[Direction] =
  if pos in world:
    world.getSafeDirections(world.tiles.getPointIndex(pos), isPlayer)
  else:
    {}

proc playerSafeDirections(world: World): set[Direction] = world.getSafeDirections(world.player.mapPos, true)

proc hoverSign*(world: var World, index: int) =
  world.signs[index].hovered = true

proc getSignColor(index, num: int): float = (index + 1) / num

proc getSignIndex*(world: World, val: float): int = (val * world.signs.len.float).int - 1

proc getSign*(world: World, pos: Vec3): Sign =
  let index = world.tiles.getPointIndex(pos)
  for sign in world.signs.items:
    if world.tiles.getPointIndex(sign.pos) == index:
      result = sign
      break

proc projectileUpdate(world: var World, dt: float32, playerDidMove: bool) =
  var projRemoveBuffer: seq[int]
  for id, proj in world.projectiles.idProj:
    let pos = ivec3(proj.toPos.floor)
    if pos.xz.ivec2 == world.player.mapPos().xz.ivec2:
      world.rewindTo({HistoryKind.checkpoint, start})
      break

    if pos.x notin 0..<world.width.int or pos.z notin 0..<world.height.int:
      projRemoveBuffer.add id
    else:
      let tile = world.tiles[vec3 pos]
      if tile.collides():
        projRemoveBuffer.add id

  world.projectiles.destroyProjectiles(projRemoveBuffer.items)
  world.projectiles.update(dt, playerDidMove)

proc playerMovementUpdate*(world: var World, cam: Camera, dt: float, moveDir: var Option[Direction]) =
  ## Orchestrates player movement and historyWriting for movement
  # Top down game dev
  world.playerStart = world.player
  let wasFullyMoved = world.player.fullymoved
  world.player.update(world.playerSafeDirections(), cam, dt, moveDir, world.finished)

  if world.player.doPlace():
    world.placeBlock(cam)
    world.saveHistoryStep(nothing)

  if moveDir.isSome:
    world.pushBlock(moveDir.get)
    world.steppedOff(world.player.startPos())

  if world.player.fullymoved and not wasFullyMoved:
    world.steppedOn(world.player.movingToPos)

  world.givePickupIfCan()
  if KeycodeP.isDown:
    world.reload()

  if KeycodeZ.isDown:
    world.rewindTo({start, checkpoint})


var 
  worldEditor: typeof(makeEditor((var wrld = default(World); wrld)))
  enemyEditor: typeof(makeEnemyEditor(wrld))

proc setupEditorGui*(world: var World) = 
  worldEditor = makeEditor(world)
  enemyEditor = makeEnemyEditor(world)

proc editorUpdate*(world: var World, cam: Camera, dt: float32, state: var MyUiState, renderTarget: var UiRenderTarget) =
  ## Update for world editor logic
  let isEnemyEditing = enemyEditing in world.state

  if isEnemyEditing:
    enemyEditor.layout(vec3(0), state)
    enemyEditor.interact(state)
    enemyEditor.upload(state, renderTarget)
  else:
    worldEditor.layout(vec3(0), state)
    worldEditor.interact(state)
    worldEditor.upload(state, renderTarget)

  if not state.overAnyUi:
    let
      pos = world.cursorPos(cam)
      ind = world.tiles.getPointIndex(pos)

    if pos in world:
      if isEnemyEditing:
        if leftMb.isPressed:
          if KeycodeLCtrl.isPressed:
            for i, enemy in world.enemies.pairs:
              if pos.xz.ivec2 == enemy.pos.xz.ivec2:
                world.inspecting = i
          elif KeyCodeLShift.isPressed:
            let isValid = block:
              var isValid = true
              for enemy in world.enemies:
                if enemy.pos.xz == pos.xz:
                  isValid = false
                  break
              isValid

            if isValid:
              let pos = vec3(pos.x, 0, pos.z)
              world.enemies.add Enemy.init(pos)
              world.inspecting = world.enemies.high

          elif world.inspecting >= 0: # We have a selected enemy add to path
            let
              enemy {.byaddr.} = world.enemies[world.inspecting]
              dir = enemy.path[^1].directionBetween(pos)
              flooredPos = pos.xz.ivec2

            for i, pos in enemy.path.pairs: 
              if pos.xz.ivec2 == flooredPos:
                enemy.path.setLen(i + 1)
                break

            if dir.isSome and world.tiles[ind].isWalkable and not world.tiles[ind].isLocked:
              var found = false
              for pathPos in enemy.path:
                if pathPos.xz.ivec2 == flooredPos:
                  found = true

              if not found:
                enemy.path.add vec3(pos.x, 0, pos.z)

        if rightMb.isPressed:
          for i, enemy in world.enemies.pairs:
            if enemy.pos.xz == pos.floor.xz:
              world.enemies.del(i)
              world.inspecting = -1
              break


      else:
        if leftMb.isPressed:
          if KeycodeLCtrl.isPressed:
            world.inspecting = world.tiles.getPointIndex(pos)
          else:
            if KeycodeLShift.isPressed:
              world.playerSpawn = ind
              world.history.setLen(0)
              world.reload(skipStepOn = true)

            else:
              world.placeTile(Tile(kind: world.paintKind), pos.xz.ivec2)
              case world.paintKind:
              of box, ice:
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
  for i, (tile, pos) in enumerate world.tiles.tileKindCoords:
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

  for eInd, enemy in world.enemies.pairs:
    let
      ind = world.tiles.getPointIndex(enemy.mapPos)
      tile = world.tiles[ind]

    instance.buffer[RenderedModel.enemies].push mat4() * translate(enemy.pos + vec3(0, tile.calcYPos(true), 0)) * rotateY(enemy.rotation)

    if enemyEditing in world.state and world.inspecting == eInd:
      for i in 0 .. enemy.path.high - 1:
        let 
          pos = enemy.path[i + 1]
          dir = pos.directionBetween(enemy.path[i]).get #enemy.path[i].directionBetween(pos).get

        instance.buffer[RenderedModel.enemies].push mat4() * translate(pos + vec3(0, tile.calcYPos(true), 0)) * scale(vec3(0.3)) * rotateY(dir.asRot + float32(TAU / 4))

  if world.player.hasKey:
    let 
      ind = world.tiles.getPointIndex(world.player.mapPos)
      tile = world.tiles[ind]
    instance.buffer[RenderedModel.keys].push mat4() * translate(world.player.pos + vec3(0, 1, 0) + vec3(0, tile.calcYPos(true), 0)) * rotateY(getTime())

  for buff in instance.buffer:
    buff.reuploadSsbo

proc hitScanCheck*(world: var World, tile: Tile, i: int, dt: float32, renderInstance: var renderinstances.RenderInstance) =
  let stacked = tile.stacked.unsafeGet()
  var hitInd = -1
  for ind in world.tiles.tilesTilCollision(i, stacked.direction):
    hitInd = 
      if world.tiles[ind].collides():
        ind
      else:
        -1
    let pos = world.getPos(ind)
    if floor(pos.x) == floor(world.player.movingToPos.x) and floor(pos.z) == floor(world.player.movingToPos.z):
      world.rewindTo({start, checkpoint}) # Player died
      return

  let thisPos = world.getPos(i)
  var 
    hitPos = 
      if hitInd == -1: # We didnt hit anything, go to the furthest point
        let dirVec = stacked.direction.asVec3
        vec3(thisPos.x + dirVec.x * abs(thisPos.x - float32 world.tiles.width), 0, thisPos.z + dirVec.z * abs(thisPos.z - float32 world.tiles.height)) 
      else:
        world.getPos(hitInd)
  let
    funnyScale = abs(sin(dt * float32 i) * 50)
    theScale = vec3(max(abs(thisPos.x - hitPos.x), funnyScale), funnyScale, max(abs(thisPos.z - hitPos.z), funnyScale))

  hitPos = (thisPos + hitPos) / 2 # Centre it
  hitPos.y = 1.1 + sin(dt * float32 i) * 10 # make it interesting
  renderInstance.buffer[lazes].push mat4() * translate(hitPos) *  scale(theScale) * rotateX(getTime() * 30) * rotateY(stacked.direction.asRot - Tau.float32 / 4f) #* scale(theScale) #* translate(hitPos)
  renderInstance.buffer[lazes].reuploadSsbo()

proc enemiesFinishedMoving(world: World): bool =
  for enemy in world.enemies:
    if not enemy.fullyMoved:
      return false
  true

proc enemyMovementUpdate*(world: var World, dt: float32, playerMoved: bool) =
  for enemy in world.enemies.mitems:
    enemy.update(world.getSafeDirections(enemy.pos, false), dt, world.finished, world.tiles, playerMoved)

proc enemyCollisionCheck*(world: var World) =
  let playerPos = world.player.pos.xz.ivec2
  var toKill {.global.}: seq[int]
  toKill.setLen(0) # reset buffer

  for eInd, enemy in world.enemies.pairs:
    if enemy.pos.xz.ivec2 == playerPos:
      world.rewindTo({checkpoint, start})
    let ind = world.tiles.getPointIndex(enemy.pos)
    if world.tiles[ind].kind == box or world.tiles[ind].hasStacked():
      toKill.add eInd
  for ind in toKill:
    world.enemies.del(ind)


proc update*(
  world: var World;
  cam: Camera;
  dt: float32;
  renderInstance: var renderInstances.RenderInstance;
  uiState: var UiState;
  target: var UiRenderTarget
  ) = # Maybe make camera var...?
  updateModels(world, renderInstance)

  fishes.update(dt)

  if playing in world.state:
    for sign in world.signs.mitems:
      sign.update(dt)

    var moveDir = options.none(Direction)

    if enemyMoving notin world.state:
      world.playerMovementUpdate(cam, dt, moveDir)
      if moveDir.isSome:
        world.state.incl playerMoving

    let startState = world.state
    if {playerMoving, enemyMoving} * world.state == {playerMoving} and world.player.fullymoved:
      world.state.incl enemyMoving
      world.state.excl playerMoving
   
    let playerMoved = playerMoving in startState and playerMoving notin world.state # Union of this might work?

    if enemyMoving in world.state:
      world.enemyMovementUpdate(dt, playerMoved)
      if world.enemiesFinishedMoving:
        world.state.excl {playerMoving, enemyMoving}

    world.enemyCollisionCheck()

    for i, tile in enumerate world.tiles.mitems:
      let startY =
        if tile.kind in {TileKind.box, ice}:
          tile.calcYPos()
        else:
          0f32
      case tile.update(dt, playerMoved)
      of shootProjectile:
        let stacked = tile.stacked.unsafeGet()
        world.projectiles.spawnProjectile(tile.shootPos, stacked.direction)
      of shootHitscan:
        hitScanCheck(world, tile, i, dt, renderInstance)
      of nothing:
        discard

      case tile.kind
      of box, ice:
        if startY > 1 and tile.calcYPos() <= 1:
          splashSfx.play()
          waterParticleSystem.spawn(100, some(world.getPos(i) + vec3(0, 1, 0)))
      else:
        if tile.hasStacked() and tile.shouldSpawnParticle:
          fallSfx.play()
          dirtParticleSystem.spawn(100, some(world.getPos(i) + vec3(0, 1, 0)))

    world.projectileUpdate(dt, playerMoved)

    if KeyCodeF11.isDown and world.state == {playing, editing}:
      world.state = {editing}
      world.reload()
    if world.finished:
      world.finishTime -= dt
      world.finishTime = clamp(world.finishTime, 0.000001, LevelCompleteAnimationTime)
  elif previewing in world.state:
    discard
  elif editing in world.state:
    world.editorUpdate(cam, dt, uiState, target)

  waterParticleSystem.update(dt)
  dirtParticleSystem.update(dt)


# RENDER LOGIC BELOW

proc renderDepth*(world: World, cam: Camera) =
  for (tile, pos) in world.tiles.tileKindCoords:
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

proc render*(world: World, cam: Camera, renderInstance: renderinstances.RenderInstance, state: UiState, fb: FrameBuffer) =
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
      of iceBlocks:
        setUniform("screenTex", fb.colourTexture)
      else: discard

      renderInstance.buffer[kind].render()

  fishes.render(cam)
  let
    thisTile = world.tiles[world.player.startPos]
    nextTile = world.tiles[world.player.movingToPos]
  world.player.render(cam, world.playerSafeDirections, thisTile, nextTile)
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
    
    if world.inspecting >= 0:
      with cursorShader:
        var pos = world.getPos(world.inspecting)
        let modelMatrix = mat4() * translate(pos)
        cursorShader.setUniform("mvp", cam.orthoView * modelMatrix)
        cursorShader.setUniform("m", modelMatrix)
        cursorSHader.setUniform("valid", int32 1)
        render(selectionModel)


    if not state.overAnyUi:
      with cursorShader:
        var pos = world.cursorPos(cam)
        pos.y = 0
        cursorShader.setUniform("valid", ord(pos in world))
        if KeycodeLShift.isPressed:
          pos.y = 1
          let modelMatrix = mat4() * translate(pos)
          cursorShader.setUniform("mvp", cam.orthoView * modelMatrix)
          cursorShader.setUniform("m", modelMatrix)
          render(flagModel)
        else:
          renderBlock(Tile(kind: world.paintKind), cam, cursorShader, cursorShader, pos, true)
  if enemyEditing in world.state:
    if world.inspecting >= 0:
      with cursorShader:
        let pos = world.enemies[world.inspecting].pos
        let modelMatrix = mat4() * translate(pos + vec3(0, EntityOffset, 0))
        cursorShader.setUniform("mvp", cam.orthoView * modelMatrix)
        cursorShader.setUniform("m", modelMatrix)
        cursorSHader.setUniform("valid", int32 1)
        render(selectionModel)



  world.projectiles.render(cam, levelShader)


proc renderWaterSplashes*(cam: Camera) =
  with particleShader:
    glEnable GlDepthTest
    particleShader.setUniform("VP", cam.orthoView)
    waterParticleSystem.render()

    particleShader.setUniform("VP", cam.orthoView)
    dirtParticleSystem.render()
    glDisable(GlBlend)


iterator tiles*(world: World): (int, int, Tile) =
  for i, tile in world.tiles:
    yield (int i mod world.width, int i div world.width, tile)
