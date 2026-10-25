//// Regenerate the schema-driven compiled fixtures, then format test/generated.

import json/blueprint/codec
import json/blueprint/codegen/schema
import json/blueprint/contract
import json/blueprint/number
import json/blueprint/value

@external(erlang, "file_test_ffi", "write_file")
@external(javascript, "./file_test_ffi.mjs", "write_file")
fn write_file(path: String, content: String) -> Result(Nil, String)

pub fn feature_schema() -> codec.Schema {
  let limits =
    value.default_limits()
    |> value.with_number_limits(number.limits(1024, 800, 2000))
  let assert Ok(contract) =
    contract.parse(
      "{
    \"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":\"object\",\"description\":\"escaped \\u0000 \\b \\f \\t \\n \\r \\\" \\\\ 雪\",
    \"properties\":{
      \"\\uD800\\uDC00a\":{\"type\":\"string\"},
      \"\\uE000b\":{\"type\":\"string\"},
      \"1 id\":{\"type\":\"boolean\"},
      \"type\":{\"type\":\"string\"},
      \"wire\\u0000x\":{\"type\":\"string\"},
      \"range\":{\"type\":\"number\",\"minimum\":1e1500,\"maximum\":1.0000000000000000000001e1500},
      \"pair\":{\"type\":\"array\",\"prefixItems\":[{\"type\":\"object\",\"properties\":{},\"required\":[],\"additionalProperties\":false},{\"anyOf\":[{\"type\":\"null\"},{\"anyOf\":[{\"type\":\"null\"},{\"type\":\"integer\"}]}]}],\"minItems\":2,\"maxItems\":2}
    },\"required\":[\"1 id\",\"wire\\u0000x\",\"range\",\"pair\"],\"additionalProperties\":false
  }",
      limits,
    )
  contract.schema(contract)
}

pub fn main() {
  let assert Ok(module) =
    schema.compile("generated/schema_ok", "ok", feature_schema())
  let assert Ok(_) = write_file("test/" <> module.path, module.content)
  let assert Ok(module) =
    schema.compile("generated/schema_feature", "feature", feature_schema())
  let assert Ok(_) = write_file("test/" <> module.path, module.content)
  let assert Ok(empty) = codec.schema(codec.success(Nil))
  let assert Ok(module) =
    schema.compile("generated/schema_empty", "empty", empty)
  let assert Ok(_) = write_file("test/" <> module.path, module.content)
}
