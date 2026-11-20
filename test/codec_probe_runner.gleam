//// Writes `test/codec_probe_expected.gleam` from the probe's current output:
////
//// ```sh
//// gleam run -m codec_probe_runner > test/codec_probe_expected.gleam
//// gleam format test/codec_probe_expected.gleam
//// ```
////
//// Run it only where `codec_probe_expected` says its lines may be replaced.

import codec_probe
import gleam/io
import gleam/list
import gleam/string

pub fn main() -> Nil {
  io.println(
    "//// Expected output of `codec_probe.lines()`, written by\n"
    <> "//// `codec_probe_runner`. Every line was generated on json_blueprint 2.1.1\n"
    <> "//// (commit 323f133) with Gleam 1.19.2, Erlang/OTP 29 and Node 24, and is\n"
    <> "//// the same on both targets, except the `adr-0018` cases: they follow\n"
    <> "//// ADR 0018 (2.2.0), which changed them from 2.1.1. A line changes only\n"
    <> "//// in a commit that names the design or ADR change it follows; new cases\n"
    <> "//// are appended.\n\n"
    <> "pub const lines = [\n"
    <> string.join(
      list.map(codec_probe.lines(), fn(line) { "  \"" <> escape(line) <> "\"," }),
      "\n",
    )
    <> "\n]",
  )
}

fn escape(text: String) -> String {
  text
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
  |> string.replace("\n", "\\n")
}
