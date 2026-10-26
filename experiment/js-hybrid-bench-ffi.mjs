// THROWAWAY: measure live-result heap and whole-process memory for the JS hybrid.
export function measure_memory(work) {
  globalThis.gc();
  const before = process.memoryUsage();
  work();
  globalThis.gc();
  const after = process.memoryUsage();
  const delta = Object.fromEntries(
    Object.keys(after).map((key) => [key, after[key] - before[key]]),
  );
  return JSON.stringify({ before, after, delta });
}
