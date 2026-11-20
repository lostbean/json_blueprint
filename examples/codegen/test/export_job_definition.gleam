//// The typed definition the export job codec is generated from. It is a
//// development module: production uses only the generated source.

import jobs/export_job.{Csv, Json, Pdf}
import json/blueprint/codegen

pub fn definition() -> codegen.Definition(export_job.ExportJob) {
  let assert Ok(csv) = codegen.enum_variant("csv", Csv, "jobs/export_job.Csv")
  let assert Ok(json) =
    codegen.enum_variant("json", Json, "jobs/export_job.Json")
  let assert Ok(pdf) = codegen.enum_variant("pdf", Pdf, "jobs/export_job.Pdf")
  // Every constructor of `Format` has a label: the generated encoder must
  // still compile without warnings.
  let assert Ok(format) =
    codegen.string_enum("export_job.Format", [csv, json, pdf])
  let properties =
    codegen.combine(
      codegen.required("customerId", codegen.string()),
      codegen.required("format", format),
    )
    |> codegen.combine(codegen.required(
      "attempt",
      codegen.integer_between(1, 10),
    ))
    |> codegen.combine(codegen.required(
      "recipients",
      codegen.list(codegen.string()),
    ))
    |> codegen.combine(codegen.optional("note", codegen.string()))
  let assert Ok(mapping) =
    codegen.named_mapping(
      export_job.from_fields,
      "jobs/export_job.from_fields",
      export_job.to_fields,
      "jobs/export_job.to_fields",
    )
  let assert Ok(definition) =
    codegen.imap(codegen.object(properties), "export_job.ExportJob", mapping)
  codegen.describe(definition, "A data export queued for a worker")
}
