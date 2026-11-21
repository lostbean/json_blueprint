// Copied size is a BEAM measure; the tests and the profile skip it on JavaScript.
export function flat_size_words(_term) {
  return -1;
}

export function shared_size_words(_term) {
  return -1;
}

export function external_bytes(_term) {
  return -1;
}

export function reference_words() {
  return -1;
}

// JavaScript has no process copy or external term format: the term itself.
export function round_trip(term) {
  return term;
}

export function through_process(term) {
  return term;
}
