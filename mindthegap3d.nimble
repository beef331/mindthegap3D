# Package

version       = "0.1.0"
author        = "Jason"
description   = "A new awesome nimble package"
license       = "GPL-3.0-or-later"
srcDir        = "src"
bin           = @["mindthegap3d"]


# Dependencies

requires "nim >= 1.6.0"
requires "https://github.com/beef331/truss3D >= 0.2.23"
requires "constructor"
requires "https://github.com/disruptek/frosty" # For serialisation

