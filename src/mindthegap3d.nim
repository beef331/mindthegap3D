import truss3D, vmath, chroma, pixie, frosty
import frosty/streams as froststreams
import truss3D/[shaders, textures, gui, audio]
import core/[worlds, resources, cameras, players, directions, tiles]
import std/[os, sugar, streams]

shaderPath = "assets/shaders"
modelPath = "assets/models"

const camDefaultSize = 8f

type MenuState = enum
  noMenu
  inMain
  previewingLevels
  optionsMenu

var
  camera: Camera
  world: World
  mainBuffer, signBuffer, uiBuffer: FrameBuffer
  depthShader, waterShader, screenShader: Shader
  waterQuad, screenQuad: Model
  waterTex: Texture
  mainMenu: seq[UiElement]
  menuState = inMain
  userLevels: seq[string]
  selectedLevel: int

proc makeRect(w, h: float32): Model =
  var data: MeshData[Vec3]
  data.appendVerts:
    [
      vec3(0, 0, 0), vec3(w, 0, h),
      vec3(0, 0, h),
      vec3(w, 0, 0)
    ].items
  data.append([0u32, 1, 2, 0, 3, 1].items)
  data.appendUv([vec2(0, 0), vec2(1, 1), vec2(0, 1), vec2(1, 0)].items)
  result = data.uploadData()

proc makeScreenQuad(): Model =
  var data: MeshData[Vec2]
  data.appendVerts([vec2(0), vec2(0, 1), vec2(1, 1), vec2(1, 0)].items)
  data.append([0u32, 1, 2, 0, 2, 3].items)
  data.appendUv([vec2(0, 0), vec2(0, 1), vec2(1, 1), vec2(1, 0)].items)
  result = data.uploadData()

addResourceProc do:
  camera.pos = vec3(0, 8, 0)
  camera.forward = normalize(vec3(5, 0, 5) - camera.pos)
  camera.pos = camera.pos - camera.forward * 20
  camera.changeSize(camDefaultSize)
  mainBuffer = genFrameBuffer(screenSize(), tfRgba, hasDepth = true)
  uiBuffer = genFrameBuffer(screenSize(), tfRgba, hasDepth = true)
  signBuffer = genFrameBuffer(screenSize(), tfR, hasDepth = true)
  waterQuad = makeRect(300, 300)
  screenQuad = makeScreenQuad()
  depthShader = loadShader(ShaderPath "vert.glsl", ShaderPath"depthfrag.glsl")
  waterShader = loadShader(ShaderPath"watervert.glsl", ShaderPath"waterfrag.glsl")
  screenShader = loadShader(ShaderPath"screenvert.glsl", ShaderPath"screenfrag.glsl")
  waterTex = genTexture()
  readImage("assets/water.png").copyTo(waterTex)
  mainBuffer.clearColor = color(0, 0, 0, 0)
  uiBuffer.clearColor = color(0, 0, 0, 0)

  world = World.init(10, 10)

let lastLevelPath = getTempDir() / "mtgdebuglevel"

proc loadLastPlayed() =
  try:
    if fileExists(lastLevelPath):
      let myFs = newFileStream(lastLevelPath, fmRead)
      defer: myFs.close()
      thaw(myFs, world)
      world.setupEditorGui()
      menuState = noMenu
  except CatchableError as e:
    echo "Debug level could not be loaded: ", e.msg
    discard tryRemoveFile(lastLevelPath)

proc saveLastPlayed() =
  let myFs = newFileStream(lastLevelPath, fmWrite)
  defer: myFs.close()
  freeze(myFs, world)


proc loadSelectedLevel() =
  var fs = newFileStream(userLevels[selectedLevel])
  defer: fs.close
  world = World()
  unload(world)
  fs.thaw world
  world.state.incl previewing
  load(world)


proc nextUserLevel() =
  let
    start = selectedLevel
    newLevel = (start + 1 + userLevels.len) mod userLevels.len
  if newLevel != start:
    selectedLevel = newLevel
    loadSelectedLevel()

proc prevUserLevel() =
  let
    start = selectedLevel
    newLevel = (start - 1 + userLevels.len) mod userLevels.len
  if newLevel != start:
    selectedLevel = newLevel
    loadSelectedLevel()

proc gameInit() =
  gui.fontPath = "assets/fonts/MarradaRegular-Yj0O.ttf"
  audio.init()
  gui.init()
  invokeResourceProcs()

  var inLevelSelect {.global.} = false

  const
    fontSize = 50
    layoutSize = ivec2(500, fontSize)
    labelSize = ivec2(140, fontSize)


  let nineSliceTex = genTexture()
  const nineSliceSize = 16f32
  readImage("assets/uiframe.png").copyTo nineSliceTex

  mainMenu.add:
    makeUi(Label):
      visibleCond = proc(): bool = menuState != noMenu
      pos = ivec2(0, 30)
      size = ivec2(300, 100)
      text = "Mind the Gap"
      fontSize = 100
      anchor = {top}

  mainMenu.add:
    makeUi(LayoutGroup):
      visibleCond = proc(): bool = menuState == inMain
      pos = ivec2(0, 30)
      size = ivec2(500, 300)
      layoutDirection = vertical
      anchor = {bottom}
      margin = 10
      children:
        makeUi(Button):
          size = labelSize
          text = "Continue"
          backgroundColor = vec4(1)
          nineSliceSize = nineSliceSize
          fontColor = vec4(1)
          backgroundTex = nineSliceTex
          visibleCond = proc(): bool = fileExists(lastLevelPath)
          onClick = proc() = loadLastPlayed()
        makeUi(Button):
          size = labelSize
          text = "Play"
          nineSliceSize = nineSliceSize
          backgroundColor = vec4(1)
          backgroundTex = nineSliceTex
          onClick = proc() =
            userLevels = fetchUserLevelNames()
            loadSelectedLevel()
            menuState = previewingLevels

        makeUi(Button):
          size = labelSize
          text = "Edit"
          nineSliceSize = nineSliceSize
          backgroundColor = vec4(1)
          backgroundTex = nineSliceTex
          onClick = proc() =
            menuState = noMenu
            world = World.init(10, 10)
            world.setupEditorGui()
            world.state = {editing}
        makeUi(Button):
          size = labelSize
          text = "Options"
          nineSliceSize = nineSliceSize
          backgroundColor = vec4(1)
          backgroundTex = nineSliceTex
        makeUi(Button):
          size = labelSize
          text = "Quit"
          nineSliceSize = nineSliceSize
          backgroundColor = vec4(1)
          backgroundTex = nineSliceTex
          onClick = proc() = quitTruss()

  let worldAddr = world.addr

  mainMenu.add:
    makeUi(LayoutGroup):
      pos = ivec2(0, 15)
      size = ivec2(800, 150)
      layoutDirection = vertical
      anchor = {bottom}
      margin = 10
      visibleCond =  proc(): bool = menuState == previewingLevels
      children:
        makeUi(Button):
          size = labelSize
          text = ""
          labelProc = proc(): string =
            "Play " & worldAddr[].levelName
          backgroundColor = vec4(1)
          nineSliceSize = 16f32
          fontColor = vec4(1)
          backgroundTex = nineSliceTex
          onClick = proc() =
            world.state = {playing}
            menuState = noMenu

        makeUi(Button):
          size = labelSize
          text = "Back"
          backgroundColor = vec4(1)
          nineSliceSize = 16f32
          fontColor = vec4(1)
          backgroundTex = nineSliceTex
          onClick = proc() = menuState = inMain


  const
    arrowSize = iVec2(50, 100)
    arrowPos = ivec2(150, 75)

  mainMenu.add:
    makeUi(Button):
      pos = arrowPos
      size = arrowSize
      anchor = {bottom}
      text = ">"
      fontSize = 100f32
      fontColor = vec4(1)
      color = vec4(0)
      backgroundColor = vec4(0)
      backgroundTex = nineSliceTex
      visibleCond = proc(): bool = menuState == previewingLevels
      onClick = nextUserLevel


  mainMenu.add:
    makeUi(Button):
      pos = ivec2(-arrowPos.x, arrowPos.y)
      size = arrowSize
      anchor = {bottom}
      text = "<"
      fontSize = 100f32
      backgroundColor = vec4(0)
      color = vec4(0)
      fontColor = vec4(1)
      visibleCond = proc(): bool = menuState == previewingLevels
      onClick = prevUserLevel

var
  lastScreenSize: IVec2

proc cameraMovement =
  var
    cameraDragPos {.global.}: Vec3
    cameraStartPos {.global.}: Vec3
    mouseStartPos {.global.}: IVec2
    mouseOffset {.global.} : IVec2

  case middleMb.state()
  of pressed:
    cameraDragPos = camera.raycast(getMousePos())
    cameraStartPos = camera.pos
    mouseStartPos = getMousePos()
    mouseOffset = ivec2(0)
    setMouseMode(MouseRelative)
  of held:
    let
      frameOffset = getMouseDelta()
      hitPos = camera.raycast(frameOffset + mouseStartPos)
      offset = hitPos - cameraDragPos
    camera.pos = cameraStartPos + offset
    mouseOffset -= frameOffset
    grabWindow()
  of released:
    setMouseMode(MouseAbsolute)
    releaseWindow()
    moveMouse(mouseStartPos + mouseOffset)
  else:
    discard

proc update(dt: float32) =

  let scrSize = screenSize()
  if lastScreenSize != scrSize:
    lastScreenSize = scrSize
    camera.calculateMatrix()
    mainBuffer.resize(scrSize)
    signBuffer.resize(scrSize)
    uiBuffer.resize(scrSize)

  if previewing notin world.state:
    cameraMovement()
    let scroll = getMouseScroll()
    if scroll != 0:
      if KeycodeLCtrl.isPressed and not middleMb.isPressed:
        camera.changeSize(clamp(camera.size + -scroll.float * dt * 1000, 3, 20))


    with signBuffer:
      let
        mousePos = getMousePos()
        colData = 0u8
      glReadPixels(mousePos.x, screenSize().y - mousePos.y, 1, 1, GlRed, GlUnsignedByte, colData.unsafeAddr)
      let selected = world.getSignIndex(colData / 255)
      if selected >= 0:
        world.hoverSign(selected)

    if KeyCodeQ.isDown:
      saveLastPlayed()
      menuState = inMain
      world = World.init(10, 10)
    world.update(camera, dt)

  if menuState != noMenu:
    for element in mainMenu:
      element.update(dt)

  audio.update()
  guiState = nothing

proc draw =
  glEnable(GlDepthTest)
  with signBuffer:
    signBuffer.clear()
    world.renderSignBuff(camera)

  with uiBuffer:
    uiBuffer.clear()
    for element in mainMenu:
      element.draw()
    if menuState == noMenu:
      world.renderUi()

  glEnable(GlDepthTest)

  with mainBuffer:
    mainBuffer.clear()
    if menuState == noMenu or previewing in world.state:
      world.render(camera)
    with waterShader:
      let waterMatrix = mat4() * translate(vec3(-150, 0.9, -150))
      waterShader.setUniform("modelMatrix", waterMatrix)
      waterShader.setUniform("worldSize", vec2(world.width.float - 1, world.height.float - 1))
      waterShader.setUniform("depthTex", mainBuffer.depthTexture)
      waterShader.setUniform("colourTex", mainBuffer.colourTexture)
      waterShader.setUniform("waterTex", waterTex)
      watershader.setUniform("time", getTime())
      waterShader.setUniform("mvp", camera.orthoView * waterMatrix)
      glEnable GlDepthTest
      glDepthMask false
      render(waterQuad)
      glDepthMask true
    glColorMask false, false, false, false
    render(waterQuad)
    glColorMask true, true, true, true
    renderWaterSplashes(camera)



  with screenShader:
    let scrSize = screenSize()
    screenShader.setUniform("matrix", scale(vec3(2)) * translate(vec3(-0.5, -0.5, 0f)))
    screenShader.setUniform("tex", mainBuffer.colourTexture)
    screenShader.setUniform("uiTex", uiBuffer.colourTexture)
    render(screenQuad)




initTruss("Mind The Gap", ivec2(1280, 720), gameInit, update, draw)
