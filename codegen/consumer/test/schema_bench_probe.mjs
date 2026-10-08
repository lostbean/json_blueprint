export function consume(value) {
  globalThis.__schema_consumer_benchmark_sink = value;
}
export function run(cases) {
  for (const job of process.env.BENCH_REVERSE === "1"
    ? [...cases].reverse()
    : cases) {
    const work = job.prepare();
    for (let i = 0; i < 50; i++) work();
    const pilotStart = process.hrtime.bigint();
    for (let i = 0; i < 50; i++) work();
    const pilotNs = Math.max(1, Number(process.hrtime.bigint() - pilotStart));
    const iterations = Math.min(
      2000000,
      Math.max(job.iterations, Math.ceil((150000000 * 50) / pilotNs)),
    );
    global.gc?.();
    const start = process.hrtime.bigint();
    for (let i = 0; i < iterations; i++) work();
    const ns = Number(process.hrtime.bigint() - start);
    console.log(
      JSON.stringify({
        name: job.name,
        operation: job.operation,
        iterations,
        elapsed_ns: ns,
        ns_per_op: ns / iterations,
      }),
    );
  }
}
