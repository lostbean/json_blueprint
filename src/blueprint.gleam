import gleam/dynamic
import gleam/json
import gleam/option.{type Option, None, Some}
import json_schema.{type SchemaDefinition, Type} as jsch

pub type Decoder(t) =
  #(dynamic.Decoder(t), SchemaDefinition)

pub type FieldDecoder(t) =
  #(dynamic.Decoder(t), #(String, SchemaDefinition))

pub fn generate_json_schema(decoder: Decoder(t)) -> json.Json {
  let #(_, schema) = decoder
  jsch.to_json(jsch.new_schema(schema))
}

pub fn get_dynamic_decoder(decoder: Decoder(t)) -> dynamic.Decoder(t) {
  let #(dyn_decoder, _) = decoder
  dyn_decoder
}

pub fn decode(
  using decoder: Decoder(t),
  from json_string: String,
) -> Result(t, json.DecodeError) {
  let #(dyn_decoder, _) = decoder
  json.decode(from: json_string, using: dyn_decoder)
}

pub fn string() -> Decoder(String) {
  #(dynamic.string, Type(jsch.StringType))
}

pub fn int() -> Decoder(Int) {
  #(dynamic.int, Type(jsch.IntegerType))
}

pub fn float() -> Decoder(Float) {
  #(dynamic.float, Type(jsch.NumberType))
}

pub fn bool() -> Decoder(Bool) {
  #(dynamic.bool, Type(jsch.BooleanType))
}

pub fn list(of decoder_type: Decoder(inner)) -> Decoder(List(inner)) {
  let #(decoder, schema) = decoder_type
  #(dynamic.list(decoder), jsch.Array(Some(schema)))
}

pub fn optional(of decode: Decoder(inner)) -> Decoder(Option(inner)) {
  let #(decoder, schema) = decode
  #(dynamic.optional(decoder), jsch.Nullable(schema))
}

pub fn field(named name: String, of inner_type: Decoder(t)) -> FieldDecoder(t) {
  let #(decoder, schema) = inner_type
  #(dynamic.field(name, decoder), #(name, schema))
}

pub fn optional_field(
  named name: String,
  of inner_type: Decoder(t),
) -> FieldDecoder(Option(t)) {
  let #(decoder, schema) = inner_type
  #(dynamic.optional_field(name, decoder), #(name, jsch.Nullable(schema)))
}

pub fn tuple2(
  first decode1: Decoder(a),
  second decode2: Decoder(b),
) -> Decoder(#(a, b)) {
  let #(decoder1, schema1) = decode1
  let #(decoder2, schema2) = decode2
  #(
    dynamic.tuple2(decoder1, decoder2),
    jsch.DetailedArray(
      None,
      Some([schema1, schema2]),
      Some(2),
      Some(2),
      None,
      None,
      None,
      None,
    ),
  )
}

pub fn tuple3(
  first decode1: Decoder(a),
  second decode2: Decoder(b),
  third decode3: Decoder(c),
) -> Decoder(#(a, b, c)) {
  let #(decoder1, schema1) = decode1
  let #(decoder2, schema2) = decode2
  let #(decoder3, schema3) = decode3
  #(
    dynamic.tuple3(decoder1, decoder2, decoder3),
    jsch.DetailedArray(
      None,
      Some([schema1, schema2, schema3]),
      Some(3),
      Some(3),
      None,
      None,
      None,
      None,
    ),
  )
}

pub fn tuple4(
  first decode1: Decoder(a),
  second decode2: Decoder(b),
  third decode3: Decoder(c),
  fourth decode4: Decoder(d),
) -> Decoder(#(a, b, c, d)) {
  let #(decoder1, schema1) = decode1
  let #(decoder2, schema2) = decode2
  let #(decoder3, schema3) = decode3
  let #(decoder4, schema4) = decode4
  #(
    dynamic.tuple4(decoder1, decoder2, decoder3, decoder4),
    jsch.DetailedArray(
      None,
      Some([schema1, schema2, schema3, schema4]),
      Some(4),
      Some(4),
      None,
      None,
      None,
      None,
    ),
  )
}

pub fn tuple5(
  first decode1: Decoder(a),
  second decode2: Decoder(b),
  third decode3: Decoder(c),
  fourth decode4: Decoder(d),
  fifth decode5: Decoder(e),
) -> Decoder(#(a, b, c, d, e)) {
  let #(decoder1, schema1) = decode1
  let #(decoder2, schema2) = decode2
  let #(decoder3, schema3) = decode3
  let #(decoder4, schema4) = decode4
  let #(decoder5, schema5) = decode5
  #(
    dynamic.tuple5(decoder1, decoder2, decoder3, decoder4, decoder5),
    jsch.DetailedArray(
      None,
      Some([schema1, schema2, schema3, schema4, schema5]),
      Some(5),
      Some(5),
      None,
      None,
      None,
      None,
    ),
  )
}

pub fn tuple6(
  first decode1: Decoder(a),
  second decode2: Decoder(b),
  third decode3: Decoder(c),
  fourth decode4: Decoder(d),
  fifth decode5: Decoder(e),
  sixth decode6: Decoder(f),
) -> Decoder(#(a, b, c, d, e, f)) {
  let #(decoder1, schema1) = decode1
  let #(decoder2, schema2) = decode2
  let #(decoder3, schema3) = decode3
  let #(decoder4, schema4) = decode4
  let #(decoder5, schema5) = decode5
  let #(decoder6, schema6) = decode6
  #(
    dynamic.tuple6(decoder1, decoder2, decoder3, decoder4, decoder5, decoder6),
    jsch.DetailedArray(
      None,
      Some([schema1, schema2, schema3, schema4, schema5, schema6]),
      Some(6),
      Some(6),
      None,
      None,
      None,
      None,
    ),
  )
}

pub fn decode1(constructor: fn(t1) -> t, t1: FieldDecoder(t1)) -> Decoder(t) {
  let #(decoder, schema) = t1
  #(dynamic.decode1(constructor, decoder), jsch.Object(Some([schema])))
}

pub fn decode2(
  constructor: fn(t1, t2) -> t,
  t1: FieldDecoder(t1),
  t2: FieldDecoder(t2),
) -> Decoder(t) {
  let #(decoder1, schema1) = t1
  let #(decoder2, schema2) = t2
  #(
    dynamic.decode2(constructor, decoder1, decoder2),
    jsch.Object(Some([schema1, schema2])),
  )
}

pub fn decode3(
  constructor: fn(t1, t2, t3) -> t,
  t1: FieldDecoder(t1),
  t2: FieldDecoder(t2),
  t3: FieldDecoder(t3),
) -> Decoder(t) {
  let #(decoder1, schema1) = t1
  let #(decoder2, schema2) = t2
  let #(decoder3, schema3) = t3
  #(
    dynamic.decode3(constructor, decoder1, decoder2, decoder3),
    jsch.Object(Some([schema1, schema2, schema3])),
  )
}
