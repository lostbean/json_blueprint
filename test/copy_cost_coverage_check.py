"""Every public function of the package that returns a Codec or a Union has a
`<name>_holds_its_inputs_once_test` in codec_input_once_test.gleam (ADR 0018),
the name prefixed by its module outside json/blueprint/codec, such as
`contract_value_codec`.

The combinators come from the compiler's package interface
(`gleam export package-interface`), whose path is the first argument, so a
new public combinator without a copy test fails the gate.
"""

import json
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
interface = json.loads(Path(sys.argv[1]).read_text())
combinators = set()
for module, contents in interface["modules"].items():
    for name, function in contents["functions"].items():
        returned = function["return"]
        if (
            returned.get("kind") == "named"
            and returned.get("module") == "json/blueprint/codec"
            and returned.get("name") in ("Codec", "Union")
        ):
            prefix = (
                ""
                if module == "json/blueprint/codec"
                else module.rsplit("/", 1)[-1] + "_"
            )
            combinators.add(prefix + name)
if not combinators:
    sys.exit("copy-cost coverage: the package interface lists no combinators")

tests = (root / "test/codec_input_once_test.gleam").read_text()
covered = set(re.findall(r"^pub fn (\w+)_holds_its_inputs_once_test\(", tests, re.M))
missing = sorted(combinators - covered)
if missing:
    sys.exit("copy-cost coverage: no copy test for %s" % ", ".join(missing))
print(
    "copy-cost coverage: %d public functions returning a codec, each with a copy test"
    % len(combinators)
)
