// Heap words are a BEAM measure; the test skips the check on JavaScript.
export function flat_size_words(_term) {
  return -1;
}

// JavaScript strings decoded from bytes never share the input's memory.
export function shares_input(_text) {
  return false;
}
