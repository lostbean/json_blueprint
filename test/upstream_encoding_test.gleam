import gleam/list
import gleeunit/should
import json/blueprint/codec

// Adapted from serde_json's test_roundtrip_f64 under the MIT license.
// Revision, source hash and license: test/oracle/serde-json/.
// These are historical rounding counterexamples, not random happy-path floats.
pub fn serde_binary64_regressions_test() {
  let cases = [
    #("51.248178375505404", 51.248178375505404),
    #("-93.31137037688033", -93.31137037688033),
    #("-36.573994842753436", -36.573994842753436),
    #("52.314008204106244", 52.314008204106244),
    #("97.45365320034685", 97.45365320034685),
    #("2.0030397744267762e-253", 2.0030397744267762e-253),
    #("7.101215824554616e260", 7.101215824554616e260),
    #("1.769268377902049e74", 1.769268377902049e74),
    #("-1.6727517818542075e58", -1.6727517818542075e58),
    #("3.9287532173373315e299", 3.9287532173373315e299),
  ]
  let float_codec = codec.float()
  list.each(cases, fn(pair) {
    let #(source, expected) = pair
    codec.decode_json(float_codec, source) |> should.equal(Ok(expected))
    let assert Ok(encoded) = codec.encode_json(float_codec, expected)
    codec.decode_json(float_codec, encoded) |> should.equal(Ok(expected))
    let assert Ok(value) = codec.encode(float_codec, expected)
    codec.decode(float_codec, value) |> should.equal(Ok(expected))
  })
}
