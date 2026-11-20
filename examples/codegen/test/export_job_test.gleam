//// The export job codec is generated from a typed definition because its
//// shape is fixed at build time and every worker process holds the codec.

import export_job_definition
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import jobs/export_job.{type ExportJob, Csv, ExportJob, Json, Pdf}
import jobs/export_job_codec
import json/blueprint/codec
import json/blueprint/codegen

@external(erlang, "consumer_ffi", "flat_size_bytes")
@external(javascript, "./consumer_ffi.mjs", "flat_size_bytes")
fn flat_size_bytes(term: a) -> Int

fn sample(format: export_job.Format) -> ExportJob {
  ExportJob(
    customer_id: "c-42",
    format:,
    attempt: 1,
    recipients: ["ops@example.com"],
    note: None,
  )
}

pub fn generated_codec_matches_its_runtime_definition_test() {
  let generated = export_job_codec.export_job_codec()
  let runtime = codegen.runtime(export_job_definition.definition())
  codec.schema(generated) |> should.equal(codec.schema(runtime))
  list.each([Csv, Json, Pdf], fn(format) {
    let job = ExportJob(..sample(format), note: Some("monthly"))
    let assert Ok(text) = codec.encode_json(runtime, job)
    codec.encode_json(generated, job) |> should.equal(Ok(text))
    codec.decode_json(generated, text) |> should.equal(Ok(job))
    export_job_codec.decode_export_job_json(text) |> should.equal(Ok(job))
  })
}

pub fn generated_codec_refuses_what_the_definition_refuses_test() {
  let text =
    "{\"customerId\":\"c-42\",\"format\":\"xls\",\"attempt\":1,\"recipients\":[]}"
  let assert Error(error) =
    codec.decode_json(export_job_codec.export_job_codec(), text)
  codec.decode_json(codegen.runtime(export_job_definition.definition()), text)
  |> should.equal(Error(error))
}

/// A generated codec is module functions and literals; the combinator codec
/// for the same shape holds closures. Sending either to a worker copies its
/// flat size, which only the BEAM measures.
pub fn generated_codec_is_smaller_to_copy_than_combinators_test() {
  let generated = flat_size_bytes(export_job_codec.export_job_codec())
  let runtime =
    flat_size_bytes(codegen.runtime(export_job_definition.definition()))
  case generated {
    -1 -> Nil
    _ -> {
      { generated < 2048 } |> should.be_true
      { generated * 10 < runtime } |> should.be_true
    }
  }
}
