import nico
import vmath
import core/[worlds, pickups, directions, tiles]




const 
  orgName = "jasonbeetham"
  appName = "mindthegapeditor"
  tileSize = 10
  colors = [
    empty: 0,
    wall: 1,
    TileKind.floor: 2,
    pickup: 3,
    TileKind.box: 4,
    shooter: 5
  ]

var
  activeTile = Tile(kind: TileKind.floor)
  inspectedTile = -1
  world: World

proc gameInit() =
  loadFont(0, "./leveleditor/font.png")

proc gameUpdate(dt: float32) =
  if mouseBtn(0):
    let mousePos = ivec2(mouse()[0] div tileSize, mouse()[1] div tileSize)
    echo mousePos
    world.placeTile(activeTile, mousePos)


proc gameDraw() =
  cls()
  for x, y, tile in world.tiles:
    setColor(colors[tile.kind])
    let
      startX = x * tileSize
      startY = y * tileSize
    rectFill(startX, startY, startX + tileSize, startY + tileSize)

nico.init(orgName, appName)
nico.createWindow(appName, 256, 256, 4, false)
nico.run(gameInit, gameUpdate, gameDraw)