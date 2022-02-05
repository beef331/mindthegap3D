import vmath, flatty, nigui
import std/[sugar, strutils, os, decls]
import worlds, pickups, directions, tiles, editorbridge, signs

const
  Paintable = {Tilekind.floor, wall, pickup, shooter}
  TileSize = 64
  MaxLevelSize = 30

type
  PaintState = enum
    psNone
    psTile
    psRemove
    psSpawn

  EditorWindow = ref object of WindowImpl
    tile: Tile
    sel: int
    world: World
    liveEditing: bool
    inspector: Control
    editor: Control
    name: string
    onSelectionChange: proc(){.closure.}
    onChange: proc(ew: EditorWindow)
    tileImages: array[TileKind, Image]
    pickupImages: array[PickupType, Image]
    spawnSprite: Image
    paintState: PaintState

const assetPath = "assets" / "leveleditor"

proc loadImages(ew: EditorWindow) =
  ew.tileImages[TileKind.floor] = newImage()
  ew.tileImages[TileKind.floor].loadFromFile assetPath / "floor.png"
  ew.spawnSprite = newImage()
  ew.spawnSprite.loadFromFile assetPath / "playerspawn.png"
  const
    pickupPath = [
      single:  assetPath / "single.png",
      closeQuad: assetPath / "closequad.png",
      farQuad: assetPath / "farquad.png",
      lLeft: assetPath / "leftl.png",
      lRight: assetPath / "rightl.png",
      tee: assetPath / "tee.png",
      line: assetPath / "line.png"
    ]
  ew.world.playerSpawn = -1

  for pickup in PickupType:
    ew.pickupImages[pickup] = newImage()
    ew.pickupImages[pickup].loadFromFile(pickupPath[pickup])

proc selected(editor: EditorWindow): int = editor.sel

proc `selected=`(editor: EditorWindow, val: int) =
  editor.sel = val
  if editor.onSelectionChange != nil:
    editor.onSelectionChange()

proc newEditorWindow(): EditorWindow =
  new result
  result.WindowImpl.init()
  result.tile = Tile(kind: TileKind.floor)
  result.world = World.init(10, 10)
  result.sel = -1
  result.onChange = proc(ew: EditorWindow) =
    sendWorld(ew.world)
    ew.editor.hide
    ew.editor.show
  result.loadImages()

proc scaleEditor(window: EditorWindow) =
  window.editor.scrollableWidth = int TileSize * window.world.width
  window.editor.scrollableHeight = int TileSize * window.world.height
  let width = window.world.width * TileSize
  if width < int(window.width.float * 0.7):
    window.editor.width = int width
  else:
    window.editor.width = int(window.width.float * 0.7)

proc worldInspector(window: EditorWindow, container: LayoutContainer) =
  let
    widthField = newTextBox($window.world.width)
    heightField = newTextBox($window.world.height)
  widthField.maxWidth = 50
  heightField.maxWidth = 50
  widthField.onTextChange = proc(textEvent: TextChangeEvent) =
    let
      textBox = TextBox textEvent.control
    var
      text = textBox.text
    if text.len > 0 and text[^1] notin Digits:
      if text.len > 1:
        textbox.text = text[0..^2]
      else:
        textbox.text = ""
    text = textBox.text
    if text.len > 0:
      let newSize = clamp(parseint(text), 1, MaxLevelSize)
      textBox.text = $newSize
      window.world.resize(ivec2(newSize, int window.world.height))
      window.editor.show
      window.selected = -1
      window.scaleEditor()
      window.onChange(window)



  heightField.onTextChange = proc(textEvent: TextChangeEvent) =
    let
      textBox = TextBox textEvent.control
    var
      text = textBox.text
    if text.len > 0 and text[^1] notin Digits:
      if text.len > 1:
        textbox.text = text[0..^2]
      else:
        textbox.text = ""
    text = textBox.text
    if text.len > 0:
      let newSize = clamp(parseint(text), 1, MaxLevelSize)
      textBox.text = $newSize
      window.world.resize(ivec2(int window.world.width, newSize))
      window.editor.show
      window.selected = -1
      window.scaleEditor()
      window.onChange(window)

  container.add newLabel("Width")
  container.add widthField
  container.add newLabel("Height")
  container.add heightField


template newComboBox(iter: untyped, onChangeVal: untyped): ComboBox =
  let
    cbVals = collect:
      for x in iter:
        $x
    res = newComboBox(cbVals)

  res.onChange = proc(event: ComboBoxChangeEvent) =
    let comboBox {.inject.} = event.control.ComboBox
    onChangeVal
  res

proc topBar*(window: EditorWindow, vert: LayoutContainer) =
  let
    horz = newLayoutContainer(LayoutHorizontal)
    paintSelector = newComboBox(Paintable):
      window.tile = Tile(kind: parseEnum[TileKind](comboBox.value))


  paintSelector.minWidth = 100

  let
    playerSpawnButton = newButton("Player Spawn")
    liveEditButton = newButton("Live Edit")
    loadButton = newButton("Load")
    saveButton = newButton("Save")

  saveButton.onClick = proc(clickEvent: ClickEvent) =
    let
      saveFileDialog = newSaveFileDialog()
    saveFileDialog.title = "Save Level as"
    saveFileDialog.defaultName = "Untitled.lvl"
    saveFileDialog.run()
    if saveFileDialog.file.len != 0:
      try:
        ## Save level
      except:
        ## Handle invalid file name

  loadButton.onClick = proc(clickEvent: ClickEvent) =
    let
      openFileDialog = newOpenFileDialog()
    openFileDialog.multiple = false
    openFileDialog.title = "Open Level"
    openFileDialog.run()
    if openFileDialog.files.len != 0 and openFileDialog.files[0].len > 0:
      try:
        ## Open level
      except:
        ## Handle invalid file name


  liveEditButton.onClick = proc(clickEvent: ClickEvent) =
    window.liveEditing = not window.liveEditing
    echo "Is Live editing: ", window.liveEditing

  playerSpawnButton.onClick = proc(clickEvent: ClickEvent) =
    window.paintState = psSpawn

  horz.add paintSelector
  horz.add playerSpawnButton
  horz.add liveEditButton
  horz.add loadButton
  horz.add saveButton
  window.worldInspector(horz)
  vert.add horz

proc makeEditor(window: EditorWindow, container: LayoutContainer) =
  let canv = newControl()
  window.editor = canv
  window.paintState = psNone

  canv.onDraw = proc(drawEvent: DrawEvent) =
    let
      canvas = drawEvent.control.canvas
    canvas.areaColor = rgb(127, 127, 127)
    canvas.fill()
    canvas.lineColor = rgb(255, 0, 0)
    canvas.lineWidth = 5
    canvas.drawRectOutline(-canv.xScrollPos, -canv.yScrollPos, int window.world.width * TileSize, int window.world.height * TileSize)
    canvas.lineColor = rgb(255, 255, 0)
    for i, tile in window.world.tiles.pairs:
      let
        x = int i mod window.world.width * TileSize - canv.xScrollPos
        y = int i div window.world.width * TileSize - canv.yScrollPos
      case tile.kind
      of TileKind.floor:
        canvas.drawImage(window.tileImages[TileKind.floor], x, y)
      of TileKind.pickup:
        canvas.drawImage(window.pickupImages[tile.pickupKind], x, y)
      else: discard

    if window.world.playerSpawn in 0..<window.world.tiles.len:
      let
        x = int window.world.playerSpawn mod window.world.width
        y = int window.world.playerSpawn div window.world.width
      canvas.drawImage(window.spawnSprite, x * TileSize, y * TileSize)

    if window.selected in 0..<window.world.tiles.len:
      let
        selectedX = int (window.selected mod window.world.width) * TileSize - canv.xScrollPos
        selectedY = int (window.selected div window.world.width) * TileSize - canv.yScrollPos
      canvas.drawRectOutline(selectedX, selectedY, TileSize, TileSize)

  canv.onMouseButtonDown = proc(mouseEvent: MouseEvent) =
    let
      x = (mouseEvent.x + canv.xScrollPos) div TileSize
      y = (mouseEvent.y + canv.yScrollPos) div TileSize
      ind = int x mod window.world.width + y * window.world.width
      inWorld = vec3(float x, 0, float y) in window.world

    case mouseEvent.button
    of MouseButtonLeft:
      if inWorld:
        if window.paintState == psSpawn:
          window.world.playerSpawn = ind
          window.paintState = psTile
        else:
          case window.tile.kind
          of pickup:
            window.tile.active = true
          else:
            discard
          window.world.tiles[ind] = window.tile

    of MouseButtonMiddle:
      window.selected =
        if inWorld:
          ind
        else:
          -1
    of MouseButtonRight:
      if inWorld:
        window.world.tiles[ind] = Tile(kind: empty)
    window.onChange(window)


  window.scaleEditor()
  canv.heightMode = HeightMode_Expand
  container.add canv

proc makeInspector(window: EditorWindow, container: LayoutContainer) =
  let canv = newLayoutContainer(LayoutVertical)
  window.inspector = canv
  let
    directionSelector = newComboBox(Direction):
      let win = EditorWindow(comboBox.parentWindow)
      win.world.tiles[win.selected].direction = parseEnum[Direction](comboBox.value)
    pickupSelector = newComboBox(PickupType):
      let win = EditorWindow(comboBox.parentWindow)
      win.world.tiles[win.selected].pickupKind = parseEnum[PickupType](comboBox.value)
      win.onChange(win)
    pickupLabel = newLabel("Pickup:")
    pickupCont = newLayoutContainer(Layout_Horizontal)
    dir = newLayoutContainer(LayoutHorizontal)
    signField = newTextArea("")

  dir.add newLabel("Direction:")
  dir.add directionSelector

  pickupCont.add pickupLabel
  pickupCont.add pickupSelector

  directionSelector.enabled = false
  pickupSelector.enabled = false
  signField.hide()

  signField.onTextChange = proc(textEvent: TextChangeEvent) =
    block addText:
      for sign in window.world.signs.mitems:
        let index = window.world.getPointIndex(sign.pos)
        if index == window.selected:
          sign = Sign.init(sign.pos, signField.text)
          break addText
      if signField.text.len > 0:
        window.world.signs.add Sign.init(window.world.getPos(window.selected) + vec3(0, 1, 0), signField.text)
    window.onChange(window)


  window.onSelectionChange = proc() =
    if window.selected in 0..<window.world.tiles.len:
      var tile {.byaddr.} = window.world.tiles[window.selected]
      case tile.kind
      of pickup:
        directionSelector.enabled = false
        pickupSelector.enabled = true
      else:
        directionSelector.enabled = false
        pickupSelector.enabled = false
      if tile.kind == empty:
        signField.hide()
      else:
        signField.show()
      window.editor.show()
      signField.text = window.world.getSign(window.world.getPos(window.selected)).message
    else:
      directionSelector.enabled = false
      pickupSelector.enabled = false
      signField.hide()

  canv.add dir
  canv.add pickupCont
  canv.add signField
  container.add canv


app.init()

var
  window = newEditorWindow()
  vert = newLayoutContainer(LayoutVertical)
  canvasInspector = newLayoutContainer(LayoutHorizontal)
window.makeEditor(canvasInspector)
window.makeInspector(canvasInspector)

window.onResize = proc(resize: ResizeEvent) = window.scaleEditor()

window.topBar(vert)
vert.add canvasInspector
window.add vert
window.show()
app.run
