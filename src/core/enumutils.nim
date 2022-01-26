proc nextWrapped*[T: enum](a: T): T =
  const count = high(T).ord
  T((a.ord + 1 + count) mod count)
