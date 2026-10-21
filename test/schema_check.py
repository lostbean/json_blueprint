"""Compare emitted Blueprint schemas with jsonschema Draft202012Validator against the frozen manifest.

Each case also carries the codec decoder outcome ("accepted") and the
`contract.validate` outcome ("runtime_accepted") for the contract loaded from
the emitted schema document; both must agree with the manifest and with the
validator on the emitted and the normalized schema.
"""

import json
import subprocess
from pathlib import Path

from jsonschema import Draft202012Validator


def validate_cases(cases, manifest):
    """Strictly validate cases against the frozen manifest and Draft202012Validator.
    Raises ValueError on any deviation.
    """
    seen_ids = set()

    for case in cases:
        case_id = case.get("case_id")
        if not case_id:
            raise ValueError(f"Missing case_id in case: {case}")
        if case_id in seen_ids:
            raise ValueError(f"Duplicate case_id: {case_id}")
        if case_id not in manifest:
            raise ValueError(f"Unexpected case_id not in frozen manifest: {case_id}")
        seen_ids.add(case_id)

        manifest_entry = manifest[case_id]
        label = case.get("label")
        if label != manifest_entry["family"]:
            raise ValueError(
                f"Family mismatch for {case_id}: expected {manifest_entry['family']}, got {label}"
            )

        # Exact schema and instance match with frozen manifest
        if case["instance"] != manifest_entry["instance"]:
            raise ValueError(
                f"Instance payload replaced/tampered for {case_id}: expected {manifest_entry['instance']}, got {case['instance']}"
            )
        if case["schema"] != manifest_entry["schema"]:
            raise ValueError(f"Schema payload replaced/tampered for {case_id}")

        # Outcome match with frozen manifest
        expected_accepted = manifest_entry["accepted"]
        if case["accepted"] != expected_accepted:
            raise ValueError(
                f"Outcome disagreement for {case_id}: expected {expected_accepted}, got {case['accepted']}"
            )

        # JSON Schema Draft 2020-12 validation
        Draft202012Validator.check_schema(case["schema"])
        accepted = Draft202012Validator(case["schema"]).is_valid(case["instance"])
        if accepted != expected_accepted:
            raise ValueError(
                f"JSON Schema oracle disagreement for {case_id}: expected {expected_accepted}, got {accepted}"
            )

        Draft202012Validator.check_schema(case["normalized_schema"])
        normalized_accepted = Draft202012Validator(case["normalized_schema"]).is_valid(
            case["instance"]
        )
        if (
            case["runtime_accepted"] != expected_accepted
            or normalized_accepted != expected_accepted
        ):
            raise ValueError(f"Contract/normalized schema disagreement for {case_id}")

    if seen_ids != set(manifest.keys()):
        missing = set(manifest.keys()) - seen_ids
        raise ValueError(f"Missing expected case IDs: {missing}")

    return True


def main():
    root = Path(__file__).resolve().parent.parent
    manifest_path = root / "test" / "schema_manifest.json"
    if not manifest_path.exists():
        raise SystemExit(f"FAIL: Manifest not found at {manifest_path}")

    with open(manifest_path, "r") as f:
        manifest = json.load(f)

    result = subprocess.run(
        ["gleam", "run", "-m", "schema_oracle_runner"],
        cwd=root,
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        raise SystemExit(result.stdout + result.stderr)

    cases = []
    for line in result.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        if (
            line.startswith("warning:")
            or line.startswith("Gleam magic")
            or line.startswith("Compiled in")
            or line.startswith("Running")
        ):
            continue
        if line.startswith("{"):
            cases.append(json.loads(line))

    # Validate live cases
    try:
        validate_cases(cases, manifest)
    except ValueError as e:
        raise SystemExit(f"FAIL: {e}")

    print(
        f"PASS: all {len(cases)} schema/decoder/contract cases agree with Draft202012Validator"
    )


if __name__ == "__main__":
    main()
