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
  selected: int
  world: World
  liveEditing: bool
  inspector: Control
  editor: Control
  name: string

proc newEditorWindow(): EditorWindow =
  new result
  result.WindowImpl.init()
  result.tile = Tile(kind: TileKind.floor)
  result.world = World.init(10, 10)

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
      window.editor.scrollableHeight = window.world.width * TileSize
      window.editor.scrollableWidth = window.world.width * TileSize



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
      window.editor.scrollableHeight = window.world.width * TileSize
      window.editor.scrollableWidth = window.world.width * TileSize


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
    canvas.drawRectOutline(-canv.xScrollPos, -canv.yScrollPos, window.world.width * TileSize - canv.xScrollPos, window.world.height * TileSize - canv.yScrollPos)
  canv.onMouseButtonDown = proc(mouseEvent: MouseEvent) =
    echo mouseEvent.x, " ", mouseEvent.y
  canv.scrollableHeight = window.world.width * TileSize
  canv.scrollableWidth = window.world.width * TileSize
  canv.heightMode = HeightMode_Expand
  container.add canv




proc makeInspector(window: EditorWindow, container: LayoutContainer) =
  let canv = newLayoutContainer(LayoutVertical)
  window.inspector = canv
  canv.heightMode = HeightModeExpand
  canv.widthMode = WidthModeExpand
  container.add canv


app.init()

var
  window = newEditorWindow()
  vert = newLayoutContainer(LayoutVertical)
  canvasInspector = newLayoutContainer(LayoutHorizontal)
window.makeEditor(canvasInspector)
window.makeInspector(canvasInspector)

window.onResize = proc(resize: ResizeEvent) =
  let win = EditorWindow(resize.window)
  win.editor.width = int(win.width.float * 0.7)

window.topBar(vert)
vert.add canvasInspector
window.add vert
window.show()
app.run
