import flatty
import std/[options, net]
import worlds
export options, net
const
  editorPort = Port(34213)
  gamePort = Port(25422)

type
  EditorConnection* = object
    server: Socket
    client: Socket


proc connectToClient*(): EditorConnection =
  result.server = newSocket()
  result.server.bindAddr(editorPort)
  result.server.listen()

proc connectToEditor*(): Socket =
  result = newSocket()
  try:
    result.connect("127.0.0.1", editorPort)
    echo "Connected to editor"
  except:
    echo "failed to connect to editor ", getCurrentExceptionMsg()
    result.close()
    result = nil


proc toFlatty[T](s: var string; x: set[T]) =
  let startPos = s.len
  s.setLen(s.len + sizeof(x))
  copyMem(s[startPos].addr, x.unsafeAddr, sizeof(x))

proc fromFlatty[T](s: string; i: var int, x: var set[T]) =
  copyMem(x.addr, s[i].unsafeAddr, sizeof(x))
  inc i, sizeof(x)


proc sendWorld*(ec: ptr EditorConnection, world: World) =
  if ec.client == nil:
    var address = ""
    ec.server.acceptAddr(ec.client, address)
  try:
    let
      data = world.toFlatty
      dataSize = data.len
    var dataSent = 0
    discard ec.client.send(dataSize.unsafeAddr, sizeof(int))
    while dataSent < data.len:
      dataSent += ec.client.send(data[dataSent].unsafeAddr, min(1024, data.len - dataSent))
  except:
    ec.client = nil
    echo getCurrentExceptionMsg()

proc getWorld*(sock: Socket): Option[World] =
  try:
    var size = 0
    let read = sock.recv(size.addr, sizeof(int), 1)
    if read == sizeof(int):
      let
        buf = newString(size)
        bufRead =  sock.recv(buf[0].addr, size)
      if bufRead == size:
        result = some fromFlatty(buf, World)
  except TimeoutError:
    result = none(World)

