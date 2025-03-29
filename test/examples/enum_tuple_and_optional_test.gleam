import gleam/json
import gleam/option.{type Option, None, Some}
import gleeunit
import gleeunit/should
import json/blueprint

pub fn main() {
  gleeunit.main()
}

type Color {
  Red
  Green
  Blue
}

type Coordinate =
  #(Float, Float)

type Drawing {
  Box(Float, Float, Coordinate, Option(Color))
}

fn color_decoder() {
  blueprint.enum_type_decoder([
    #("red", Red),
    #("green", Green),
    #("blue", Blue),
  ])
}

fn color_encoder(input) {
  blueprint.enum_type_encoder(input, fn(color) {
    case color {
      Red -> "red"
      Green -> "green"
      Blue -> "blue"
    }
  })
}

fn encode_coordinate(coord: Coordinate) -> json.Json {
  blueprint.encode_tuple2(coord, json.float, json.float)
}

fn coordinate_decoder() {
  blueprint.tuple2(blueprint.float(), blueprint.float())
}

fn encode_drawing(drawing: Drawing) -> json.Json {
  blueprint.union_type_encoder(drawing, fn(shape) {
    case shape {
      Box(width, height, position, color) -> #(
        "box",
        json.object([
          #("width", json.float(width)),
          #("height", json.float(height)),
          #("position", encode_coordinate(position)),
          #("color", json.nullable(color, color_encoder)),
        ]),
      )
    }
  })
}

fn drawing_decoder() -> blueprint.Decoder(Drawing) {
  blueprint.union_type_decoder([
    #(
      "box",
      blueprint.decode4(
        Box,
        blueprint.field("width", blueprint.float()),
        blueprint.field("height", blueprint.float()),
        blueprint.field("position", coordinate_decoder()),
        blueprint.optional_field("color", color_decoder()),
      ),
    ),
  ])
}

pub fn drawing_test() {
  // Test cases
  let box = Box(15.0, 25.0, #(30.0, 40.0), None)

  // Test encoding
  let encoded_box = encode_drawing(box)

  // Test decoding
  encoded_box
  |> json.to_string
  |> blueprint.decode(using: drawing_decoder())
  |> should.equal(Ok(box))

  blueprint.generate_json_schema(drawing_decoder())
  |> json.to_string
}

pub fn drawing_match_str_test() {
  // Test specific JSON structure
  Box(15.0, 25.0, #(30.0, 40.0), None)
  |> encode_drawing()
  |> should.equal(
    json.object([
      #("type", json.string("box")),
      #(
        "data",
        json.object([
          #("width", json.float(15.0)),
          #("height", json.float(25.0)),
          #(
            "position",
            json.preprocessed_array([json.float(30.0), json.float(40.0)]),
          ),
          #("color", json.null()),
        ]),
      ),
    ]),
  )

  // Test invalid data
  // Test missing required fields
  "{\"type\":\"box\",\"data\":{\"width\":15.0}}"
  |> blueprint.decode(using: drawing_decoder())
  |> should.be_error()

  drawing_decoder()
  |> blueprint.generate_json_schema
  |> json.to_string
  |> should.equal(
    "{\"$schema\":\"http://json-schema.org/draft-07/schema#\",\"required\":[\"type\",\"data\"],\"additionalProperties\":false,\"type\":\"object\",\"properties\":{\"type\":{\"type\":\"string\",\"enum\":[\"box\"]},\"data\":{\"required\":[\"width\",\"height\",\"position\"],\"additionalProperties\":false,\"type\":\"object\",\"properties\":{\"width\":{\"type\":\"number\"},\"height\":{\"type\":\"number\"},\"position\":{\"maxItems\":2,\"minItems\":2,\"prefixItems\":[{\"type\":\"number\"},{\"type\":\"number\"}],\"type\":\"array\"},\"color\":{\"required\":[\"enum\"],\"additionalProperties\":false,\"type\":\"object\",\"properties\":{\"enum\":{\"type\":\"string\",\"enum\":[\"red\",\"green\",\"blue\"]}}}}}}}",
  )
}

pub fn enum_type_test() {
  // Test encoding
  color_encoder(Red)
  |> json.to_string
  |> should.equal("{\"enum\":\"red\"}")

  color_encoder(Green)
  |> json.to_string
  |> should.equal("{\"enum\":\"green\"}")

  color_encoder(Blue)
  |> json.to_string
  |> should.equal("{\"enum\":\"blue\"}")

  // Test decoding
  blueprint.decode(color_decoder(), "{\"enum\":\"red\"}")
  |> should.equal(Ok(Red))

  blueprint.decode(color_decoder(), "{\"enum\":\"green\"}")
  |> should.equal(Ok(Green))

  blueprint.decode(color_decoder(), "{\"enum\":\"blue\"}")
  |> should.equal(Ok(Blue))

  // Test invalid enum value
  blueprint.decode(color_decoder(), "{\"enum\":\"yellow\"}")
  |> should.be_error

  // Test encoding a Circle
  let red = Red
  // Test encoding a Rectangle
  let blue = Blue

  //test decoding
  color_encoder(red)
  |> json.to_string
  |> blueprint.decode(using: color_decoder())
  |> should.equal(Ok(red))

  color_encoder(blue)
  |> json.to_string
  |> blueprint.decode(using: color_decoder())
  |> should.equal(Ok(blue))
}

type ColorPair =
  #(Color, Color)

type RBG =
  #(Int, Int, Int)

type Palette {
  Palette(
    primary: Color,
    secondary: Option(Color),
    pair: Option(ColorPair),
    rgb: Option(RBG),
  )
}

fn encode_palette(input) {
  blueprint.union_type_encoder(input, fn(palette) {
    case palette {
      Palette(primary, secondary, pair, rgb) -> {
        let fields = [
          #("primary", color_encoder(primary)),
          #("secondary", json.nullable(secondary, color_encoder)),
          #(
            "pair",
            json.nullable(pair, blueprint.encode_tuple2(
              _,
              color_encoder,
              color_encoder,
            )),
          ),
          #(
            "rgb",
            json.nullable(rgb, blueprint.encode_tuple3(
              _,
              json.int,
              json.int,
              json.int,
            )),
          ),
        ]
        #("palette", json.object(fields))
      }
    }
  })
}

fn palette_decoder() {
  blueprint.union_type_decoder([
    #(
      "palette",
      blueprint.decode4(
        Palette,
        blueprint.field("primary", color_decoder()),
        blueprint.optional_field("secondary", color_decoder()),
        blueprint.optional_field(
          "pair",
          blueprint.tuple2(color_decoder(), color_decoder()),
        ),
        blueprint.optional_field(
          "rgb",
          blueprint.tuple3(blueprint.int(), blueprint.int(), blueprint.int()),
        ),
      ),
    ),
  ])
}

pub fn palette_test() {
  // Create decoder for Palette

  // Test cases
  let palette1 =
    Palette(
      primary: Red,
      secondary: Some(Blue),
      pair: Some(#(Green, Red)),
      rgb: Some(#(255, 128, 0)),
    )

  let palette2 = Palette(primary: Green, secondary: None, pair: None, rgb: None)

  // Test encoding
  let encoded1 = encode_palette(palette1)
  let encoded2 = encode_palette(palette2)

  // Test decoding
  encoded1
  |> json.to_string
  |> blueprint.decode(using: palette_decoder())
  |> should.equal(Ok(palette1))

  encoded2
  |> json.to_string
  |> blueprint.decode(using: palette_decoder())
  |> should.equal(Ok(palette2))

  // Test specific JSON structure
  encoded1
  |> json.to_string
  |> should.equal(
    "{\"type\":\"palette\",\"data\":{\"primary\":{\"enum\":\"red\"},\"secondary\":{\"enum\":\"blue\"},\"pair\":[{\"enum\":\"green\"},{\"enum\":\"red\"}],\"rgb\":[255,128,0]}}",
  )

  encoded2
  |> json.to_string
  |> should.equal(
    "{\"type\":\"palette\",\"data\":{\"primary\":{\"enum\":\"green\"},\"secondary\":null,\"pair\":null,\"rgb\":null}}",
  )
}
