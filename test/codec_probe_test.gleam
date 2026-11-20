import codec_probe
import codec_probe_expected
import gleam/list
import gleeunit/should

/// Every probe line equals its expected line; compared line by line so a
/// failure names the case.
pub fn probe_matches_its_expected_output_test() {
  let actual = codec_probe.lines()
  list.length(actual) |> should.equal(list.length(codec_probe_expected.lines))
  list.zip(actual, codec_probe_expected.lines)
  |> list.each(fn(pair) { pair.0 |> should.equal(pair.1) })
}
