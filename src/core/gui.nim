import vmath, pixie, truss3D
import truss3D/[textures, shaders, inputs, models]
import std/[options, sequtils, sugar]


type
  InteractDirection* = enum
    horizontal, vertical
  AnchorDirection* = enum
    left, right, top, bottom
  UiElement = ref object of RootObj
    pos: IVec2
    size: IVec2
    color: Vec4
    anchor: set[AnchorDirection]
  Button* = ref object of UiElement
    textureId: Texture
    onClick: proc(){.closure.}
  Scrollable* = concept s, type S
    lerp(s, s, 0f) is S
  ScrollBar*[T: Scrollable] = ref object of UiElement
    direction: InteractDirection
    val: T
    minMax: Slice[T]
    percentage: float32
    backgroundColor: Vec4
  LayoutGroup* = ref object of UiElement
    layoutDirection: InteractDirection
    children: seq[UiElement]
    margin: int
    centre: bool

  DropDown*[T] = ref object of UiElement
    values: seq[T]
    dropDownButtons: LayoutGroup
    opened: bool
    selected: int
    button: Button

const
  vertShader = ShaderFile"""
#version 430

layout(location = 0) in vec3 vertex_position;
layout(location = 2) in vec2 uv;


uniform mat4 modelMatrix;

out vec2 fuv;


void main() {
  gl_Position = modelMatrix * vec4(vertex_position, 1.0);
  fuv = uv;
}
"""
  fragShader = ShaderFile"""
#version 430
out vec4 frag_color;

uniform sampler2D tex;
uniform int hasTex;
uniform vec4 color;
in vec2 fuv;

void main() {
  frag_color = color;
  if(hasTex > 0){
    frag_color *= texture(tex, fuv);
  }
  if(frag_color.a < 0.01){
    discard;
  }
}
"""


var
  uiShader: Shader
  uiQuad: Model

proc initUI*() =
  uiShader = loadShader(vertShader, fragShader)
  var meshData: MeshData[Vec2]
  meshData.appendVerts([vec2(0, 0), vec2(0, 1), vec2(1, 1), vec2(1, 0)].items)
  meshData.append([0u32, 1, 2, 0, 2, 3].items)
  meshData.appendUv([vec2(0, 1), vec2(0, 0), vec2(1, 0), vec2(1, 1)].items)
  uiQuad = meshData.uploadData()

proc calculatePos(ui: UiElement, offset = ivec2(0)): IVec2 =
  let scrSize = screenSize()

  if left in ui.anchor:
    result.x = ui.pos.x
  elif right in ui.anchor:
    result.x = scrSize.x - ui.pos.x - ui.size.x
  else:
    result.x = scrSize.x div 2 - ui.size.x div 2 + ui.pos.x

  if top in ui.anchor:
    result.y = ui.pos.y
  elif bottom in ui.anchor:
    result.y = scrSize.y - ui.pos.y - ui.size.y
  else:
    result.y = scrSize.y div 2 - ui.size.y div 2 + ui.pos.y
  result += offset


proc isOver(ui: UiElement, pos = getMousePos(), offset = ivec2(0)): bool =
  let realUiPos = ui.calculatePos(offset)
  pos.x in realUiPos.x .. realUiPos.x + ui.size.x and pos.y in realUiPos.y .. realUiPos.y + ui.size.y

proc calculateAnchorMatrix(ui: UiElement, size = none(Vec2), offset = ivec2(0)): Mat4 =
  let
    scrSize = screenSize()
    scale =
      if size.isNone:
        ui.size.vec2 * 2 / scrSize.vec2
      else:
        size.get * 2 / scrSize.vec2
  var pos = ui.calculatePos(offset).vec2 / scrSize.vec2
  pos.y *= -1
  translate(vec3(pos * 2 + vec2(-1, 1 - scale.y), 0f)) * scale(vec3(scale, 0))

method update*(ui: UiElement, dt: float32, offset = ivec2(0)) {.base.} = discard
method draw*(ui: UiElement, offset = ivec2(0)) {.base.} = discard


proc renderTextTo(tex: Texture, size: IVec2, message: string) =
  let
    font = readFont("assets/fonts/MarradaRegular-Yj0O.ttf")
    image = newImage(size.x, size.y)
  font.size = 30
  font.paint = rgb(255, 255, 255)
  image.fillText(font, message, bounds = size.vec2, hAlign = CenterAlign, vAlign = MiddleAlign)
  image.copyTo(tex)


proc new*(_: typedesc[Button], pos, size: IVec2, text: string, color: Vec4 = vec4(1), anchor = {left, top}): Button =
  result = Button(pos: pos, size: size, color: color, anchor: anchor)
  if text.len > 0:
    result.textureId = genTexture()
    result.textureId.renderTextTo(size, text)

proc new*(_: typedesc[Button], pos, size: IVec2, image: Image, anchor = {left, top}): Button =
  result = Button(pos: pos, size: size, color: color, anchor: anchor, textureId: genTexture())
  image.copyTo(result.textureId)

method update*(button: Button, dt: float32, offset = ivec2(0)) =
  if button.isOver(offset = offset):
    if leftMb.isDown and button.onClick != nil:
      button.onClick()

method draw*(button: Button, offset = ivec2(0)) =
  with uiShader:
    uiShader.setUniform("modelMatrix", button.calculateAnchorMatrix(offset = offset))
    uiShader.setUniform("color"):
      if button.isOver(offset = offset):
        button.color * 0.5
      else:
        button.color
    uishader.setUniform("tex", button.textureId)
    uishader.setUniform("hasTex", button.textureId.int)
    render(uiQuad)
    uishader.setUniform("hasTex", 0)


proc new*[T](_: typedesc[ScrollBar[T]], pos, size: IVec2, minMax: Slice[T], color, backgroundColor: Vec4, direction = InteractDirection.horizontal, anchor = {left, top}): ScrollBar[T] =
  result = ScrollBar[T](pos: pos, size: size, minMax: minMax, direction: direction, color: color, backgroundColor: backgroundColor, anchor: anchor)

template emitScrollbarMethods*(t: typedesc) =
  method update*(scrollbar: ScrollBar[t], dt: float32, offset = ivec2(0)) =
    if scrollBar.isOver(offset = offset):
      if leftMb.isPressed():
        let pos = scrollBar.calculatePos(offset)
        case scrollbar.direction
        of horizontal:
          scrollbar.percentage = (getMousePos().x - pos.x) / scrollBar.size.x
          scrollBar.val = lerp(scrollBar.minMax.a, scrollBar.minMax.b, scrollbar.percentage)
          echo scrollbar.val
        of vertical:
          assert false, "Unimplemented"


  method draw*(scrollBar: ScrollBar[t], offset = ivec2(0)) =
    with uiShader:
      let isOver = scrollBar.isOver(offset = offset)
      uiShader.setUniform("modelMatrix", scrollBar.calculateAnchorMatrix(offset = offset))
      uiShader.setUniform("color"):
        if isOver:
          scrollBar.backgroundColor / 2
        else:
          scrollBar.backgroundColor
      render(uiQuad)

      let sliderScale = scrollBar.size.vec2 * vec2(clamp(scrollbar.percentage, 0, 1), 1)

      uiShader.setUniform("modelMatrix", scrollBar.calculateAnchorMatrix(some(sliderScale), offset))
      uiShader.setUniform("color"):
        if isOver:
          scrollBar.color * 2
        else:
          scrollBar.color
      render(uiQuad)

emitScrollbarMethods(float32)

proc new(_: typedesc[LayoutGroup], pos, size: IVec2, anchor = {top, left}, margin = 10, layoutDirection = InteractDirection.horizontal, centre = true): LayoutGroup =
  LayoutGroup(pos: pos, size: size, anchor: anchor, margin: margin, layoutDirection: layoutDirection, centre: centre)

proc calculateStart(layoutGroup: LayoutGroup, offset = ivec2(0)): IVec2 =
  if layoutGroup.centre:
    case layoutGroup.layoutDirection
    of horizontal:
      var totalWidth = 0
      for i, item in layoutGroup.children:
        totalWidth += item.size.x + layoutGroup.margin
      result = ivec2((layoutGroup.size.x - totalWidth) div 2, 0) + layoutGroup.calculatePos(offset)
    of vertical:
      result =  layoutGroup.calculatePos(offset) # Assume top left?
  else:
    result = layoutGroup.calculatePos(offset)


iterator offsetElement(layoutGroup: LayoutGroup, offset: IVec2): (IVec2, UiElement) =
  ## Iterates over `layoutGroup`s children yielding offset and element
  var pos = layoutGroup.calculateStart(offset)
  for item in layoutGroup.children:
    case layoutGroup.layoutDirection
    of horizontal:
      yield (pos, item)
      pos.x += item.size.x + layoutGroup.margin

    of vertical:
      let renderPos = ivec2(pos.x + (layoutGroup.size.x - item.size.x) div 2, pos.y)
      yield (renderPos, item)
      pos.y += item.size.y + layoutGroup.margin



method update*(layoutGroup: LayoutGroup, dt: float32, offset = ivec2(0)) =
  for pos, item in layoutGroup.offsetElement(offset):
    update(item, dt, pos)


method draw*(layoutGroup: LayoutGroup, offset = ivec2(0)) =
  for pos, item in layoutGroup.offsetElement(offset):
    draw(item, pos)

proc add*(layoutGroup: LayoutGroup, ui: UiElement) =
  ui.anchor = {top, left} # Layout groups require top left anchored elements
  layoutGroup.children.add ui

proc remove*(layoutGroup: LayoutGroup, ui: UiElement) =
  let ind = layoutGroup.children.find(ui)
  if ind > 0:
    layoutGroup.children.delete(ind)

proc clear*(layoutGroup: LayoutGroup) =
  layoutGroup.children.setLen(0)


proc new*[T](_: typedesc[DropDown[T]], pos, size: IVec2, values: openarray[(string, T)], anchor = {top, left}): DropDown[T] =
  result = DropDown[T](pos: pos, size: size, anchor: anchor)
  result.dropDownButtons = LayoutGroup.new(pos, size, margin = 0, layoutDirection = vertical, anchor = anchor)
  let res = result[].addr
  for i, iterVal in values:
    let
      (name, value) = iterVal
      color =
        if i > 0:
          vec4(0.5, 0.5, 0.5, 1)
        else:
          vec4(1)
    result.dropDownButtons.add Button.new(ivec2(0), size, name, color = color)
    capture(name, value, i):
      Button(res[].dropDownButtons.children[^1]).onClick = proc() =
        res[].opened = false
        res[].button.textureid.renderTextTo(size, name)
        res[].selected = i
        for ind, child in res[].dropDownButtons.children:
          if ind == i:
            child.color = vec4(1) # TODO: Dont hard code these
          else:
            child.color = vec4(0.5, 0.5, 0.5, 1)

  result.button = Button.new(pos, size, values[0][0], anchor = anchor)
  result.button.onClick = proc() =
    res[].opened = not res[].opened

proc new*[T](_: typedesc[DropDown[T]], pos, size: IVec2, values: openarray[T], anchor = {top, left}): DropDown[T] =
  var vals = newSeqOfCap[(string, T)](values.len)
  for x in values:
    vals.add ($x, x)
  DropDown[T].new(pos, size, vals, anchor)

type MyEnum = enum
  SomeValue
  SomeOtherValue
  SomeOthererValue
  SomeOthrerererValue

method update*(dropDown: DropDown[MyEnum], dt: float32, offset = ivec2(0)) =
  if dropDown.opened:
    dropdown.dropDownButtons.update(dt, offset)
    if leftMb.isDown():
      dropDown.opened = false
  else:
    dropDown.button.update(dt, offset)



method draw*(dropDown: DropDown[MyEnum], offset = ivec2(0)) =
  if dropdown.opened:
    dropdown.dropDownButtons.draw(offset)
  else:
    dropdown.button.draw(offset)


when isMainModule:
  import truss3D
  var
    btns: seq[Button]
    horzLayout = LayoutGroup.new(ivec2(0, 10), ivec2(500, 100), {bottom}, margin = 10)
    vertLayout = LayoutGroup.new(ivec2(0, 10), ivec2(500, 300), {top}, margin = 10, layoutDirection = vertical)
    myDropDown: Dropdown[MyEnum]
  proc init =
    initUi()

    btns.add  Button.new(ivec2(10, 10), ivec2(200, 100), "Hmmm", color = vec4(0.5), anchor = {left,top})
    btns[^1].onClick = proc() = echo "Hello world"

    btns.add  Button.new(ivec2(10, 10), ivec2(200, 100), "Is this text?!", color = vec4(0.5), anchor = {left,bottom})
    btns[^1].onClick = proc() = echo "Hello world"

    btns.add  Button.new(ivec2(10, 10), ivec2(200, 100), "So much memory being wasted", color = vec4(0.5), anchor = {right, bottom})
    btns[^1].onClick = proc() = echo "Hello world"

    btns.add  Button.new(ivec2(10, 10), ivec2(200, 100), "All the textures", color = vec4(0.5), anchor = {right, top})
    btns[^1].onClick = proc() = echo "Hello world"

    btns.add  Button.new(ivec2(10, 10), ivec2(200, 100), "This doesnt even fit", color = vec4(0.5), anchor = {})
    btns[^1].onClick = proc() = echo "Hello world"

    horzLayout.add Button.new(ivec2(10, 10), ivec2(100, 50), "Red", color = vec4(1, 0, 0, 1))
    horzLayout.add Button.new(ivec2(10, 10), ivec2(100, 50), "Green", color = vec4(0, 1, 0 , 1))
    horzLayout.add Button.new(ivec2(10, 10), ivec2(100, 50), "Blue", color = vec4(0, 0, 1, 1))


    vertLayout.add ScrollBar[float32].new(ivec2(0, 0), iVec2(100, 20), 0f..4f, vec4(0, 0, 0.6, 1), vec4(0.1, 0.1, 0, 1))
    vertLayout.add ScrollBar[float32].new(ivec2(0, 0), iVec2(400, 20), 0f..4f, vec4(0.6, 0, 0, 1), vec4(0.1, 0.1, 0.3, 1))
    vertLayout.add ScrollBar[float32].new(ivec2(0, 0), iVec2(300, 20), 0f..4f, vec4(0.6, 0, 0.6, 1), vec4(0.1, 0.1, 0.1, 1))
    myDropDown = Dropdown[MyEnum].new(ivec2(0, 100), ivec2(200, 30), MyEnum.toSeq, anchor = {})

  proc update(dt: float32) =
    for btn in btns:
      btn.update(dt)
    horzLayout.update(dt)
    vertLayout.update(dt)
    myDropDown.update(dt)


  proc draw() =
    for btn in btns:
      btn.draw()
    horzLayout.draw()
    vertLayout.draw()
    myDropDown.draw()

  initTruss("Test", ivec2(1280, 720), init, update, draw)

