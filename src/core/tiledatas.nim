import tiles
import std/[enumerate]
import vmath, directions

type
  TileData* = object
    width*: int64
    height*: int64
    data*: seq[Tile]

proc len*(tileData: TileData): int = tileData.data.len
proc high*(tileData: TileData): int = tileData.data.high

iterator items*(tileData: TileData): Tile =
  for x in tileData.data:
    yield x

iterator mitems*(tileData: var TileData): var Tile =
  for x in tileData.data.mitems:
    yield x

iterator pairs*(tileData: TileData): (int, Tile) =
  for val in tileData.data.pairs:
    yield val

proc contains*(tiles: TileData, vec: Vec3): bool =
  floor(vec.x).int in 0..<tiles.width and floor(vec.z).int in 0..<tiles.height


proc getPointIndex*(tiles: TileData, point: Vec3): int =
  if point in tiles:
    int floor(point.x).int + floor(point.z).int * tiles.width
  else:
    -1

proc `[]`*(tileData: TileData, ind: int): Tile = tileData.data[ind]

proc `[]`*(tileData: TileData, ind: Vec3): Tile =
  let index = getPointIndex(tileData, ind)
  assert index in 0..tileData.high
  tileData[index]
  

proc `[]`*(tileData: var TileData, ind: int): var Tile = tileData.data[ind]

proc `[]`*(tileData: var TileData, ind: Vec3): var Tile =
  let index = getPointIndex(tileData, ind)
  assert index in 0..tileData.high
  tileData[index]

proc `[]=`*(tileData: var TileData, ind: int, val: sink Tile) = tileData.data[ind] = val


iterator tileKindCoords*(tiles: TileData): (Tile, Vec3) =
  for i, tile in tiles.pairs:
    let
      x = i mod tiles.width
      z = i div tiles.width
    yield (tile, vec3(x.float, 0, z.float))

iterator tilesInDir*(tiles: TileData, index: int, dir: Direction, isLast: var bool): Tile =
  assert index in 0..tiles.high
  case dir
  of Direction.up:
    isLast = index div tiles.width >= tiles.height - 1
    for index in countUp(index + tiles.width.int, tiles.high, tiles.width):
      yield tiles[index]
      isLast = index div tiles.width >= tiles.height - 1

  of down:
    isLast = index div tiles.width == 0
    for index in countDown(index - tiles.width.int, 0, tiles.width):
      yield tiles[index]
      isLast = index div tiles.width == 0

  of left:
    isLast = index mod tiles.width >= tiles.width - 1
    for index in countUp(index, index + (tiles.width - index mod tiles.width)):
      yield tiles[index]
      isLast = index mod tiles.width >= tiles.width - 1

  of right:
    isLast = index mod tiles.width == 0
    for index in countDown(index, index - index mod tiles.width):
      yield tiles[index]
      isLast = index mod tiles.width == 0

iterator tilesInDir*(tiles: var TileData, start: int, dir: Direction): (int, int) =
  ## Yields present and next index
  assert start in 0..<tiles.len
  case dir
  of Direction.up:
    for index in countUp(start, tiles.high, tiles.width):
      yield (index, index + tiles.width.int)

  of down:
    for index in countDown(start, 0, tiles.width):
      yield (index, index - tiles.width.int)

  of left:
    for i, _ in enumerate countUp(int start mod tiles.width, tiles.width - 1):
      yield (start + i, start + i + 1)

  of right:
    for i, _ in enumerate countDown(int start mod tiles.width, 0):
      yield (start - i, start - i - 1) 
