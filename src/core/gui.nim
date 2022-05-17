import vmath, pixie, truss3D
import truss3D/[textures, shaders, inputs, models]


type
  InteractDirection* = enum
    horizontal, vertical

  UiElement = ref object of RootObj
    pos: IVec2
    size: IVec2
    color: Vec4
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


proc isOver(ui: UiElement, pos = getMousePos()): bool =
  pos.x in ui.pos.x .. ui.pos.x + ui.size.x and pos.y in ui.pos.y .. ui.pos.y + ui.size.y

method update*(ui: UiElement, dt: float32){.error.}
method draw*(ui: UiElement) {.error.}


proc new*(_: typedesc[Button], pos, size: IVec2, text: string, color: Vec4): Button =
  result = Button(pos: pos, size: size, color: color)

method update*(button: Button, dt: float32) =
  if button.isOver():
    if leftMb.isDown and button.onClick != nil:
      button.onClick()

method draw*(button: Button) =
  with uiShader:
    let
      scale = button.size.vec2 * 2 / screenSize().vec2
    var pos = button.pos.vec2 / screenSize().vec2
    pos.y *= -1
    let
      viewPortOffset = vec2(-1, 1 - scale.y)
      matrix = translate(vec3(pos * 2 + viewPortOffset, 0f)) * scale(vec3(scale, 0))

    uiShader.setUniform("modelMatrix", matrix)
    uiShader.setUniform("color"):
      if button.isOver():
        button.color * 0.5
      else:
        button.color
    render(uiQuad)

proc new*[T](_: typedesc[ScrollBar[T]], pos, size: IVec2, minMax: Slice[T], color, backgroundColor: Vec4, direction = InteractDirection.horizontal): ScrollBar[T] =
  result = ScrollBar[T](pos: pos, size: size, minMax: minMax, direction: direction, color: color, backgroundColor: backgroundColor)

method update*(scrollbar: ScrollBar, dt: float32) =
  if scrollBar.isOver():
    if leftMb.isPressed():
      case scrollbar.direction
      of horizontal:
        scrollbar.percentage = (getMousePos().x - scrollBar.pos.x) / scrollBar.size.x
        scrollBar.val = lerp(scrollBar.minMax.a, scrollBar.minMax.b, scrollbar.percentage)
        echo scrollbar.val
      of vertical:
        assert false, "Unimplemented"


method draw*(scrollBar: ScrollBar) =
  with uiShader:

    let
      isOver = scrollBar.isOver()
      scale = scrollBar.size.vec2 * 2 / screenSize().vec2
    var pos = scrollBar.pos.vec2 / screenSize().vec2
    pos.y *= -1
    let viewPortOffset = vec2(-1, 1 - scale.y)
    var matrix = translate(vec3(pos * 2 + viewPortOffset, 0f)) * scale(vec3(scale, 0))

    uiShader.setUniform("modelMatrix", matrix)
    uiShader.setUniform("color"):
      if isOver:
        scrollBar.backgroundColor / 2
      else:
        scrollBar.backgroundColor
    render(uiQuad)

    let sliderScale = scrollBar.size.vec2 * 2 * vec2(scrollbar.percentage, 1) / screenSize().vec2
    matrix = translate(vec3(pos * 2 + viewPortOffset, 0f)) * scale(vec3(sliderScale, 0))

    uiShader.setUniform("modelMatrix", matrix)
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
    for x in 0..3:
      let color =
        case x
        of 0:
          vec4(1, 0, 0, 1)
        of 1:
          vec4(0, 1, 0, 1)
        of 2:
          vec4(0, 0, 1, 1)
        else:
          vec4(1, 1, 0, 1)
      btns.add  Button.new(ivec2(10 + 210 * x, 10), ivec2(200, 100), "hello", color)
      btns[^1].onClick = proc() = echo "Hello world"
    scrollBar = ScrollBar[float32].new(ivec2(300, 120), iVec2(500, 100), 0f..4f, vec4(0.6, 0, 0, 1), vec4(0.1, 0.1, 0, 1))

  proc update(dt: float32) =
    for btn in btns:
      btn.update(dt)
    scrollBar.update(dt)


  proc draw() =
    for btn in btns:
      btn.draw()
    scrollBar.draw()
  initTruss("Test", ivec2(1280, 720), init, update, draw)

