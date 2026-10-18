//// Schemas that arrive at runtime.
////
//// `json/blueprint/contract` accepts a Draft 2020-12 schema document inside
//// the profile that codecs describe, such as a tool's input schema from a
//// remote server, and validates values against it. A form outside the profile
//// returns `UnsupportedDocument`, a wrong keyword type returns
//// `MalformedDocument`, and loading stops at its first refusal. It does not
//// promise to load arbitrary third-party schemas, and the dynamic adapter
//// imposes no independent resource limits.

import gleam/result
import json/blueprint/contract
import json/blueprint/value

pub fn check_arguments(
  schema_text: String,
  arguments: String,
) -> Result(value.Value, String) {
  let limits = value.default_limits()
  use remote <- result.try(
    contract.parse(schema_text, limits)
    |> result.map_error(contract.describe_load_error),
  )
  use parsed <- result.try(
    value.parse(arguments, limits)
    |> result.map_error(value.describe_parse_error),
  )
  contract.validate(remote, parsed)
  |> result.map(contract.value)
  |> result.map_error(contract.describe_validation_error)
}

/// Runs the example and returns what it shows.
pub fn demonstrate() -> String {
  let schema =
    "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\","
    <> "\"type\":\"object\",\"properties\":{\"limit\":"
    <> "{\"type\":\"integer\",\"minimum\":1,\"maximum\":10}},"
    <> "\"required\":[\"limit\"],\"additionalProperties\":false}"
  let assert Ok(_) = check_arguments(schema, "{\"limit\":3}")
  let assert Error(reason) = check_arguments(schema, "{\"limit\":30}")
  assert reason == "$[\"limit\"]: integer outside range 1 to 10"
  reason
}
