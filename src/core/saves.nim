import std/[tables, strscans, sets, strformat]
import consts


type
  SaveEntry* = object
    steps*: int
  SaveData* = object
    campaignLevels: Table[int, SaveEntry]
    userLevels: Table[string, SaveEntry]

proc loadSaveData*(): SaveData {.raises: [ValueError].} =
  try:
    let file = open(savePath)
    for line in file.lines:
      var
        levelName = ""
        levelIndex, steps: int
      if line.scanf("campaign: $i:$i", levelIndex, steps):
        result.campaignLevels[levelIndex] = SaveEntry(steps: steps)
      elif line.scanf("$+:$i", levelName, steps):
        result.userLevels[levelName] = SaveEntry(steps: steps)

  except IoError as e:
    echo "Failed to load save data: ", e.msg
  except OsError as e:
    echo "Failed to load save data: ", e.msg

proc saveData*(data: SaveData) {.raises: [ValueError].} =
  try:
    let file = open(savePath, fmWrite)
    for lvl, entry in data.campaignLevels:
      file.writeLine(fmt"campaign: {lvl}:{entry.steps}")

    for lvl, entry in data.userLevels:
      file.writeLine(fmt"{lvl}:{entry.steps}")
  except IoError as e:
    echo "Failed to save data: ", e.msg
  except OsError as e:
    echo "Failed to save data: ", e.msg

proc save*(saveData: var SaveData, level, steps: int) =
  let newEntry = SaveEntry(steps: max(saveData.campaignLevels.getOrDefault(level).steps, steps))
  saveData.campaignLevels[level] = newEntry
  saveData.saveData()

proc save*(saveData: var SaveData, level: string, steps: int) =
  let newEntry = SaveEntry(steps: max(saveData.userLevels.getOrDefault(level).steps, steps))
  saveData.userLevels[level] = newEntry
  saveData.saveData()

proc finished*(saveData: var SaveData, i: int): bool = i in saveData.campaignLevels

proc highestPlayableLevel*(saveData: SaveData): int =
  for lvl, _ in saveData.campaignLevels:
    result = max(lvl, result)
