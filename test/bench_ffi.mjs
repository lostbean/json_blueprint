let consumedValueCount = 0;

export function monotonic_nanos() {
  if (typeof process !== "undefined" && process.hrtime && process.hrtime.bigint) {
    return Number(process.hrtime.bigint());
  }
  return Math.round(performance.now() * 1000000);
}

export function target_runtime() {
  if (typeof process !== "undefined" && process.version) {
    return `Node.js ${process.version}`;
  }
  return "JavaScript";
}

export function consume(value) {
  // A global reference makes the constructed artefact observably escape this
  // module, so the JS engine cannot discard the construction as dead work.
  globalThis.__json_blueprint_benchmark_sink = value;
  consumedValueCount += 1;
}

export function consumed_count() {
  return consumedValueCount;
}
