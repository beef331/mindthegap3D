import directions, pickups, cameras, resources, consts, renderinstances
import vmath, easings, opengl, pixie
import truss3D/[shaders, models, textures]
import std/[options, decls, setutils]


var
  floorModel, wallModel, pedestalModel, pickupQuadModel: Model
  checkpointModel, flagModel, boxModel, iceModel, signModel, crossbowmodel: Model
  quadModel: Model
  progressShader: Shader
  progressTex: Texture

proc makeQuad(width, height: float32): Model =
  var data: MeshData[Vec3]
  let halfPos = vec3(width / 2, height / 2, 0)
  data.appendVerts([vec3(0) - halfPos, vec3(width, height, 0) - halfPos, vec3(0, height, 0) - halfPos, vec3(width, 0, 0) - halfPos].items)
  data.appendUV([vec2(1, 1), vec2(0, 0), vec2(1, 0), vec2(0, 1)].items)
  data.append([1u32, 0, 2, 0, 1, 3].items)
  result = data.uploadData()

addResourceProc do():
  floorModel = loadModel("floor.dae")
  wallModel = loadModel("wall.dae")
  pedestalModel = loadModel("pickup_platform.dae")
  pickupQuadModel = loadModel("pickup_quad.dae")
  flagModel = loadModel("flag.dae")
  boxModel = loadModel("box.dae")
  iceModel = loadModel("ice.glb")
  signModel = loadModel("sign.dae")
  crossbowmodel = loadModel("crossbow.dae")
  checkpointModel = loadModel("checkpoint.dae")
  quadModel = makeQuad(1, 1)
  progressShader = loadShader(ShaderPath"texvert.glsl", ShaderPath"animtextfrag.glsl")
  progressTex = genTexture()
  readImage("assets/progress.png").copyto progressTex

type
  TileKind* = enum
    empty = "Empty"
    wall = "Wall"# Insert before wall for non rendered tiles
    checkpoint = "Checkpoint"
    floor = "Floor"
    pickup = "Pickup"
    box = "Box"
    ice = "Ice"
    key = "Key"

  RenderedTile* = TileKind.wall..TileKind.high

  StackedObjectKind* = enum
    none = "None"
    turret = "Turret"
    box = "Box"
    ice = "Ice"

  StackedFlag = enum
    spawnedParticle
    toggled

  ShotRange* = 0i8..10i8

  StackedObject* = object
    startPos: Vec3
    toPos: Vec3
    moveTime: float32
    flags: set[StackedFlag]
    case kind*: StackedObjectKind
    of turret:
      direction*: Direction
      turnsToNextShot*: ShotRange
      turnsPerShot*: ShotRange
      projectileKind*: ProjectileKind
    of box, ice:
      discard
    of none: discard


  ProjectileKind* = enum
    hitScan = "Hit Scan"
    dynamicProjectile = "Dynamic"

  TileFlags = enum
    locked # Whether this tile requires a lock to access
    reserved

  Tile* = object
    stacked*: Option[StackedObject]
    direction*: Direction
    steppedOn*: bool
    flags: set[TileFlags]
    case kind*: TileKind
    of pickup:
      pickupKind*: PickupType
      active*: bool
    of box, ice:
      progress*: float32
    of key:
      discard
    else: discard

  TileActionState* = enum
    nothing
    shootProjectile
    shootHitscan


  LockState* = enum
    Unlocked
    Locked

  NonEmpty* = range[succ(TileKind.empty)..TileKind.high]

const # Gamelogic constants
  FloorDrawn* = {wall, floor, pickup, key}
  AlwaysWalkable* = {TileKind.floor, pickup, checkpoint, ice, key}
  Walkable* = {box} + AlwaysWalkable
  FallingTiles* = {TileKind.box, ice}
  FallingStacked* = {StackedObjectKind.box, ice}
  ProjectilesAlwaysCollide = {wall}

proc shootPos*(t: Tile): Vec3 = t.stacked.unsafeGet.startPos + vec3(0, 0.5, 0)

proc completed*(t: Tile): bool =
  case t.kind:
  of checkpoint:
    t.steppedOn
  else:
    true

proc clampedProgress(progress: float32): float32 = clamp(outBounce(progress), 0f, 1f)

proc hasStacked*(tile: Tile): bool = tile.stacked.isSome()
proc fullyStacked*(tile: Tile): bool =
  assert tile.hasStacked
  tile.stacked.unsafeGet.moveTime >= MoveTime

proc shouldSpawnParticle*(tile: var Tile): bool =
  assert tile.hasStacked()
  let
    stacked {.cursor.} = tile.stacked.unsafeGet
    y = stacked.startPos.y.mix(stacked.toPos.y, clampedProgress(stacked.moveTime / MoveTime))

  result = abs(1f - y) < 0.05 and (spawnedParticle notin tile.stacked.get.flags)
  if result:
    tile.stacked.get.flags.incl spawnedParticle

proc isLocked*(tile: Tile): bool = locked in tile.flags
proc `lockState=`*(tile: var Tile, val: LockState) = tile.flags[locked] = bool(val)

proc isWalkable*(tile: Tile): bool =
  if tile.hasStacked():
    (tile.stacked.unsafeget.moveTime >= MoveTime)
  else:
    (tile.kind in AlwaysWalkable) or
    (tile.kind == Tilekind.box and not tile.steppedOn and tile.progress >= FallTime)

proc collides*(tile: Tile): bool = tile.kind in ProjectilesAlwaysCollide or (tile.kind != empty and tile.hasStacked())

proc isSlidable*(tile: Tile): bool = tile.isWalkable and not tile.hasStacked and locked notin tile.flags

proc canStackOn*(tile: Tile): bool =
  not tile.hasStacked() and tile.isWalkable

proc stackBox*(tile: var Tile, pos: Vec3) = 
  tile.stacked = some(StackedObject(kind: box, startPos: pos + vec3(0, 10, 0), toPos: pos))

proc giveStackedObject*(tile: var Tile, stackedObj: Option[StackedObject], fromPos, toPos: Vec3) =
  tile.stacked = stackedObj
  if tile.hasStacked():
    if fromPos == toPos:
      tile.stacked.get.flags.incl spawnedParticle
    tile.stacked.get.moveTime = 0
    tile.stacked.get.startPos = fromPos
    tile.stacked.get.toPos = toPos

proc clearStack*(frm: var Tile) = frm.stacked = none(StackedObject)

proc updateFalling*(tile: var Tile, dt: float32) =
  assert tile.kind in FallingTiles
  tile.progress += dt

proc calcYPos*(tile: Tile): float32 =
  ## Calculates drop pos for boxes
  case tile.kind
  of FallingTiles:
    result = block:
      let clampedProgress = outBounce(clamp(tile.progress / FallTime, 0f..FallTime))
      if tile.steppedOn:
        mix(0f, SinkHeight, clampedProgress)
      else:
        mix(StartHeight, 0, clampedProgress)
    if tile.progress >= FallTime:
      result += sin(tile.progress * 3) * 0.1
  of pickup:
    result = 0.1
  else:
    result = 0

proc update*(tile: var Tile, dt: float32, playerMoved: bool): TileActionState =
  case tile.kind
  of box, ice:
    tile.updateFalling(dt)
  of empty:
    if tile.hasStacked() and tile.stacked.unsafeGet.moveTime >= MoveTime:
      let kind = tile.stacked.unsafeGet.kind

      if kind in FallingStacked:
        case kind
        of box:
          tile = Tile(kind: box, progress: 0.65) # TODO: Replace with invert lerp
        of ice:
          tile = Tile(kind: ice, progress: 0.65) # TODO: Replace with invert lerp
        else: discard

      else:
        tile.stacked = none(StackedObject)
  else: discard

  if tile.hasStacked():
    tile.stacked.get.moveTime += dt
    let stacked {.byaddr.} = tile.stacked.get
    case stacked.kind
    of turret:
      if playerMoved:
        case stacked.turnsToNextShot
        of 0:
          case stacked.projectileKind
          of hitScan:
            stacked.flags[toggled] = toggled notin stacked.flags
          of dynamicProjectile:
            result = shootProjectile
          stacked.turnsToNextShot = stacked.turnsPerShot
        else:
          dec stacked.turnsToNextShot

      if toggled in stacked.flags:
          result = shootHitscan

    else: discard

proc renderBlock*(tile: Tile, cam: Camera, shader, transparentShader: Shader, pos: Vec3, drawAtPos = false)

proc renderStack*(tile: Tile, cam: Camera, shader: Shader, pos: Vec3) =
  if tile.hasStacked():
    let
      stacked = tile.stacked.get
      pos = mix(stacked.startPos, stacked.toPos, clampedProgress(stacked.moveTime / MoveTime))
    case tile.stacked.get.kind
    of box, ice:
      let kind =
        if tile.stacked.get.kind == box:
          TileKind.box
        else:
          ice

      renderBlock(Tile(kind: kind), cam, shader, shader, pos, true)
    of turret:
      let modelMatrix = mat4() * translate(pos) * rotateY stacked.direction.asRot
      shader.setUniform("mvp", cam.orthoView * modelMatrix)
      shader.setUniform("m", modelMatrix)
      render(crossbowmodel)
    of none:
      discard

proc updateTileModel*(tile: Tile, pos: Vec3, instance: var RenderInstance) =
  let yOffset =
    if tile.kind in FallingTiles:
      tile.calcYPos()
    else:
      0f

  if tile.isLocked:
    instance.buffer[RenderedModel.lockedwalls].push mat4() * translate(pos + vec3(0, 1, 0))
  
  case tile.kind
  of wall:
    instance.buffer[RenderedModel.walls].push mat4() * translate(pos + vec3(0, 1, 0))
  of pickup:
    instance.buffer[RenderedModel.pickups].push mat4() * translate(pos + vec3(0, 1, 0))
    let blockInstance = BlockInstanceData(state: getPickupTexId(tile.pickupKind), matrix: mat4() * translate(vec3(pos.x, pos.y + 1.1, pos.z)))
    instance.buffer[RenderedModel.pickupIcons].push blockInstance
  of box:
    let
      isWalkable = tile.isWalkable
      blockInstance = BlockInstanceData(state: int32 isWalkable, matrix: mat4() * translate(vec3(pos.x, yOffset, pos.z)))
    instance.buffer[RenderedModel.blocks].push blockInstance

  of ice:
    instance.buffer[RenderedModel.iceBlocks].push mat4() * translate(vec3(pos.x, yOffset, pos.z))
  of key:
    instance.buffer[RenderedModel.pickups].push mat4() * translate(pos + vec3(0, 1, 0))
  else:
    discard

  if tile.hasStacked:
    let stacked = tile.stacked.unsafeget

    var pos = mix(stacked.startPos, stacked.toPos, clamp(outBounce(stacked.moveTime / MoveTime), 0f, 1f))
    if stacked.moveTime > MoveTime:
      pos.y = yOffset + 1

    case stacked.kind
    of turret:
      let modelMatrix = mat4() * translate(pos) * rotateY stacked.direction.asRot
      instance.buffer[RenderedModel.crossbows].push modelMatrix

      if stacked.projectileKind == hitScan: discard
        

    of box:
      instance.buffer[RenderedModel.blocks].push BlockInstanceData(matrix: mat4() * translate(pos))
    of ice:
      instance.buffer[RenderedModel.iceBlocks].push mat4() * translate(pos)
    else: discard

proc renderBlock*(tile: Tile, cam: Camera, shader, transparentShader: Shader, pos: Vec3, drawAtPos = false) =
  case tile.kind
  of wall:
    let modelMatrix = mat4() * translate(pos + vec3(0, 1, 0)) * rotateY tile.direction.asRot
    shader.setUniform("mvp", cam.orthoView * modelMatrix)
    shader.setUniform("m", modelMatrix)
    render(wallModel)
  of pickup:
    with transparentShader:
      transparentShader.setUniform("mvp", cam.orthoView * (mat4() * translate(pos + vec3(0, 1.1, 0))))
      render(pickupQuadModel)
    with shader:
      let modelMatrix = mat4() * translate(pos + vec3(0, 1, 0))
      shader.setUniform("m", modelMatrix)
      shader.setUniform("mvp", cam.orthoView * modelMatrix)
      render(pedestalModel)
  of box, ice:
    var pos = pos
    if not drawAtPos:
      pos.y = tile.calcYPos()
    with shader:
      let modelMatrix = mat4() * translate(pos)
      shader.setUniform("m", modelMatrix)
      shader.setUniform("mvp", cam.orthoView * modelMatrix)
      let model =
        if tile.kind == box:
          boxModel
        else:
          iceModel
      render(model)

  of checkpoint:
    with shader:
      let modelMatrix = mat4() * translate(pos)
      shader.setUniform("mvp", cam.orthoView * modelMatrix)
      shader.setUniform("m", modelMatrix)
      render(checkpointModel)
  of floor:
     with shader:
      let modelMatrix = mat4() * translate(pos)
      shader.setUniform("mvp", cam.orthoView * modelMatrix)
      shader.setUniform("m", modelMatrix)
      render(floorModel)
  of key:
    discard
  of empty: discard
