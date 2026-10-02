"""Compare emitted Blueprint schemas with jsonschema Draft202012Validator against the frozen manifest.

Each case also carries the codec decoder outcome ("accepted") and the
`contract.validate` outcome ("runtime_accepted") for the contract loaded from
the emitted schema document; both must agree with the manifest and with the
validator on the emitted and the normalized schema. Also proves that
missing, extra, duplicate, or replaced fixtures fail closed.
"""
import copy
import json
import subprocess
from collections import Counter
from pathlib import Path

from jsonschema import Draft202012Validator

EXPECTED_FAMILIES = {
    "finite-priority": 8,
    "finite-unusual-labels": 4,
    "finite-object": 7,
    "finite-list-nullable": 4,
    "text": 3,
    "integer": 3,
    "boolean": 2,
    "pair": 5,
    "list-nullable": 4,
    "empty-object": 3,
    "optional-nullable-record": 6,
    "inclusive-bounds": 6,
    "tagged-decision": 6,
    "union-unit-variants": 12,
}
TOTAL_EXPECTED_CASES = sum(EXPECTED_FAMILIES.values())  # 73


def validate_cases(cases, manifest):
    """Strictly validate cases against the frozen manifest and Draft202012Validator.
    Raises ValueError on any deviation.
    """
    if len(cases) != TOTAL_EXPECTED_CASES:
        raise ValueError(
            f"Expected {TOTAL_EXPECTED_CASES} cases, got {len(cases)}"
        )

    seen_ids = set()
    seen_family_instances = set()
    observed_families = Counter()
    outcomes = set()

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
        observed_families[label] += 1

        # Reject duplicate payloads within the same family
        family_instance_key = (
            label,
            json.dumps(case["instance"], sort_keys=True),
        )
        if family_instance_key in seen_family_instances:
            raise ValueError(
                f"Duplicate instance payload in family {label}: {case_id}"
            )
        seen_family_instances.add(family_instance_key)

        # Exact schema and instance match with frozen manifest
        if case["instance"] != manifest_entry["instance"]:
            raise ValueError(
                f"Instance payload replaced/tampered for {case_id}: expected {manifest_entry['instance']}, got {case['instance']}"
            )
        if case["schema"] != manifest_entry["schema"]:
            raise ValueError(
                f"Schema payload replaced/tampered for {case_id}"
            )

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
        normalized_accepted = Draft202012Validator(
            case["normalized_schema"]
        ).is_valid(case["instance"])
        if (
            case["runtime_accepted"] != expected_accepted
            or normalized_accepted != expected_accepted
        ):
            raise ValueError(
                f"Contract/normalized schema disagreement for {case_id}"
            )
        outcomes.add(accepted)

    if seen_ids != set(manifest.keys()):
        missing = set(manifest.keys()) - seen_ids
        raise ValueError(f"Missing expected case IDs: {missing}")

    if observed_families != EXPECTED_FAMILIES:
        raise ValueError(
            f"Family count mismatch: expected {EXPECTED_FAMILIES}, got {dict(observed_families)}"
        )

    if outcomes != {True, False}:
        raise ValueError("Corpus must include accepted and rejected instances")

    return True


def verify_mutation_fail_closed(cases, manifest):
    """Proves that missing, extra, duplicate, and replaced fixtures fail closed."""
    # 1. Missing fixture fails
    try:
        validate_cases(cases[:-1], manifest)
        raise SystemExit("FAIL: Dropping a fixture did not fail!")
    except ValueError:
        pass

    # 2. Extra fixture fails
    extra_case = copy.deepcopy(cases[0])
    extra_case["case_id"] = "extra-family/extra-case"
    try:
        validate_cases(cases + [extra_case], manifest)
        raise SystemExit("FAIL: Adding an extra fixture did not fail!")
    except ValueError:
        pass

    # 3. Duplicate fixture ID fails
    dup_id_cases = copy.deepcopy(cases)
    dup_id_cases[1]["case_id"] = dup_id_cases[0]["case_id"]
    try:
        validate_cases(dup_id_cases, manifest)
        raise SystemExit("FAIL: Duplicate fixture ID did not fail!")
    except ValueError:
        pass

    # 4. Duplicate payload in same family fails
    dup_payload_cases = copy.deepcopy(cases)
    dup_payload_cases[1]["instance"] = dup_payload_cases[0]["instance"]
    dup_payload_cases[1]["label"] = dup_payload_cases[0]["label"]
    try:
        validate_cases(dup_payload_cases, manifest)
        raise SystemExit("FAIL: Duplicate payload in same family did not fail!")
    except ValueError:
        pass

    # 5. Replaced instance fails
    replaced_inst_cases = copy.deepcopy(cases)
    replaced_inst_cases[0]["instance"] = {"tampered": True}
    try:
        validate_cases(replaced_inst_cases, manifest)
        raise SystemExit("FAIL: Replaced instance did not fail!")
    except ValueError:
        pass

    # 6. Replaced expected outcome fails
    flipped_outcome_cases = copy.deepcopy(cases)
    flipped_outcome_cases[0]["accepted"] = not flipped_outcome_cases[0]["accepted"]
    try:
        validate_cases(flipped_outcome_cases, manifest)
        raise SystemExit("FAIL: Flipped outcome did not fail!")
    except ValueError:
        pass


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

    # Verify mutations fail closed
    verify_mutation_fail_closed(cases, manifest)

    print(
        f"PASS: all {len(cases)} schema/decoder/contract cases agree with Draft202012Validator across all {len(EXPECTED_FAMILIES)} frozen families"
    )
    print(
        "PASS: fail-closed mutation proofs passed (missing, extra, duplicate, replaced fixture detection verified)"
    )


if __name__ == "__main__":
    main()
