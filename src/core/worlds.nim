import truss3D, truss3D/[models, textures]
import pixie, opengl, vmath, easings
import resources, cameras, pickups, directions, shadows, signs, enumutils
import std/[sequtils, options, decls]
import constructor/constructor

{.experimental: "overloadableEnums".}

const
  StartHeight = 10f
  FallTime = 1f
  SinkHeight = -1
type
  TileKind* = enum
    empty
    wall # Insert before wall for non rendered tiles
    floor
    pickup
    box
    shooter
  BlockFlag* = enum
    dropped, pushable
  ProjectileKind = enum
    hitScan, dynamicProjectile
  Projectile = object
    pos: Vec3
    timeToMove: float32
    direction: Vec3
  Tile = object
    isWalkable: bool
    boxFlag: set[BlockFlag]
    direction: Direction
    case kind: TileKind
    of pickup:
      pickupKind*: PickupType
      active: bool
    of box:
      progress: float32
      steppedOn: bool
    of shooter:
      toggledOn: bool
      timeToShot: float32
      shotDelay: float32 # Shooters and boxes are the same, but come here to make editing easier
      projectileKind: ProjectileKind
      pool: seq[Projectile]
    else: discard

  RenderedTile = TileKind.wall..TileKind.high
  Block* = object
    flags: set[BlockFlag]
    index: int
    worldPos: Vec3
  WorldState* = enum
    playing, editing, previewing
  World* = object
    width, height: int
    tiles: seq[Tile]
    blocks: seq[Block]
    cursor: Vec3
    signs: seq[Sign]
    playerSpawn: int
    case state*: WorldState
    of editing:
      editingTile: Tile
    else: discard

const
  FloorDrawn = {wall, floor, pickup, shooter}
  Paintable = {Tilekind.floor, wall, pickup, shooter}
  Walkable = {TileKind.floor, pickup, box}

var
  wallModel, floorModel, pedestalModel, pickupQuadModel, flagModel, boxModel, signModel: Model
  levelShader, cursorShader, alphaClipShader, flagShader, boxShader, signBuffShader: Shader

addResourceProc:
  floorModel = loadModel("floor.dae")
  wallModel = loadModel("wall.dae")
  pedestalModel = loadModel("pickup_platform.dae")
  pickupQuadModel = loadModel("pickup_quad.dae")
  flagModel = loadModel("flag.dae")
  boxModel = loadModel("box.dae")
  signModel = loadModel("sign.dae")

  levelShader = loadShader("vert.glsl", "frag.glsl")
  cursorShader = loadShader("vert.glsl", "cursorfrag.glsl")
  alphaClipShader = loadShader("vert.glsl", "alphaclip.glsl")
  flagShader = loadShader("flagvert.glsl", "frag.glsl")
  boxShader = loadShader("boxvert.glsl", "frag.glsl")
  signBuffShader = loadShader("vert.glsl", "signbufffrag.glsl")
  cursorShader.setUniform("opacity", 0.6)
  cursorShader.setUniform("invalidColour", vec4(1, 0, 0, 1))
  boxShader.setUniform("walkColour", vec4(1, 1, 0, 1))
  boxShader.setUniform("notWalkableColour", vec4(0.3, 0.3, 0.3, 1))

proc init*(_: typedesc[World], width, height: int): World =
  result = World(state: editing, width: width, height: height, editingTile: Tile(kind: floor))
  result.tiles = newSeqWith(width * height, Tile(kind: empty))

proc play*(world: var World) =
  world = World(
    width: world.width,
    height: world.height,
    tiles: world.tiles,
    blocks: world.blocks,
    signs: world.signs,
    playerSpawn: world.playerSpawn)


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
    case world.editingTile.kind
    of pickup:
      world.editingTile.active = true
    of shooter:
      world.editingTile.shotDelay = 1
    else: discard

    world.tiles[world.getCursorIndex] = world.editingTile
    world.tiles[world.getCursorIndex].isWalkable = true

proc placeBlock*(world: var World, pos: Vec3, kind: PickupType, dir: Direction): bool =
  block placeBlock:
    for x in kind.positions(dir, pos):
      if not world.posValid(x):
        break placeBlock
    result = true
    for x in kind.positions(dir, pos):
      let index = world.getPointIndex(vec3(x))
      world.tiles[index] = Tile(kind: box, isWalkable: false)

proc placeEmpty*(world: var World) =
  if world.cursor in world:
    world.tiles[world.getCursorIndex] = Tile(kind: empty)

proc nextTile*(world: var World, dir: -1..1) =
  var newKind = world.editingTile.kind.nextWrapped
  while newKind notin Paintable:
    newKind = newKind.nextWrapped
  world.editingTile = Tile(kind: newKind)

proc nextOptional*(world: var World, dir: -1..1) =
  let
    index = world.getCursorIndex
    tile {.byaddr.} = world.tiles[index]
  case tile.kind
  of pickup:
    tile.pickupKind = tile.pickupKind.nextWrapped(dir)
  of shooter:
    tile.projectileKind = tile.projectileKind.nextwrapped(dir)
  else:
    discard

proc renderBlock(tile: RenderedTile, cam: Camera, shader: Shader, pos: Vec3, dir: Direction = up) =
  if tile in FloorDrawn:
    let modelMatrix = mat4() * translate(pos)
    shader.setUniform("mvp", cam.orthoView * modelMatrix)
    shader.setUniform("m", modelMatrix)
    render(floorModel)
  case tile:
  of wall, shooter:
    let modelMatrix = mat4() * translate(pos + vec3(0, 1, 0)) * rotateY dir.asRot
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

proc hoverSign*(world: var World, index: int) =
  world.signs[index].hovered = true

proc getSignColor(index, num: int): float = (index + 1) / num

proc getSignIndex*(world: World, val: float): int = (val * world.signs.len.float).int - 1

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

    with cursorShader:
      if world.editingTile.kind in RenderedTile.low.TileKind .. RenderedTile.high.TileKind:
        let isValid = world.cursorValid(true)
        if not isValid:
          glDisable(GlDepthTest)
        cursorShader.setUniform("valid", isValid.ord)
        renderBlock(world.editingTile.kind.RenderedTile, cam, cursorShader, world.cursor)
        glEnable(GlDepthTest)
  renderSigns(world, cam)

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

proc updateShooter(shtr: var Tile, dt: float32) =
  assert shtr.kind == shooter
  case shtr.projectileKind
  of dynamicProjectile:
    ## Check if time to shoot another projectile
  of hitScan:
    shtr.timeToShot -= dt
    if shtr.timeToShot <= 0:
      shtr.toggledOn = not shtr.toggledOn
      shtr.timeToShot = shtr.shotDelay
      if shtr.toggledOn:
        echo "Shoot"
    ## Toggle ray

proc updateBox(boxTile: var Tile, dt: float32) =
  assert boxTile.kind == box
  if boxTile.progress < FallTime:
    boxTile.progress += dt
  elif not boxTile.steppedOn:
    boxTile.progress = FallTime
    boxTile.isWalkable = true
  else:
    boxTile.progress += dt
  boxTile.progress = clamp(boxTile.progress, 0, FallTime)

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
        x.updateSHooter(dt)
      else:
        discard

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
    if KeyCodeLCtrl.isPressed and rightMb.isPressed:
      let hit = cam.raycast(getMousePos())
      if hit in world:
        let index = world.getPointIndex(hit)
        if world.tiles[index].kind != empty:
          world.editingTile = world.tiles[index]
    elif rightMb.isPressed:
      world.placeEmpty()
  of previewing:
    discard
