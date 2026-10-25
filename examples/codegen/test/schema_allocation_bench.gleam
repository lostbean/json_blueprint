import schema_bench

@external(erlang, "schema_allocation_probe", "run")
@external(javascript, "./schema_allocation_probe.mjs", "run")
fn run(cases: List(schema_bench.Workload)) -> Nil

pub fn main() {
  run(schema_bench.workloads())
}
