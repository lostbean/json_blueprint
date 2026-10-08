// Adapted from the retained 2026-10-08 object-validation allocation probe.
import { Session } from "node:inspector/promises";
function measuredLoop(work, count) {
  for (let i = 0; i < count; i++) work();
}
function allocated(node, inside = false) {
  inside ||= node.callFrame.functionName === "measuredLoop";
  return (
    (inside ? node.selfSize : 0) +
    node.children.reduce((sum, child) => sum + allocated(child, inside), 0)
  );
}
export async function run(cases) {
  if (!global.gc) throw new Error("Run Node with --expose-gc");
  for (const job of process.env.BENCH_REVERSE === "1"
    ? [...cases].reverse()
    : cases) {
    const work = job.prepare();
    measuredLoop(work, 50);
    global.gc();
    global.gc();
    const session = new Session();
    session.connect();
    await session.post("HeapProfiler.enable");
    const interval = job.name.endsWith("_100") ? 4096 : 512;
    await session.post("HeapProfiler.startSampling", {
      samplingInterval: interval,
      stackDepth: 128,
      includeObjectsCollectedByMajorGC: true,
      includeObjectsCollectedByMinorGC: true,
    });
    measuredLoop(work, job.iterations);
    const { profile } = await session.post("HeapProfiler.stopSampling");
    session.disconnect();
    const bytes = allocated(profile.head);
    console.log(
      JSON.stringify({
        name: job.name,
        operation: job.operation,
        iterations: job.iterations,
        allocation_estimate_bytes: bytes,
        allocation_estimate_bytes_per_op: bytes / job.iterations,
        sampling_interval: interval,
        profile_samples: profile.samples.length,
      }),
    );
  }
}
