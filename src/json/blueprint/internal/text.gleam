//// Byte-size checks on JSON text, shared by the parsers.

/// Report whether `source` has more than `max_bytes` bytes of UTF-8, without
/// encoding it on targets whose strings are not UTF-8.
@external(erlang, "json_blueprint_ffi", "utf8_byte_size_exceeds")
@external(javascript, "../../../json_blueprint_ffi.mjs", "utf8_byte_size_exceeds")
pub fn exceeds_byte_limit(source: String, max_bytes: Int) -> Bool

/// Check host string scalar validity before UTF-8 conversion can replace an
/// unpaired UTF-16 surrogate. Failure carries the valid prefix for location
/// reporting. Erlang strings already hold UTF-8, so no extra scan is needed.
@external(javascript, "../../../json_blueprint_ffi.mjs", "validate_scalars")
pub fn validate_scalars(_source: String) -> Result(Nil, String) {
  Ok(Nil)
}

/// The default byte bound of every parse: 1 MiB.
pub const default_max_bytes = 1_048_576
