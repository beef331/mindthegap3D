## Shared constants
import std/[math, os]
const
  MoveTime* = 0.3f
  RotationSpeed* = Tau * 3
  Height* = 2
  StartHeight* = 10f
  FallTime* = 1f
  SinkHeight* = -0.6
  LevelCompleteAnimationTime* = 1f
  PlayerSoundDelay* = 1f
  EntityOffset* = 1.1f


let
  gameDir* = getConfigDir() / "mindthegap"
  savePath* = gameDir / "gamesaves"
  campaignLevelPath* = getAppDir() / "levels"
  userLevelPath* = gameDir / "userlevels"

discard existsOrCreateDir(gameDir)
discard existsOrCreateDir(campaignLevelPath)

