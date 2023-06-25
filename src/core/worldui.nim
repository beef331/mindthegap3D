proc makeEditorGui(world: var World): auto =
  const entrySize = vec2(125, 30)

  let world = world.addr

  let saveLabel = TimedLabel(
    color: vec4(1),
    backgroundColor: vec4(0, 0, 0, 0.5),
    pos: vec3(0, 30, 0),
    size: vec2(300, 60),
    anchor: {bottom},
    time: 1)

  let topLeft = VGroup[(
        DropDown[NonEmpty],
        HGroup[(Label, HSlider[int])],
        HGroup[(Label, HSlider[int])],
        HGroup[(Label, TextInput)],
        Button,
        )](
        anchor: {top, left},
        pos: vec3(10, 10, 0),
        size: entrySize,
        margin: 10,
        color: vec4(0),
        backgroundColor: vec4(0, 0, 0, 0.3),
        entries:
        (
          DropDown[NonEmpty](
            size: entrySize,
            active: succ(TileKind.empty),
            color: vec4(0, 0, 0, 0.5),
            hoveredColor: vec4(0, 0, 0, 0.7),
            onChange: proc(kind: NonEmpty) =
              world.paintKind = kind
          ),
          HGroup[(Label, HSlider[int])](
            color: vec4(0),
            entries:(
              Label(text: "Width: ", size: entrySize),
              HSlider[int](
                color: vec4(0.5),
                hoveredColor: vec4(0.3),
                value: world.width,
                watchValue: (proc(): int = int world.width),
                rng: 3..10,
                size: entrySize,
                slideBar: MyUiElement(color: vec4(1)),
                onChange: proc(i: int) =
                  world[].resize(iVec2(i, int world.height))
              )
            )
          ),
          HGroup[(Label, HSlider[int])](
            color: vec4(0),
            entries:(
              Label(text: "Height: ", size: entrySize),
              HSlider[int](
                color: vec4(0.5),
                hoveredColor: vec4(0.3),
                value: world.height,
                watchValue: (proc(): int = int world.height),
                rng: 3..10,
                size: entrySize,
                slideBar: MyUiElement(color: vec4(1)),
                onChange: proc(i: int) =
                  world[].resize(iVec2(int world.width, i))
              )
            )
          ),
          HGroup[(Label, TextInput)](
            color: vec4(0),
            entries:(
              Label(
                size: entrySize,
                text: "World Name:"),
              TextInput(
                color: vec4(0),
                size: entrySize,
                onChange: (proc(s: string) = world[].levelName = s),
                watchValue: (proc(): string = world[].levelName),
              )
            )
          ),
          Button(
            color: vec4(0, 0, 0, 0.5),
            hoveredColor: vec4(0, 0, 0, 0.3),
            size: entrySize, label: Label(text: "Save"),
            clickCb: (proc() =
              try:
                world[].history.setLen(0)
                world[].saveHistoryStep(start)
                world[].reload()

                world[].save()
                saveLabel.show("Successfully Saved the Level.")
              except CatchableError as e:
                saveLabel.show("Could not save Level. Error: " & e.msg)
            ),
          )
        )
      )

  template inspectingTile: Tile = world[].tiles[world[].inspecting]
  proc isInspecting: bool = editing in world.state and world[].inspecting in 0..world[].tiles.high

  let
    movesPerLabel = Label(size: entrySize, text: "Moves Per Shot: ") 
    movesTilLabel = Label(size: entrySize, text: "Moves Until Next Shot: ")
    topRightEntries = (
        HGroup[(Label, DropDown[PickupType])](
          visible: (proc(): bool = isInspecting() and inspectingTile().kind == pickup),
          color: vec4(0),
          entries:(
            Label(size: entrySize, text: "Pickup Type: "),
            DropDown[PickupType](
              size: entrySize,
              color: vec4(0, 0, 0, 0.5),
              hoveredColor: vec4(0, 0, 0, 0.7),
              watchValue: (proc(): PickupType = inspectingTile().pickupKind),
              onChange: proc(kind: PickupType) =
                inspectingTile().pickupKind = kind
            )
          )
        ),
        HGroup[(Label, DropDown[StackedObjectKind])](
          visible: (proc(): bool = isInspecting() and inspectingTile().kind in Walkable),
          color: vec4(0),
          entries:(
            Label(size: entrySize, text: "Stacked Kind:"),
            DropDown[StackedObjectKind](
              size: entrySize,
              color: vec4(0, 0, 0, 0.5),
              hoveredColor: vec4(0, 0, 0, 0.7),
              watchValue: (proc(): StackedObjectKind =
                if isInspecting() and inspectingTile.hasStacked:
                  inspectingTile.stacked.get.kind
                else:
                  none
              ),
              onChange: proc(kind: StackedObjectKind) =
                if kind != none:
                  let pos = world[].getPos(world[].inspecting) + vec3(0, 1, 0)
                  inspectingTile.giveStackedObject(some(StackedObject(kind: kind)), pos, pos)
                else:
                  inspectingTile.clearStack()
            )
          )
        ),
        HGroup[(Label, DropDown[Direction])](
          visible: (proc(): bool = isInspecting() and inspectingTile().hasStacked and inspectingTile.stacked.get.kind == turret),
          color: vec4(0),
          entries:(
            Label(size: entrySize, text: "Stacked Direction:"),
            DropDown[Direction](
              size: entrySize,
              color: vec4(0, 0, 0, 0.5),
              hoveredColor: vec4(0, 0, 0, 0.7),
              watchValue: (proc(): Direction = inspectingTile.stacked.get.direction),
              onChange: (proc(dir: Direction) = inspectingTile.stacked.get.direction = dir)
            )
          )
        ),
        HGroup[(Label, TextInput)](
          visible: (proc(): bool =  inspectingTile.isWalkable),
          color: vec4(0),
          backgroundColor: vec4(0),
          entries:(
            Label(size: entrySize, text: "Sign Message: "),
            TextInput(
              size: entrySize * vec2(2, 3),
              color: vec4(0, 0, 0, 0.3),
              watchValue: (proc(): string =
                for sign in world[].activeSign:
                  return sign.message
                ""
              ),
              onChange: (proc(str: string) =
                for sign in world[].activeSign:
                  sign.message = str
                  return

                let pos = ivec2(int32 world[].inspecting mod world[].width, int32 world[].inspecting div world[].width)
                var newSign = Sign.init(vec3(float32 pos.x, 0, float32 pos.y), str)
                newSign.load()
                world[].signs.add newSign
              )

            )
          )
        ),
        HGroup[(Label, HSlider[ShotRange])](
          visible: (proc(): bool = isInspecting() and inspectingTile().hasStacked and inspectingTile.stacked.get.kind == turret),
          color: vec4(0),
          backgroundColor: vec4(0),
          entries: (
            movesPerLabel,
            HSlider[ShotRange](
              size: entrySize,
              rng: ShotRange.low..ShotRange.high,
              color: vec4(0.5),
              hoveredColor: vec4(0.3),
              slideBar: MyUiElement(color: vec4(1)),
              watchValue: (proc(): ShotRange = inspectingTile.stacked.get.turnsPerShot),
              onChange: proc(val: ShotRange) =
                inspectingTile.stacked.get.turnsPerShot = val
                movesPerLabel.text = "Moves Per Shot: " & $val
            )
          )
        ),
        HGroup[(Label, HSlider[ShotRange])](
          visible: (proc(): bool = isInspecting() and inspectingTile().hasStacked and inspectingTile.stacked.get.kind == turret),
          color: vec4(0),
          backgroundColor: vec4(0),
          entries: (
            movesTilLabel,
            HSlider[ShotRange](
              size: entrySize,
              rng: ShotRange.low..ShotRange.high,
              color: vec4(0.5),
              hoveredColor: vec4(0.3),
              slideBar: MyUiElement(color: vec4(1)),
              watchValue: (proc(): ShotRange = inspectingTile.stacked.get.turnsToNextShot),
              onChange: proc(val: ShotRange) =
                inspectingTile.stacked.get.turnsToNextShot = val
                movesTilLabel.text = "Moves Until Next Shot: " & $val
            )
          )
        )

      )

    topRight = VGroup[typeof(topRightEntries)](
      anchor: {top, right},
      pos: vec3(10, 10, 0),
      margin: 10,
      color: vec4(0),
      backgroundColor: vec4(0, 0, 0, 0.3),
      visible: isInspecting,
      entries: topRightEntries
    )


  (
    topLeft,
    topRight,
    saveLabel
  )

