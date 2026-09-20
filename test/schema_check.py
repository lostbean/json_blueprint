"""Compare emitted Blueprint schemas with jsonschema Draft202012Validator."""
import json
import subprocess
from pathlib import Path

from jsonschema import Draft202012Validator


def main():
    root = Path(__file__).resolve().parent.parent
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
        if line.startswith("warning:") or line.startswith("Gleam magic") or line.startswith("Compiled in") or line.startswith("Running"):
            continue
        if line.startswith("{"):
            cases.append(json.loads(line))

    if not cases:
        raise SystemExit("FAIL: empty schema agreement corpus")

    outcomes = set()
    for case in cases:
        Draft202012Validator.check_schema(case["schema"])
        accepted = Draft202012Validator(case["schema"]).is_valid(case["instance"])
        if accepted != case["accepted"]:
            raise SystemExit(f"FAIL: schema disagreement: {case['label']}: {case}")
        Draft202012Validator.check_schema(case["normalized_schema"])
        normalized_accepted = Draft202012Validator(
            case["normalized_schema"]
        ).is_valid(case["instance"])
        if accepted != case["runtime_accepted"] or accepted != normalized_accepted:
            raise SystemExit(
                f"FAIL: runtime/normalized schema disagreement: {case['label']}: {case}"
            )
        outcomes.add(accepted)

    if outcomes != {True, False}:
        raise SystemExit("FAIL: corpus must include accepted and rejected instances")

    print(f"PASS: {len(cases)} schema/decoder/runtime cases agree with Draft202012Validator")


if __name__ == "__main__":
    main()
