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

proc calculatePos(ui: UiElement): IVec2 =
  let scrSize = screenSize()

  if left in ui.anchor:
    result.x = ui.pos.x
  elif right in ui.anchor:
    result.x = scrSize.x - ui.pos.x - ui.size.x
  else:
    result.x = scrSize.x div 2 - ui.size.x div 2

  if top in ui.anchor:
    result.y = ui.pos.y
  elif bottom in ui.anchor:
    result.y = scrSize.y - ui.pos.y - ui.size.y
  else:
    result.y = scrSize.y div 2 - ui.size.y div 2


proc isOver(ui: UiElement, pos = getMousePos()): bool =
  let realUiPos = ui.calculatePos()
  pos.x in realUiPos.x .. realUiPos.x + ui.size.x and pos.y in realUiPos.y .. realUiPos.y + ui.size.y

proc calculateAnchorMatrix(ui: UiElement, size = none(Vec2)): Mat4 =
  let
    scrSize = screenSize()
    scale =
      if size.isNone:
        ui.size.vec2 * 2 / scrSize.vec2
      else:
        size.get * 2 / scrSize.vec2
  var pos = ui.calculatePos().vec2 / scrSize.vec2
  pos.y *= -1
  translate(vec3(pos * 2 + vec2(-1, 1 - scale.y), 0f)) * scale(vec3(scale, 0))

method update*(ui: UiElement, dt: float32, offset = mat4()){.error.}
method draw*(ui: UiElement, offset = mat4()) {.error.}


proc new*(_: typedesc[Button], pos, size: IVec2, text: string, color: Vec4 = vec4(1), anchor = {left, top}): Button =
  result = Button(pos: pos, size: size, color: color, anchor: anchor)

method update*(button: Button, dt: float32, offset = mat4()) =
  if button.isOver():
    if leftMb.isDown and button.onClick != nil:
      button.onClick()

method draw*(button: Button, offset = mat4()) =
  with uiShader:
    uiShader.setUniform("modelMatrix", offset * button.calculateAnchorMatrix())
    uiShader.setUniform("color"):
      if button.isOver():
        button.color * 0.5
      else:
        button.color
    render(uiQuad)

proc new*[T](_: typedesc[ScrollBar[T]], pos, size: IVec2, minMax: Slice[T], color, backgroundColor: Vec4, direction = InteractDirection.horizontal, anchor = {left, top}): ScrollBar[T] =
  result = ScrollBar[T](pos: pos, size: size, minMax: minMax, direction: direction, color: color, backgroundColor: backgroundColor, anchor: anchor)

method update*(scrollbar: ScrollBar, dt: float32, offset = mat4()) =
  if scrollBar.isOver():
    if leftMb.isPressed():
      let pos = scrollBar.calculatePos()
      case scrollbar.direction
      of horizontal:
        scrollbar.percentage = (getMousePos().x - pos.x) / scrollBar.size.x
        scrollBar.val = lerp(scrollBar.minMax.a, scrollBar.minMax.b, scrollbar.percentage)
        echo scrollbar.val
      of vertical:
        assert false, "Unimplemented"


method draw*(scrollBar: ScrollBar, offset = mat4()) =
  with uiShader:

    let isOver = scrollBar.isOver()
    uiShader.setUniform("modelMatrix", offset * scrollBar.calculateAnchorMatrix())
    uiShader.setUniform("color"):
      if isOver:
        scrollBar.backgroundColor / 2
      else:
        scrollBar.backgroundColor
    render(uiQuad)

    let sliderScale = scrollBar.size.vec2 * vec2(clamp(scrollbar.percentage, 0, 1), 1)

    uiShader.setUniform("modelMatrix", offset * scrollBar.calculateAnchorMatrix(some(sliderScale)))
    uiShader.setUniform("color"):
      if isOver:
        scrollBar.color * 2
      else:
        scrollBar.color
    render(uiQuad)


when isMainModule:
  import truss3D
  var
    btns: seq[Button]
    scrollBar: ScrollBar[float32]

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

    scrollBar = ScrollBar[float32].new(ivec2(0, 10), iVec2(500, 100), 0f..4f, vec4(0.6, 0, 0, 1), vec4(0.1, 0.1, 0, 1), anchor = {top})

  proc update(dt: float32) =
    for btn in btns:
      btn.update(dt)
    scrollBar.update(dt)


  proc draw() =
    for btn in btns:
      btn.draw()
    scrollBar.draw()
  initTruss("Test", ivec2(1280, 720), init, update, draw)

