import std/[macros]
import frosty/streams
template unserialized* {.pragma.}

proc saveSkippingFields*[S](output: var S; val: object) =
  for field in val.fields:
    when not field.hasCustomPragma(unserialized):
      serialize(output, field)

proc loadSkippingFields*[S](input: var S; val: var object) =
  for field in val.fields:
    when not field.hasCustomPragma(unserialized):
      deserialize(input, field)
