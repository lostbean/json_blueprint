//// Optional, nullable and absent.
////
//// `optional_field` omits the field for `None` and decodes an absent field as
//// `None`; JSON `null` fails. `codec.nullable(c)` accepts `null` as `None`.
//// With `optional_field(name, codec.nullable(c), ..)`, an absent field,
//// `null` and a value decode as `None`, `Some(None)` and `Some(Some(x))`, and
//// encode back the same way.

import gleam/option.{type Option, None, Some}
import json/blueprint/codec.{type Codec}

pub type Profile {
  Profile(nickname: Option(String), website: Option(Option(String)))
}

pub fn profile_codec() -> Codec(Profile) {
  use nickname <- codec.optional_field("nickname", codec.string(), get: fn(p) {
    p.nickname
  })
  use website <- codec.optional_field(
    "website",
    codec.nullable(codec.string()),
    get: fn(p) { p.website },
  )
  codec.success(Profile(nickname:, website:))
}

/// Runs the example and returns what it shows.
pub fn demonstrate() -> String {
  let decode = fn(text) { codec.decode_json(profile_codec(), text) }
  // An absent field is None.
  assert decode("{}") == Ok(Profile(None, None))
  // Null is refused for a plain optional field...
  assert case decode("{\"nickname\":null}") {
    Error(_) -> True
    Ok(_) -> False
  }
  // ...and distinguished from absence once the codec is nullable.
  assert decode("{\"website\":null}") == Ok(Profile(None, Some(None)))
  assert decode("{\"website\":\"https://example.com\"}")
    == Ok(Profile(None, Some(Some("https://example.com"))))
  // Encoding writes each form back the same way.
  assert codec.encode_json(profile_codec(), Profile(None, None)) == Ok("{}")
  assert codec.encode_json(profile_codec(), Profile(None, Some(None)))
    == Ok("{\"website\":null}")
  "absent, null and a value decode to None, Some(None) and Some(Some(x))"
}
