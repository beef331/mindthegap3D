import truss3D, vmath
import truss3D/[instancemodels, models, shaders]
import resources, directions, cameras
import std/random

type
  FishRenderInstance = object
    velocity: float32
    mat {.align: 16.} : Mat4
  
  FishRender = seq[FishRenderInstance]

  Fish = object
    pos: Vec3
    rot: float32
    velocity: float32
    scale: float32

  FishSpawner = object
    fishes: seq[Fish]
    model: InstancedModel[FishRender]


const fishArea = 10f

var 
  fishSpawner = FishSpawner(fishes: newSeq[Fish](1000))
  shader: Shader

proc relocate(fish: var Fish) =
  let newPos = rand(-fishArea..fishArea)
  fish.pos.y = rand(-0.5f .. 0f)
  fish.velocity = rand(1f..3f)
  fish.scale = rand(0.3f..1f)
  fish.rot = rand(0f..360f)
  case rand(Direction)
  of up:
    fish.pos.x = newPos
    fish.pos.z = fishArea
  of right:
    fish.pos.x = fishArea
    fish.pos.z = newPos
  of down:
    fish.pos.x = newPos
    fish.pos.z = -fishArea
  of left:
    fish.pos.x = -fishArea
    fish.pos.z = newPos

addResourceProc do():
  fishSpawner.model = loadInstancedModel[FishRender]("fish.glb")
  shader = loadShader(ShaderPath"fishvert.glsl", ShaderPath"fishfrag.glsl")
  for fish in fishSpawner.fishes.mitems:
    fish.relocate()

proc update*(dt: float32) =
  fishSpawner.model.clear()
  for fish in fishSpawner.fishes.mitems:
    fish.pos += dt * fish.velocity * (rotateY(fish.rot) * vec3(0, 0, 1))
    if fish.pos.x notin -fishArea..fishArea or fish.pos.z notin -fishArea..fishArea:
      fish.relocate()
    fishSpawner.model.push FishRenderInstance(velocity: fish.velocity, mat: mat4() * translate(fish.pos) * scale(vec3(fish.scale)) * rotateY(fish.rot))

proc render*(cam: Camera) =
  fishSpawner.model.reuploadSsbo()
  with shader:
    shader.setUniform("vp", cam.orthoView)
    shader.setUniform("time", getTime())
    fishSpawner.model.render()


