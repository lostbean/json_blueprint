//// Regenerates `src/jobs/export_job_codec.gleam` from the typed definition:
////
//// ```sh
//// gleam run -m generate_export_job
//// gleam format src/jobs/export_job_codec.gleam
//// ```

import export_job_definition
import gleam/io
import json/blueprint/codegen

@external(erlang, "consumer_ffi", "write_file")
@external(javascript, "./consumer_ffi.mjs", "write_file")
fn write_file(path: String, content: String) -> Result(Nil, String)

pub fn main() {
  let assert Ok(codegen.GeneratedModule(path:, content:, fingerprint: _)) =
    codegen.compile(
      "jobs/export_job_codec",
      "export_job",
      export_job_definition.definition(),
    )
  let assert Ok(Nil) = write_file("src/" <> path, content)
  io.println("Generated src/" <> path)
}
