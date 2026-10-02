//// Byte-size checks on JSON text, shared by the parsers.

/// Report whether `source` has more than `max_bytes` bytes of UTF-8, without
/// encoding it on targets whose strings are not UTF-8.
@external(erlang, "json_blueprint_ffi", "utf8_byte_size_exceeds")
@external(javascript, "../../../json_blueprint_ffi.mjs", "utf8_byte_size_exceeds")
pub fn exceeds_byte_limit(source: String, max_bytes: Int) -> Bool

/// The default byte bound of every parse: 1 MiB.
pub const default_max_bytes = 1_048_576
