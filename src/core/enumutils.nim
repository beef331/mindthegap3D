proc nextWrapped*[T: enum](a: T, dir: -1..1 = 1): T =
  const count = high(T).ord + 1
  T((a.ord + dir + count) mod count)
