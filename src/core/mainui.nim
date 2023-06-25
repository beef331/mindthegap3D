proc makeMenu(): auto =
    (
      VGroup[(Button, Button, Button, Button)](
        margin: 10,
        visible: (proc(): bool = menuState == inMain),
        pos: vec3(0, 20, 0),
        anchor: {bottom},
        color: vec4(0),
        entries:(
          Button(
            color: vec4(0, 0, 0, 0.5),
            hoveredColor: vec4(0, 0, 0, 0.3),
            size: vec2(125, 50),
            label: Label(text: "Play", color: vec4(1)),
            clickCb: (proc() =
              selectedLevel = 0
              playingUserLevel = false
              if builtinLevels.len > 0:
                loadSelectedLevel(builtinLevels[selectedLevel])
                menuState = previewingBuiltinLevels
            )
          ),
          Button(
            color: vec4(0, 0, 0, 0.5),
            hoveredColor: vec4(0, 0, 0, 0.3),
            size: vec2(125, 50),
            label: Label(text: "Edit", color: vec4(1)),
            clickCb: proc() =
              world.setupEditorGui()
              menuState = noMenu
              world = World.init(10, 10)
              world.state = {editing}
          ),
          Button(
            color: vec4(0, 0, 0, 0.5),
            hoveredColor: vec4(0, 0, 0, 0.3),
            size: vec2(125, 50),
            label: Label(text: "Play User Levels", color: vec4(1)),
            clickCb: proc() =
              userLevels = fetchUserLevelNames()
              selectedLevel = 0
              playingUserLevel = true
              if userLevels.len > 0:
                loadSelectedLevel(userLevels[selectedLevel])
                menuState = previewingUserLevels

          ),
          Button(
            color: vec4(0, 0, 0, 0.5),
            hoveredColor: vec4(0, 0, 0, 0.3),
            size: vec2(125, 50),
            label: Label(text: "Quit", color: vec4(1)),
            clickCb: proc() = quit()
          ),
        )
      ),
      VGroup[(HGroup[(Button, Button, Button)], Button, Button)](
        margin: 10,
        pos: vec3(0, 30, 0),
        visible: (proc(): bool = menuState in {previewingUserLevels, previewingBuiltinLevels}),
        color: vec4(0),
        anchor: {bottom},
        alignment: Center,
        entries:(
          HGroup[(Button, Button, Button)](
            color: vec4(0),
            margin: 10,
            entries:(
              Button(
                color: vec4(0, 0, 0, 0.5),
                hoveredColor: vec4(0, 0, 0, 0.3),
                size: vec2(30, 30),
                label: Label(text: "<", color: vec4(1)),
                clickCb: proc() =
                  nextLevel(-1)
              ),
              Button(
                color: vec4(0, 0, 0, 0.5),
                hoveredColor: vec4(0, 0, 0, 0.3),
                size: vec2(125, 50),
                visible: (proc(): bool =
                  if menuState == previewingUserLevels:
                    true
                  else:
                    canPlayLevel()
                ),
                label: Label(text: "Play", color: vec4(1)),
                clickCb: proc() =
                  menuState = noMenu
                  world.state.incl playing
                  world.state.excl previewing
              ),
              Button(
                color: vec4(0, 0, 0, 0.5),
                hoveredColor: vec4(0, 0, 0, 0.3),
                size: vec2(30, 30),
                label: Label(text: ">", color: vec4(1)),
                clickCb: proc() =
                  nextLevel(1)
              ),
            )
          ),
          Button(
            color: vec4(0, 0, 0, 0.5),
            hoveredColor: vec4(0, 0, 0, 0.3),
            visible: (proc(): bool = menuState == previewingUserLevels),
            pos: vec3(10, 10, 0),
            size: vec2(125, 50),
            label: Label(text: "Edit", color: vec4(1)),
            clickCb: proc() =
              menuState = noMenu
              world.state = {editing}
              world.setupEditorGui()
          ),
          Button(
            color: vec4(0, 0, 0, 0.5),
            hoveredColor: vec4(0, 0, 0, 0.3),
            pos: vec3(10, 10, 0),
            size: vec2(125, 50),
            label: Label(text: "Back", color: vec4(1)),
            clickCb: proc() =
              menuState = inMain
          ),
        )
      ),

    )

