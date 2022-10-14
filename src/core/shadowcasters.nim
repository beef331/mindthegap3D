import vmath, constructor/constructor
import truss3D/shaders


type ShadowCaster* = object
  pos, dir: Vec3
  width, near, far: float32


proc init*(_: typedesc[ShadowCaster], pos, dir: Vec3, width, near, far: float32): ShadowCaster =
  ShadowCaster(pos: pos, dir: dir, width: width, near: near, far: far)

proc setup*(shadowCaster: ShadowCaster) =
  let
    view = lookAt(shadowCaster.pos, shadowCaster.pos + normalize(shadowCaster.dir), vec3(0, 1, 0))
    proj = ortho(-shadowCaster.width, shadowCaster.width, -shadowCaster.width, shadowCaster.width, shadowCaster.near, shadowCaster.far)
  setUniform("lightMatrix", proj * view)
  setUniform("lightDir", shadowCaster.dir)

