## This module holds a stateful object passed around for rendering passes, since we do instanced rendering this suffices

import truss3D/[instancemodels, shaders]
import vmath

type
  RenderedModel* = enum
    floors
    walls
    blocks
    signs
    pickups
    pickupIcons
    crossbows
    checkpoints
    iceBlocks
    lazes
    lockedwalls
    keys
    enemies
    portals

  BlockInstanceData* = object
    state*: int32
    matrix* {.align: 16.} : Mat4

  Instance* = InstancedModel[seq[BlockInstanceData]]

  ShaderRef = ref Shader

  RenderInstance* = object
    buffer*: array[RenderedModel, Instance]
    shaders*: array[RenderedModel, ShaderRef]

proc reuploadSsbo*(inst: var Instance) =
  if inst.drawCount > 0:
    instancemodels.reuploadSsbo(inst)

proc render*(inst: var Instance) =
  inst.render()

proc push*(instance: var Instance, val: BlockInstanceData) =
  instancemodels.push(instance, val)

proc push*(instance: var Instance, state: int32, matrix: Mat4) =
  instance.push(BlockInstanceData(state: state, matrix: matrix))

proc push*(instance: var Instance, matrix: Mat4) =
  instance.push(0, matrix)

proc new*(_: typedesc[Instance], path: string): Instance = loadInstancedModel[seq[BlockInstanceData]](path)



