import truss3D, truss3D/[models, textures]
import pixie, opengl, vmath, easings
import resources, cameras, pickups, directions, shadows, signs, enumutils, tiles
import std/[sequtils, options, decls]

{.experimental: "overloadableEnums".}

const
  StartHeight = 10f
  FallTime = 1f
  SinkHeight = -1

type
  RenderedTile = TileKind.wall..TileKind.high
  Block* = object
    flags: set[BlockFlag]
    index: int
    worldPos: Vec3
  WorldState* = enum
    playing, previewing
  World* = object
    width, height: int
    tiles: seq[Tile]
    blocks: seq[Block]
    cursor: Vec3
    signs*: seq[Sign]
    playerSpawn: int
    state*: WorldState

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

iterator tileKindCoords(world: World): (Tile, Vec3) =
  for i, tile in world.tiles:
    let
      x = i mod world.width
      z = i div world.width
    yield (tile, vec3(x.float, 0, z.float))

proc contains(world: World, vec: Vec3): bool = vec.x.int in 0..<world.width and vec.z.int in 0..<world.height

proc getPointIndex(world: World, point: Vec3): int =
  if point in world:
    floor(point.x).int + floor(point.z).int * world.width
  else:
    -1

proc posValid(world: World, pos: Vec3): bool =
  if pos in world and world.tiles[world.getPointIndex(pos)].kind == empty:
    result = true

proc placeBlock*(world: var World, pos: Vec3, kind: PickupType, dir: Direction): bool =
  block placeBlock:
    for x in kind.positions(dir, pos):
      if not world.posValid(x):
        break placeBlock
    result = true
    for x in kind.positions(dir, pos):
      let index = world.getPointIndex(vec3(x))
      world.tiles[index] = Tile(kind: box, isWalkable: false)

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
  of TileKind.floor: discard

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
    world.resize(ivec2(newWidth, newHeight))
  let ind = world.getPointIndex(vec3(float pos.x, 0, float pos.y))
  echo newWidth, " ", newHeight
  if ind >= 0:
    world.tiles[ind] = tile


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
  of previewing:
    discard

iterator tiles*(world: World): (int, int, Tile) =
  for i, tile in world.tiles:
    yield (i mod world.width, i div world.width, tile)