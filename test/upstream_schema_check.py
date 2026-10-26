#!/usr/bin/env python3
"""Check pinned upstream schema fixtures, oracle verdicts and compiled test freshness.

Runs offline in the pinned Nix development shell. Does not modify any files.
"""

import hashlib
import json
from pathlib import Path
import subprocess

from jsonschema import Draft202012Validator

root = Path(__file__).resolve().parents[1]
out = root / "test/oracle/upstream-schema"
provenance = json.loads((out / "provenance.json").read_text())
assert provenance["revision"] == "89e83a74014617ffbe79a56d83d14d054cd11417"
assert (
    provenance["upstream"]
    == "https://github.com/json-schema-org/JSON-Schema-Test-Suite"
)
assert set(provenance["sources"]) == {
    "type",
    "items",
    "enum",
    "minimum",
    "maximum",
    "required",
}
for name, source in provenance["sources"].items():
    assert source["path"] == f"tests/draft2020-12/{name}.json"
    assert (
        hashlib.sha256((out / (name + ".json")).read_bytes()).hexdigest()
        == source["sha256"]
    ), name
assert (
    hashlib.sha256((out / "LICENSE").read_bytes()).hexdigest()
    == provenance["license_sha256"]
)

cases = []


def add(name, index, kind, schema=None, reason=None):
    group = json.loads((out / (name + ".json")).read_text())[index]
    tests = group["tests"]
    original = group["schema"]
    used = original if schema is None else schema
    Draft202012Validator.check_schema(used)
    validator = Draft202012Validator(used)
    original_validator = Draft202012Validator(original)
    for test in tests:
        assert original_validator.is_valid(test["data"]) == test["valid"], (
            name,
            index,
            test["description"],
        )
    cases.append(
        {
            "id": f"{name}/{index}/{kind}",
            "source_file": name + ".json",
            "source_group": index,
            "description": group["description"],
            "kind": kind,
            "adaptation": reason,
            "schema": used,
            "tests": [
                {
                    "description": t["description"],
                    "data": t["data"],
                    "upstream_valid": t["valid"],
                    "valid": validator.is_valid(t["data"])
                    if kind == "adapted"
                    else t["valid"],
                }
                for t in tests
            ],
        }
    )


for i in range(11):
    add("type", i, "unchanged" if i in (0, 1, 2, 5) else "unsupported")
for i in range(10):
    add("items", i, "unchanged" if i == 4 else "unsupported")
add("enum", 4, "unsupported")
s = json.loads((out / "enum.json").read_text())[4]["schema"]
s["type"] = "string"
add(
    "enum",
    4,
    "adapted",
    s,
    "Add explicit string type; upstream instance verdicts are unchanged.",
)
for name in ("minimum", "maximum"):
    for i in range(2):
        add(name, i, "unsupported")
        s = json.loads((out / (name + ".json")).read_text())[i]["schema"]
        s["type"] = "number"
        if name == "minimum":
            s["maximum"] = 1000000
        else:
            s["minimum"] = -1000000
        add(
            name,
            i,
            "adapted",
            s,
            "Add explicit number type and a nonbinding opposite bound. Non-number instances now reject; expected outcomes independently evaluated with Draft202012Validator.",
        )
for i in range(5):
    add("required", i, "unsupported")
    s = json.loads((out / "required.json").read_text())[i]["schema"]
    s["type"] = "object"
    s["additionalProperties"] = False
    props = s.setdefault("properties", {})
    required = s.setdefault("required", [])
    for name in required:
        props.setdefault(name, {})
    add(
        "required",
        i,
        "adapted",
        s,
        "Add explicit object type, properties, required, and closed-object policy. Upstream instances are retained; changed acceptance independently evaluated with Draft202012Validator.",
    )
s = json.loads((out / "items.json").read_text())[0]["schema"]
s["type"] = "array"
add(
    "items",
    0,
    "adapted",
    s,
    "Add explicit array type; non-array instances now reject, other upstream verdicts unchanged.",
)
assert len(cases) == 42
assert cases == json.loads((out / "cases.json").read_text()), (
    "cases.json differs from pinned upstream selection/adaptations"
)


# Gleam literals contain escaped JSON text, avoiding native numeric projection.
def lit(x):
    return json.dumps(x, ensure_ascii=False)


lines = [
    "// Derived from the pinned upstream files in test/oracle/upstream-schema/.",
    "// Cases and adaptation rules are recorded in cases.json; expected verdicts are",
    "// upstream-authored for unchanged cases and independently checked for adaptations.",
    "import gleam/list",
    "import gleam/result",
    "import gleeunit/should",
    "import json/blueprint/codec",
    "import json/blueprint/contract",
    "import json/blueprint/value",
    "",
    "fn check(schema_text: String, cases: List(#(String, Bool))) -> Nil {",
    "  let assert Ok(schema_value) = value.parse(schema_text, value.default_limits())",
    "  let assert Ok(loaded) = contract.load(schema_value)",
    "  let dynamic = contract.value_codec(loaded)",
    "  let assert Ok(rendered) = codec.schema_json(dynamic)",
    "  let assert Ok(reloaded) = contract.parse(rendered, value.default_limits())",
    "  contract.same_schema(loaded, reloaded) |> should.be_true",
    "  list.each(cases, fn(item) {",
    "    let #(text, expected) = item",
    "    let assert Ok(raw) = value.parse(text, value.default_limits())",
    "    contract.validate(loaded, raw) |> result.is_ok |> should.equal(expected)",
    "    contract.validate(reloaded, raw) |> result.is_ok |> should.equal(expected)",
    "    codec.decode(dynamic, raw) |> result.is_ok |> should.equal(expected)",
    "    codec.decode_json(dynamic, text) |> result.is_ok |> should.equal(expected)",
    "    codec.encode(dynamic, raw) |> result.is_ok |> should.equal(expected)",
    "    case codec.encode_json(dynamic, raw) {",
    "      Ok(encoded) -> {",
    "        expected |> should.be_true",
    "        codec.decode_json(dynamic, encoded) |> should.equal(Ok(raw))",
    "      }",
    "      Error(_) -> expected |> should.be_false",
    "    }",
    "  })",
    "}",
    "",
]
for c in cases:
    name = c["id"].replace("/", "_")
    lines += ["// " + c["description"]]
    if c["adaptation"]:
        lines += ["// " + c["adaptation"]]
    lines += ["pub fn " + name + "_test() -> Nil {"]
    s = lit(json.dumps(c["schema"], ensure_ascii=False, separators=(",", ":")))
    if c["kind"] == "unsupported":
        lines += [
            f"  let assert Ok(raw) = value.parse({s}, value.default_limits())",
            "  let assert Error(contract.UnsupportedDocument(_, _)) = contract.load(raw)",
            "  Nil",
        ]
    else:
        lines += [f"  check({s}, ["]
        for t in c["tests"]:
            lines += [
                "    // " + t["description"],
                "    #("
                + lit(json.dumps(t["data"], ensure_ascii=False, separators=(",", ":")))
                + ", "
                + str(t["valid"])
                + "),",
            ]
        lines += ["  ])"]
    lines += ["}", ""]
formatted = subprocess.run(
    ["gleam", "format", "--stdin"],
    input="\n".join(lines),
    text=True,
    capture_output=True,
    check=True,
).stdout
assert formatted == (root / "test/upstream_schema_test.gleam").read_text(), (
    "upstream_schema_test.gleam differs from checked fixtures"
)
print(
    "Upstream schema oracle: 40 unchanged instances, 44 adapted instances, 26 unsupported schemas; provenance and compiled fixture freshness passed"
)
