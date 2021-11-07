import resources
import truss3D/textures
import truss3D, pixie
import std/os

type
  PickupType* = enum
    single
    closeQuad
    farQuad
    lLeft
    lRight
    tee

const
  assetPath = "assets/pickupblocks"
  imageNames = [
    single: assetPath / "single.png",
    closeQuad: assetPath / "quad_close.png",
    farQuad: assetPath / "quad_far.png",
    lLeft: assetPath / "l_left.png",
    lRight: assetPath / "l_right.png",
    tee: assetPath / "tee.png"
  ]

var pickupTextures: array[PickupType, Texture]

addResourceProc do:
  for i, _ in pickupTextures.pairs:
    pickupTextures[i] = genTexture()
    let img = readImage(imageNames[i])
    img.copyTo pickupTextures[i]

proc getPickupTexture*(pickupKind: PickupType): Texture = pickupTextures[pickupKind]
