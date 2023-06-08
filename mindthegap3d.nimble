# Package

version       = "0.1.0"
author        = "Jason"
description   = "A new awesome nimble package"
license       = "GPL-3.0-or-later"
srcDir        = "src"
bin           = @["mindthegap3d"]


# Dependencies

requires "nim >= 1.6.0"
requires "https://github.com/beef331/truss3D >= 0.2.4"
requires "constructor"
requires "https://github.com/disruptek/frosty" # For level editor bridge



task leveleditor, "builds and run elevel editor":
  selfexec("c --out:leveleditor -r ./src/core/leveleditor.nim")
task wleveleditor, "builds and run elevel editor":
  selfexec("c --out:leveleditor -d:mingw -r ./src/core/leveleditor.nim")
