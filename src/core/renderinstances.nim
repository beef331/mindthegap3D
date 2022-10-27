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
    pedestals
    crossbows
    checkpoints

  RenderInstance* = object
    buffer*: array[RenderedModel, InstancedModel[seq[Mat4]]]
    shaders*: array[RenderedModel, Shader]
