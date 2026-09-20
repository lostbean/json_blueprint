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
