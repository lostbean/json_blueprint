//// Tagged unions.
////
//// The JSON is `{"tag": "circle", "value": 2}`, and `{"tag": "empty"}` for a
//// unit variant. Gleam checks that the `case` covers every constructor.

import json/blueprint/codec.{type Codec}

pub type Shape {
  Circle(radius: Int)
  Label(text: String)
  Empty
}

pub fn shape_codec() -> Codec(Shape) {
  codec.union({
    use circle <- codec.variant("circle", codec.int(), Circle)
    use label <- codec.variant("label", codec.string(), Label)
    use empty <- codec.unit_variant("empty", Empty)
    codec.match(fn(shape) {
      case shape {
        Circle(radius) -> circle(radius)
        Label(text) -> label(text)
        Empty -> empty
      }
    })
  })
}

/// Runs the example and returns what it shows.
pub fn demonstrate() -> String {
  assert codec.encode_json(shape_codec(), Circle(2))
    == Ok("{\"tag\":\"circle\",\"value\":2}")
  assert codec.decode_json(shape_codec(), "{\"tag\":\"empty\"}") == Ok(Empty)
  let assert Ok(text) = codec.encode_json(shape_codec(), Label("hello"))
  text
}
