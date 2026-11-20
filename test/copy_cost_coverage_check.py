"""Every public function of json/blueprint/codec that returns a Codec or a
Union has a `<name>_holds_its_inputs_once_test` in codec_input_once_test.gleam
(ADR 0018)."""

import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
source = (root / "src/json/blueprint/codec.gleam").read_text()
tests = (root / "test/codec_input_once_test.gleam").read_text()

combinators = set()
for match in re.finditer(r"^pub fn (\w+)\((.*?)\{\n", source, re.S | re.M):
    signature = match.group(2)
    if re.search(r"\)\s*->\s*(Codec|Union)\(", signature):
        combinators.add(match.group(1))

covered = set(re.findall(r"^pub fn (\w+)_holds_its_inputs_once_test\(", tests, re.M))
missing = sorted(combinators - covered)
stale = sorted(covered - combinators)
if missing or stale:
    print(
        "copy-cost coverage: missing tests for",
        missing,
        "; tests without a combinator",
        stale,
    )
    sys.exit(1)
print("copy-cost coverage: %d combinators, each with a copy test" % len(combinators))
