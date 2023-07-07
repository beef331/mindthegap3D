import std/[macros]
import frosty/streams
template unserialized* {.pragma.}

proc saveSkippingFields*[S](output: var S; val: object) =
  for name, field in val.fieldPairs:
    when not field.hasCustomPragma(unserialized):
      when defined(debugSerialiser):
        static: echo "Emit Save: ", $typeof(val), ".", name
        echo "Saving: ", name
      serialize(output, field)

proc loadSkippingFields*[S](input: var S; val: var object) =
  for name, field in val.fieldPairs:
    when not field.hasCustomPragma(unserialized):
      when defined(debugSerializer):
        static: echo "Emit Load: ", $typeof(val), ".", name 
        echo "Loading: ", name
      deserialize(input, field)
