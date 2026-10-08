"""Check the finite-profile diagnostic fixtures against Draft 2020-12.

This checks schema validity, not Blueprint acceptance or general conformance.
Gleam tests consume the same fixture documents and check diagnostic paths.
The oracle is the jsonschema version pinned by the repository's Nix shell.
No references are resolved and no network access is required.
"""

import json
from pathlib import Path

from jsonschema import Draft202012Validator, SchemaError


def main():
    cases = json.loads(Path("test/contract_profile_cases.json").read_text())
    for case in cases:
        try:
            Draft202012Validator.check_schema(case["schema"])
            valid = True
        except SchemaError:
            valid = False
        assert valid == (case["kind"] != "malformed"), case["name"]
    print(f"{len(cases)} schema-profile fixtures checked against Draft 2020-12")


if __name__ == "__main__":
    main()
