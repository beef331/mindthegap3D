import vmath
import std/[sugar, strutils]
import worlds, pickups, directions, tiles
import nigui

const
  Paintable = {Tilekind.floor, wall, pickup, shooter}
  TileSize = 64
  MaxLevelSize = 30

type EditorWindow = ref object of WindowImpl
  tile: Tile
  sel: int
  world: World
  liveEditing: bool
  inspector: Control
  editor: Control
  name: string
  onSelectionChange: proc(){.closure.}


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

proc scaleEditor(window: EditorWindow) =
  window.editor.scrollableWidth = TileSize * window.world.width
  window.editor.scrollableHeight = TileSize * window.world.height
  let width = window.world.width * TileSize
  if width < int(window.width.float * 0.7):
    window.editor.width = width
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
      window.world.resize(ivec2(newSize, window.world.height))
      window.editor.show
      window.selected = -1
      window.scaleEditor()



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
      window.world.resize(ivec2(window.world.width, newSize))
      window.editor.show
      window.selected = -1
      window.scaleEditor()

  container.add newLabel("Width")
  container.add widthField
  container.add newLabel("Height")
  container.add heightField

proc topBar*(window: EditorWindow, vert: LayoutContainer) =
  let
    horz = newLayoutContainer(LayoutHorizontal)
    paintable = collect:
      for x in Paintable:
        $x
    paintSelector = newComboBox(paintable)

  paintSelector.minWidth = 100
  paintSelector.onChange = proc(event: ComboBoxChangeEvent) =
    let comboBox = event.control.ComboBox
    window.tile = Tile(kind: parseEnum[TileKind](comboBox.value))

  let
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
    if not window.liveEditing:
      echo "Live editing"
      #clickEvent.control.Button.enabled = false

  horz.add paintSelector
  horz.add liveEditButton
  horz.add loadButton
  horz.add saveButton
  window.worldInspector(horz)
  vert.add horz

proc makeEditor(window: EditorWindow, container: LayoutContainer) =
  let canv = newControl()
  window.editor = canv
  canv.onDraw = proc(drawEvent: DrawEvent) =
    let
      canvas = drawEvent.control.canvas
    canvas.areaColor = rgb(127, 127, 127)
    canvas.fill()
    canvas.lineColor = rgb(255, 0, 0)
    canvas.lineWidth = 5
    canvas.drawRectOutline(-canv.xScrollPos, -canv.yScrollPos, window.world.width * TileSize, window.world.height * TileSize)
    canvas.lineColor = rgb(255, 255, 0)
    if window.selected in 0..<window.world.tiles.len:
      let
        selectedX = (window.selected mod window.world.width) * TileSize - canv.xScrollPos
        selectedY = (window.selected div window.world.width) * TileSize - canv.yScrollPos
      canvas.drawRectOutline(selectedX, selectedY, TileSize, TileSize)


  canv.onMouseButtonDown = proc(mouseEvent: MouseEvent) =
    let
      x = (mouseEvent.x + canv.xScrollPos) div TileSize
      y = (mouseEvent.y + canv.yScrollPos) div TileSize
      ind = x mod window.world.width + y * window.world.width
    case mouseEvent.button
    of MouseButtonLeft:
      discard
    of MouseButtonMiddle:
      if vec3(float x, 0, float y) in window.world:
        window.selected = ind
      else:
        window.selected = -1
      window.onSelectionChange()
    of MouseButtonRight:
      discard

  window.scaleEditor()
  canv.heightMode = HeightMode_Expand
  container.add canv

proc makeInspector(window: EditorWindow, container: LayoutContainer) =
  let canv = newLayoutContainer(LayoutVertical)
  window.inspector = canv
  let
    direction = collect:
      for x in Direction:
        $x
    directionSelector = newComboBox(direction)

  window.onSelectionChange = proc() =
    if window.selected in 0..< window.world.tiles.len:
      canv.show
      directionSelector.index = window.world.tiles[window.selected].direction.ord
    else:
      canv.hide
  directionSelector.onChange = proc(event: ComboBoxChangeEvent) =
    let
      comboBox = event.control.ComboBox
      win = EditorWindow(event.control.parentWindow)
    win.world.tiles[win.selected].direction = parseEnum[Direction](comboBox.value)
  canv.hide
  let dir = newLayoutContainer(LayoutHorizontal)
  dir.add newLabel("Direction:")
  dir.add directionSelector
  canv.add dir
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
