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
    crossbows
    checkpoints

  BlockInstanceData* = object
    state*: int32
    matrix* {.align: 16.} : Mat4

  InstanceBase* = ref object of RootObj

  Instance*[T] = ref object of InstanceBase
    model*: InstancedModel[T]

  RenderInstance* = object
    buffer*: array[RenderedModel, InstanceBase]
    shaders*: array[RenderedModel, Shader]

method render*(base: InstanceBase) {.base.} = discard
method clear*(base: InstanceBase) {.base.} = discard
method reuploadSsbo*(base: InstanceBase) {.base.} = discard

method clear*[T](inst: Instance[T]) =
  inst.model.clear()

method reuploadSsbo*[T](inst: Instance[T]) =
  if inst.model.drawCount > 0:
    inst.model.reuploadSsbo()

method render*[T](inst: Instance[T]) =
  inst.model.render()

proc push*[T](instance: InstanceBase, val: T) =
  bind push
  Instance[seq[T]](instance).model.push(val)

proc new*[T](_: typedesc[Instance[T]], model: InstancedModel[T]): Instance[T] =
  Instance[T](model: model)



