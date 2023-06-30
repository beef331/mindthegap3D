import truss3D, vmath, chroma, pixie, frosty, gooey
import frosty/streams as froststreams
import truss3D/[shaders, textures, gui, audio, instancemodels]
import core/[worlds, resources, cameras, players, directions, tiles, consts, shadowcasters, renderinstances, saves]
import std/[os, sugar, streams, algorithm]

shaderPath = "assets/shaders"
modelPath = "assets/models"

const camDefaultSize = 8f

type MenuState = enum
  noMenu
  inMain
  previewingBuiltinLevels
  previewingUserLevels
  optionsMenu

const previewingLevels = {previewingBuiltinLevels, previewingUserLevels}

proc loadBuiltinLevels*(): seq[string] =
  try:
    for line in lines(campaignLevelPath / "levellayout.dat"):
      if line.len > 0:
        result.add campaignLevelPath / line
  except IoError as e:
    echo "Cannot load built in levels: ", e.msg
  except OsError as e:
    echo "Cannot load built in levels: ", e.msg

let builtinLevels = loadBuiltinLevels()

var
  camera: Camera
  world: World
  mainBuffer, signBuffer, uiBuffer, waterBuffer: FrameBuffer
  waterShader, screenShader: Shader
  waterQuad, screenQuad: Model
  waterTex: Texture
  menuState = inMain
  userLevels: seq[string]
  selectedLevel: int
  playingUserLevel = false
  renderInstance = renderInstances.RenderInstance()
  saveData = loadSaveData()
  finishTransition = -1f
  transitionDir = 0f

proc canPlayLevel: bool =
  menuState != previewingBuiltinLevels or selectedLevel == 0 or saveData.finished(selectedLevel - 1)

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

addResourceProc do():
  camera.pos = vec3(0, 8, 0)
  camera.forward = normalize(vec3(5, 0, 5) - camera.pos)
  camera.pos = camera.pos - camera.forward * 20
  camera.changeSize(camDefaultSize)
  mainBuffer = genFrameBuffer(screenSize(), tfRgba, {FrameBufferKind.Color, Depth})
  uiBuffer = genFrameBuffer(screenSize(), tfRgba, {FrameBufferKind.Color})
  signBuffer = genFrameBuffer(screenSize(), tfR, {FrameBufferKind.Color, Depth})
  waterBuffer = genFrameBuffer(screenSize(), tfRgba, {FrameBufferKind.Color, Depth})
  waterQuad = makeRect(300, 300)
  screenQuad = makeScreenQuad()
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
      menuState = noMenu
  except CatchableError as e:
    echo "Debug level could not be loaded: ", e.msg
    discard tryRemoveFile(lastLevelPath)

proc saveLastPlayed() =
  let myFs = newFileStream(lastLevelPath, fmWrite)
  defer: myFs.close()
  freeze(myFs, world)


proc positionCamera() =
  var worldSize = vec2(float32 world.width, float32 world.height) / 2
  camera.size = max(worldSize.x, worldSize.y).max(6)
  camera.pos = vec3(worldSize.x, 0, worldSize.y) - camera.forward * 20
  camera.calculateMatrix()
  

proc loadSelectedLevel(path: string) =
  let name = path.splitFile.name
  var fs = newFileStream(path)
  defer: fs.close
  world = World(levelName: name)
  unload(world)
  fs.thaw world
  world.state.incl previewing
  load(world)
  positionCamera()

proc nextLevel(dir: int = 1) =
  let
    isBuiltin = menuState == previewingBuiltinLevels
    start = selectedLevel
    len =
      if isBuiltin:
        builtinLevels.len
      else:
        userLevels.len
    newLevel = (start + dir + len) mod len
  if newLevel != start:
    selectedLevel = newLevel
    if menuState == previewingBuiltinLevels:
      loadSelectedLevel(builtinLevels[selectedLevel])
    else:
      loadSelectedLevel(userLevels[selectedLevel])

include core/mainui

var
  mainMenu = makeMenu()
  uiState = MyUiState(scaling: 1)
  renderTarget: UiRenderTarget
  modelData: MeshData[Vec2]
modelData.appendVerts [vec2(0, 0), vec2(0, 1), vec2(1, 1), vec2(1, 0)].items
modelData.append [0u32, 1, 2, 0, 2, 3].items
modelData.appendUv [vec2(0, 1), vec2(0, 0), vec2(1, 0), vec2(1, 1)].items



proc gameInit() =
  fontPath = getAppDir() / "assets/fonts/MarradaRegular-Yj0O.ttf"
  audio.init()
  invokeResourceProcs()

  renderInstance.buffer[floors] = Instance[seq[BlockInstanceData]].new(loadInstancedModel[seq[BlockInstanceData]]("floor.dae", floors.ord))
  renderInstance.shaders[floors] = loadShader(ShaderPath"instblockvert.glsl", ShaderPath"frag.glsl")

  renderInstance.buffer[signs] = Instance[seq[Mat4]].new(loadInstancedModel[seq[Mat4]]("sign.dae", signs.ord))
  renderInstance.shaders[signs] = loadShader(ShaderPath"instvert.glsl", ShaderPath"frag.glsl")

  renderInstance.buffer[pickupIcons] = Instance[seq[BlockInstanceData]].new(loadInstancedModel[seq[BlockInstanceData]]("pickup_quad.dae", signs.ord))
  renderInstance.shaders[pickupIcons] = loadShader(ShaderPath"insttexturedvert.glsl", ShaderPath"instpickupfrag.glsl")

  renderInstance.buffer[walls] = Instance[seq[Mat4]].new(loadInstancedModel[seq[Mat4]]("wall.dae", walls.ord))
  renderInstance.shaders[walls] = renderInstance.shaders[signs]

  renderInstance.buffer[pickups] = Instance[seq[Mat4]].new(loadInstancedModel[seq[Mat4]]("pickup_platform.dae", pickups.ord))
  renderInstance.shaders[pickups] = renderInstance.shaders[signs]

  renderInstance.buffer[blocks] = Instance[seq[BlockInstanceData]].new(loadInstancedModel[seq[BlockInstanceData]]("box.dae", blocks.ord))
  renderInstance.shaders[blocks] = loadShader(ShaderPath"instblockvert.glsl", ShaderPath"frag.glsl")

  renderInstance.buffer[checkpoints] = Instance[seq[BlockInstanceData]].new(loadInstancedModel[seq[BlockInstanceData]]("checkpoint.dae", checkpoints.ord))
  renderInstance.shaders[checkpoints] = renderInstance.shaders[blocks]

  renderInstance.buffer[iceBlocks] = Instance[seq[Mat4]].new(loadInstancedModel[seq[Mat4]]("ice.glb", iceBlocks.ord))
  renderInstance.shaders[iceBlocks] = loadShader(ShaderPath"icevert.glsl", ShaderPath"icefrag.glsl")

  renderInstance.buffer[crossbows] = Instance[seq[Mat4]].new(loadInstancedModel[seq[Mat4]]("crossbow.dae", crossbows.ord))
  renderInstance.shaders[crossbows] = renderInstance.shaders[signs]

  renderTarget.model = uploadInstancedModel[gui.RenderInstance](modelData)
  renderTarget.shader = loadShader(guiVert, guiFrag)

var lastScreenSize: IVec2

proc cameraMovement =
  var
    cameraDragPos {.global.}: Vec3
    cameraStartPos {.global.}: Vec3
    mouseStartPos {.global.}: IVec2
    mouseOffset {.global.} : IVec2
  if world.finished:
    setMouseMode(MouseAbsolute)
    releaseWindow()
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
    waterBuffer.resize(scrSize)

  if previewing notin world.state:
    cameraMovement()
    let scroll = getMouseScroll()
    if scroll != 0:
      if KeycodeLCtrl.isPressed and not middleMb.isPressed:
        camera.changeSize(clamp(camera.size + -scroll.float, 3, 20))

    with signBuffer:
      let
        mousePos = getMousePos()
        colData = 0u8
      glReadPixels(mousePos.x, screenSize().y - mousePos.y, 1, 1, GlRed, GlUnsignedByte, colData.unsafeAddr)
      let selected = world.getSignIndex(colData / 255)
      if selected >= 0:
        world.hoverSign(selected)

    if KeyCodeQ.isDown:
      world.state.excl editing
      world.state.excl playing
      saveLastPlayed()
      menuState = inMain

    if playing in world.state and finishTransition >= LevelCompleteAnimationTime:
      if playingUserLevel:
        saveData.save(userLevels[selectedLevel], 0)
        menuState = previewingUserLevels
      else:
        saveData.save(selectedLevel, 0)
        selectedLevel = min(selectedLevel + 1, builtinLevels.high)
        menuState = previewingBuiltinLevels
        loadSelectedLevel(builtinLevels[selectedLevel])
      world.reload()


  uiState.dt = dt
  uiState.screenSize = vec2 screenSize()
  uiState.inputPos = vec2 getMousePos()
  if leftMb.isDown:
    uiState.input = UiInput(kind: leftClick)
  elif leftMb.isPressed:
    uiState.input = UiInput(kind: leftClick, isHeld: true)
  elif isTextInputActive():
    if inputText() != "":
      uiState.input = UiInput(kind: textInput, str: inputText())
    elif KeyCodeBackspace.isDownRepeating:
      uiState.input = UiInput(kind: textDelete)
    elif KeyCodeReturn.isDownRepeating:
      uiState.input = UiInput(kind: textNewline)
    else:
      reset uiState.input
  else:
    reset uiState.input
  setInputText("")
  uiState.interactedWithCurrentElement = false
  uiState.overAnyUi = false

  let isFinished = world.finished
  world.update(camera, dt, renderInstance, uiState, renderTarget)

  if not isFinished and world.finished:
    finishTransition = 0
    transitionDir = 1

  if finishTransition >= LevelCompleteAnimationTime:
    transitionDir = -1

  finishTransition += transitionDir * dt

  if finishTransition < 0:
    finishTransition = 0
    transitionDir = 0


  if menuState != noMenu:
    mainMenu.interact(uiState)
    mainMenu.layout(vec3(0), uiState)

  audio.update()

proc draw =
  glEnable(GlDepthTest)
  with signBuffer:
    signBuffer.clear()
    world.renderSignBuff(camera)

  with uiBuffer:
    uiBuffer.clear()
    if menuState != noMenu:
      mainMenu.upload(uiState, renderTarget)
    if renderTarget.model.drawCount > 0:
      renderTarget.model.ssboData.sort(proc(a, b: UiRenderObj): int = (if b.matrix[3, 2] - a.matrix[3, 2] <= 0: -1 else: 1))
      renderTarget.model.reuploadSsbo()

    if not uiState.interactedWithCurrentElement and uiState.currentElement != nil:
      uiState.currentElement.flags = {}
      reset uiState.input
      reset uiState.action
      uiState.currentElement = nil
      if isTextInputActive():
        stopTextInput()

    glDisable(GlDepthTest)
    atlas.ssbo.bindBuffer(1)
    with renderTarget.shader:
      setUniform("fontTex", atlas.texture)
      glEnable(GlBlend)
      glBlendFunc(GlOne, GlOneMinusSrcAlpha)
      renderTarget.model.render()
      glDisable(GlBlend)
      renderTarget.model.clear()



  glEnable(GlDepthTest)
  with mainBuffer:
    mainBuffer.clear()
    if menuState == noMenu or previewing in world.state:
      world.render(camera, renderInstance, uiState, mainBuffer)
    renderWaterSplashes(camera)

  with waterBuffer:
    waterBuffer.clear()
    with waterShader:
      let waterMatrix = mat4() * translate(vec3(-150, 0.9, -150))
      waterShader.setUniform("modelMatrix", waterMatrix)
      waterShader.setUniform("worldSize", vec2(world.width.float - 1, world.height.float - 1))
      waterShader.setUniform("depthTex", mainBuffer.depthTexture)
      waterShader.setUniform("colourTex", mainBuffer.colourTexture)
      waterShader.setUniform("waterTex", waterTex)
      watershader.setUniform("time", getTime())
      waterShader.setUniform("mvp", camera.orthoView * waterMatrix)
      render(waterQuad)

  with screenShader:
    screenShader.setUniform("matrix", scale(vec3(2)) * translate(vec3(-0.5, -0.5, 0f)))
    screenShader.setUniform("tex", waterBuffer.colourTexture)
    screenShader.setUniform("uiTex", uiBuffer.colourTexture)
    screenShader.setUniform("playerPos", vec2 camera.screenPosFromWorld(world.player.pos + vec3(0, 1.5, 0)))
    screenShader.setUniform("finishProgress", finishTransition / LevelCompleteAnimationTime)
    screenShader.setUniform("isPlayable", int32(canPlayLevel()))
    render(screenQuad)


initTruss("Mind The Gap", ivec2(1280, 720), gameInit, update, draw)
