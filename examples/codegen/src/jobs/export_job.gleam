//// A queue job payload whose shape is fixed at build time.
////
//// Its codec, `jobs/export_job_codec`, is generated from the typed definition
//// in `test/export_job_definition.gleam`: the codec is module functions and
//// literals, so a worker process that receives one copies almost nothing.
//// The generated module refers to these types and mappings by name.

import gleam/option.{type Option}

pub type Format {
  Csv
  Json
  Pdf
}

pub type ExportJob {
  ExportJob(
    customer_id: String,
    format: Format,
    attempt: Int,
    recipients: List(String),
    note: Option(String),
  )
}

/// The generated codec decodes the properties as nested pairs, in the order
/// the definition combines them.
pub fn from_fields(
  fields: #(#(#(#(String, Format), Int), List(String)), Option(String)),
) -> ExportJob {
  let #(#(#(#(customer_id, format), attempt), recipients), note) = fields
  ExportJob(customer_id:, format:, attempt:, recipients:, note:)
}

pub fn to_fields(
  job: ExportJob,
) -> #(#(#(#(String, Format), Int), List(String)), Option(String)) {
  #(#(#(#(job.customer_id, job.format), job.attempt), job.recipients), job.note)
}
