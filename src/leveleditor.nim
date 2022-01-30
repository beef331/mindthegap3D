import vmath
import std/sugar
import core/[worlds, pickups, directions, tiles]
import nigui

const Paintable = {Tilekind.floor, wall, pickup, shooter}

type EditorWindow = ref object of WindowImpl
  tile: Tile
  world: World
  liveEditing: bool
  name: string

proc newEditorWindow(): EditorWindow =
  new result
  result.WindowImpl.init()
  result.tile = Tile(kind: TileKind.floor)

proc topBar*(window: EditorWindow) =
  let
    vert = newLayoutContainer(LayoutVertical)
    tileSelect = newLayoutContainer(LayoutHorizontal)
  for x in Paintable:
    let button = newButton($x) # Todo replace with images?
    tileSelect.add button
    button.enabled = window.tile.kind != x
    closureScope:
      button.onClick = proc(event: ClickEvent) =
        let button = Button(event.control)
        window.tile = Tile(kind: x)
        for cntrl in button.parentControl.childControls:
          if cntrl of Button:
            Button(cntrl).enabled = true
        button.enabled = false
  let
    worldLine = newLayoutContainer(LayoutHorizontal)
    textBox = newTextBox("Name")
    liveEditButton = newButton("Live Edit")
    loadButton = newButton("Load")
    saveButton = newButton("Save")


  textbox.onTextChange = proc(textEvent: TextChangeEvent) =
    window.name = textEvent.control.TextBox.text

  liveEditButton.onClick = proc(clickEvent: ClickEvent) =
    if not window.liveEditing:
      echo "Live editing"
      clickEvent.control.Button.enabled = false


  worldLine.add textBox
  worldLine.add liveEditButton
  worldLine.add loadButton
  worldLine.add saveButton
  vert.add tileSelect
  vert.add worldLine
  window.add vert


app.init()

var window = newEditorWindow()
window.topBar()
window.show()
app.run



