import directions, pickups, cameras, resources, projectiles, consts, renderinstances
import vmath, easings, opengl, pixie
import truss3D/[shaders, models, textures, instancemodels]
import std/[options, decls]


var
  floorModel, wallModel, pedestalModel, pickupQuadModel: Model
  checkpointModel, flagModel, boxModel, signModel, crossbowmodel: Model
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

addResourceProc:
  floorModel = loadModel("floor.dae")
  wallModel = loadModel("wall.dae")
  pedestalModel = loadModel("pickup_platform.dae")
  pickupQuadModel = loadModel("pickup_quad.dae")
  flagModel = loadModel("flag.dae")
  boxModel = loadModel("box.dae")
  signModel = loadModel("sign.dae")
  crossbowmodel = loadModel("crossbow.dae")
  checkpointModel = loadModel("checkpoint.dae")
  quadModel = makeQuad(1, 1)
  progressShader = loadShader(ShaderPath"texvert.glsl", ShaderPath"animtextfrag.glsl")
  progressTex = genTexture()
  readImage("assets/progress.png").copyto progressTex

type
  TileKind* = enum
    empty
    wall # Insert before wall for non rendered tiles
    checkpoint
    floor
    pickup
    box
  RenderedTile* = TileKind.wall..TileKind.high

  StackedObjectKind* = enum
    none = "None"
    turret = "Turret"
    box = "Box"

  StackedObject* = object
    startPos: Vec3
    toPos: Vec3
    moveTime: float32
    case kind*: StackedObjectKind
    of turret:
      direction*: Direction
      toggledOn*: bool
      movesToNextShot: int
      projectileKind*: ProjectileKind
    of box:
      discard
    of none: discard

  ProjectileKind* = enum
    hitScan, dynamicProjectile


  Tile* = object
    stacked*: Option[StackedObject]
    direction*: Direction
    steppedOn*: bool
    case kind*: TileKind
    of pickup:
      pickupKind*: PickupType
      active*: bool
    of box:
      progress*: float32
    else: discard


const # Gamelogic constants
  FloorDrawn* = {wall, floor, pickup}
  Walkable* = {TileKind.floor, pickup, box}
  AlwaysWalkable* = {TileKind.floor, pickup, checkpoint}

proc completed*(t: Tile): bool =
  case t.kind:
  of checkpoint:
    t.steppedOn
  else:
    true


proc hasStacked*(tile: Tile): bool = tile.stacked.isSome()

proc isWalkable*(tile: Tile): bool =
  if tile.hasStacked():
    (tile.stacked.get.moveTime >= MoveTime)
  else:
    (tile.kind in AlwaysWalkable) or
    (tile.kind == Tilekind.box and not tile.steppedOn and tile.progress >= FallTime)

proc canStackOn*(tile: Tile): bool =
  not tile.hasStacked() and tile.isWalkable

proc stackBox*(tile: var Tile, pos: Vec3) = tile.stacked =
  some(StackedObject(kind: box, startPos: pos + vec3(0, 10, 0), toPos: pos))

proc giveStackedObject*(tile: var Tile, stackedObj: Option[StackedObject], fromPos, toPos: Vec3) =
  tile.stacked = stackedObj
  if tile.hasStacked():
    tile.stacked.get.moveTime = 0
    tile.stacked.get.startPos = fromPos
    tile.stacked.get.toPos = toPos

proc clearStack*(frm: var Tile) = frm.stacked = none(StackedObject)

proc updateBox*(boxTile: var Tile, dt: float32) =
  assert boxTile.kind == box
  if boxTile.progress < FallTime:
    boxTile.progress += dt
  elif not boxTile.steppedOn:
    boxTile.progress = FallTime
  else:
    boxTile.progress += dt
  boxTile.progress = clamp(boxTile.progress, 0, FallTime)

proc calcYPos*(tile: Tile): float32 =
  ## Calculates drop pos for boxes
  assert tile.kind == box
  if tile.steppedOn:
    mix(0f, SinkHeight, easingsOutBounce(tile.progress / FallTime))
  else:
    mix(StartHeight, 0, easingsOutBounce(tile.progress / FallTime))

proc update*(tile: var Tile, projectiles: var Projectiles, dt: float32, playerMoved: bool) =
  case tile.kind
  of box:
    tile.updateBox(dt)
  else: discard

  if tile.hasStacked():
    tile.stacked.get.moveTime += dt
    let stacked {.byaddr.} = tile.stacked.get
    case tile.stacked.get.kind
    of turret:
      if playerMoved:
        dec stacked.movesToNextShot
        if stacked.movesToNextShot <= 0:
          stacked.movesToNextShot = MovesBetweenShots
          projectiles.spawnProjectile(stacked.toPos + vec3(0, 0.5, 0), stacked.direction)
    else: discard

proc renderBlock*(tile: Tile, cam: Camera, shader, transparentShader: Shader, pos: Vec3, drawAtPos = false)

proc renderStack*(tile: Tile, cam: Camera, shader: Shader, pos: Vec3) =
  if tile.hasStacked():
    let
      stacked = tile.stacked.get
      pos = lerp(stacked.startPos, stacked.toPos, clamp(easingsOutBounce(stacked.moveTime / MoveTime), 0f, 1f))
    case tile.stacked.get.kind
    of box:
      renderBlock(Tile(kind: box), cam, shader, shader, pos, true)
    of turret:
      let modelMatrix = mat4() * translate(pos) * rotateY stacked.direction.asRot
      shader.setUniform("mvp", cam.orthoView * modelMatrix)
      shader.setUniform("m", modelMatrix)
      render(crossbowmodel)

      let
        progress = clamp(float32 (stacked.movesToNextShot - 1) / MovesBetweenShots, 0f..1f)
        pos = pos + vec3(0, 1, 0)
        targetUp = cam.up
        targetRot = fromTwoVectors(vec3(0, 0, 1), cam.forward)
        upRot = fromTwoVectors(mat4(targetRot) * vec3(0, 1, 0), targetUp)
        mat = mat4() * translate(pos) * (mat4(upRot) * mat4(targetRot))
      progressShader.setUniform("mvp", cam.orthoView * mat)
      progressShader.setUniform("tex", progressTex)
      progressShader.setUniform("progress", progress)
      with progressShader:
        render(quadModel)



      ##renderBlock(Tile(kind: shooter), cam)
    of none:
      discard

proc updateTileModel*(tile: Tile, pos: Vec3, instance: var RenderInstance) =
  case tile.kind
  of wall:
    instance.buffer[RenderedModel.walls].push mat4() * translate(pos + vec3(0, 1, 0))
  of pickup:
    instance.buffer[RenderedModel.pickups].push mat4() * translate(pos + vec3(0, 1, 0))
  of box:
    let
      isWalkable = tile.isWalkable
      blockInstance = BlockInstanceData(walkable: int32 isWalkable, matrix: mat4() * translate(vec3(pos.x, tile.calcYPos, pos.z)))
    instance.buffer[RenderedModel.blocks].push blockInstance
  else:
    discard

  if tile.hasStacked:
    let
      stacked = tile.stacked.unsafeget
      pos = lerp(stacked.startPos, stacked.toPos, clamp(easingsOutBounce(stacked.moveTime / MoveTime), 0f, 1f))
    case stacked.kind
    of turret:
      let modelMatrix = mat4() * translate(pos) * rotateY stacked.direction.asRot
      instance.buffer[RenderedModel.crossbows].push modelMatrix
    of box:
      let modelMatrix = mat4() * translate(pos)
      instance.buffer[RenderedModel.blocks].push modelMatrix
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
      transparentShader.setUniform("tex", getPickupTexture(tile.pickupKind))
      transparentShader.setUniform("mvp", cam.orthoView * (mat4() * translate(pos + vec3(0, 1.1, 0))))
      render(pickupQuadModel)
    with shader:
      let modelMatrix = mat4() * translate(pos + vec3(0, 1, 0))
      shader.setUniform("m", modelMatrix)
      shader.setUniform("mvp", cam.orthoView * modelMatrix)
      render(pedestalModel)
  of box:
      var pos = pos
      if not drawAtPos:
        pos.y = tile.calcYPos()
      with shader:
        let modelMatrix = mat4() * translate(pos)
        shader.setUniform("m", modelMatrix)
        shader.setUniform("mvp", cam.orthoView * modelMatrix)
        shader.setUniform("isWalkable", (tile.isWalkable and not tile.steppedOn).ord)
        render(boxModel)

  of checkpoint:
    with shader:
      let modelMatrix = mat4() * translate(pos)
      shader.setUniform("isWalkable", tile.steppedOn.ord) # Stupid name uniform now
      shader.setUniform("mvp", cam.orthoView * modelMatrix)
      shader.setUniform("m", modelMatrix)
      render(checkpointModel)
  else: discard
