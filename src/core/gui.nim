import vmath, pixie, truss3D
import truss3D/[textures, shaders, inputs, models]
import std/[options]


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

const
  vertShader = ShaderFile"""
#version 430

layout(location = 0) in vec3 vertex_position;
layout(location = 2) in vec2 uv;


uniform mat4 modelMatrix;

out vec2 fuv;


void main() {
  gl_Position = modelMatrix* vec4(vertex_position, 1.0);
  fuv = uv;
}
"""
  fragShader = ShaderFile"""
#version 430
out vec4 frag_color;

uniform sampler2D tex;
uniform vec4 color;
in vec2 fuv;

void main() {
  frag_color = color;
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


proc new*(_: typedesc[Button], pos, size: IVec2, text: string, color: Vec4 = vec4(1), anchor = {left, top}): Button =
  result = Button(pos: pos, size: size, color: color, anchor: anchor)

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
    render(uiQuad)

proc new*[T](_: typedesc[ScrollBar[T]], pos, size: IVec2, minMax: Slice[T], color, backgroundColor: Vec4, direction = InteractDirection.horizontal, anchor = {left, top}): ScrollBar[T] =
  result = ScrollBar[T](pos: pos, size: size, minMax: minMax, direction: direction, color: color, backgroundColor: backgroundColor, anchor: anchor)

template emitScrollbarMethods*(t: typedesc) =
  method update*(scrollbar: ScrollBar[float32], dt: float32, offset = ivec2(0)) =
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


  method draw*(scrollBar: ScrollBar[float32], offset = ivec2(0)) =
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
      var totalHeight = 0
      for i, item in layoutGroup.children:
        totalHeight += item.size.y
        if i < layoutGroup.children.high:
          totalHeight += layoutGroup.margin
      result = layoutGroup.calculatePos(offset)
  else:
    result = layoutGroup.calculatePos(offset)

method update*(layoutGroup: LayoutGroup, dt: float32, offset = ivec2(0)) =
  var pos = layoutGroup.calculateStart(offset)
  for x in layoutGroup.children:
    update(x, dt, pos)
    case layoutGroup.layoutDirection
    of horizontal:
      pos.x += x.size.x + layoutGroup.margin
    of vertical:
      pos.y += x.size.y + layoutGroup.margin

method draw*(layoutGroup: LayoutGroup, offset = ivec2(0)) =
  var pos = layoutGroup.calculateStart(offset)
  for x in layoutGroup.children:
    draw(x, pos)
    case layoutGroup.layoutDirection
    of horizontal:
      pos.x += x.size.x + layoutGroup.margin
    of vertical:
      pos.y += x.size.y + layoutGroup.margin

proc add*(layoutGroup: LayoutGroup, ui: UiElement) =
  layoutGroup.children.add ui

proc remove*(layoutGroup: LayoutGroup, ui: UiElement) =
  let ind = layoutGroup.children.find(ui)
  if ind > 0:
    layoutGroup.children.delete(ind)

proc clear*(layoutGroup: LayoutGroup) =
  layoutGroup.children.setLen(0)


when isMainModule:
  import truss3D
  var
    btns: seq[Button]
    horzLayout = LayoutGroup.new(ivec2(0, 10), ivec2(500, 100), {bottom}, margin = 10)
    vertLayout = LayoutGroup.new(ivec2(0, 10), ivec2(500, 300), {top}, margin = 10, layoutDirection = vertical)

  proc init =
    initUi()

    btns.add  Button.new(ivec2(10, 10), ivec2(200, 100), "hello", anchor = {left,top})
    btns[^1].onClick = proc() = echo "Hello world"

    btns.add  Button.new(ivec2(10, 10), ivec2(200, 100), "hello", anchor = {left,bottom})
    btns[^1].onClick = proc() = echo "Hello world"

    btns.add  Button.new(ivec2(10, 10), ivec2(200, 100), "hello", anchor = {right, bottom})
    btns[^1].onClick = proc() = echo "Hello world"

    btns.add  Button.new(ivec2(10, 10), ivec2(200, 100), "hello", anchor = {right, top})
    btns[^1].onClick = proc() = echo "Hello world"

    btns.add  Button.new(ivec2(10, 10), ivec2(200, 100), "hello", anchor = {})
    btns[^1].onClick = proc() = echo "Hello world"

    horzLayout.add Button.new(ivec2(10, 10), ivec2(100, 50), "hello")
    horzLayout.add Button.new(ivec2(10, 10), ivec2(100, 50), "hello")
    horzLayout.add Button.new(ivec2(10, 10), ivec2(100, 50), "hello")


    vertLayout.add ScrollBar[float32].new(ivec2(0, 0), iVec2(500, 50), 0f..4f, vec4(0, 0, 0.6, 1), vec4(0.1, 0.1, 0, 1))
    vertLayout.add ScrollBar[float32].new(ivec2(0, 0), iVec2(500, 50), 0f..4f, vec4(0.6, 0, 0, 1), vec4(0.1, 0.1, 0.3, 1))
    vertLayout.add ScrollBar[float32].new(ivec2(0, 0), iVec2(500, 50), 0f..4f, vec4(0.6, 0, 0.6, 1), vec4(0.1, 0.1, 0.1, 1))


  proc update(dt: float32) =
    for btn in btns:
      btn.update(dt)
    horzLayout.update(dt)
    vertLayout.update(dt)


  proc draw() =
    for btn in btns:
      btn.draw()
    horzLayout.draw()
    vertLayout.draw()
  initTruss("Test", ivec2(1280, 720), init, update, draw)

