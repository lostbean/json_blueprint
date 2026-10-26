"""THROWAWAY: compare hybrid acceptance/meaning with the pinned parser oracle.

Run after Gleam JavaScript build, in nix develop. Keeps reason-code differences
separate; does not turn invalid acceptance or changed exact meaning into a pass.
"""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from collections import Counter

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location(
    "parser_check", ROOT / "test/parser_check.py"
)
oracle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(oracle)
sys.setrecursionlimit(10000)
cases = oracle.load_cases()
with tempfile.TemporaryDirectory(prefix="js-hybrid-review-corpus-") as directory:
    for name, raw in cases.items():
        (Path(directory) / name).write_bytes(raw)
    run = subprocess.run(
        [
            "node",
            "--input-type=module",
            "-e",
            "import {main} from './build/dev/javascript/json_blueprint/parser_corpus_runner.mjs'; main();",
        ],
        cwd=ROOT,
        env={**os.environ, "BLUEPRINT_PARSER_CORPUS": directory},
        capture_output=True,
        text=True,
        timeout=120,
    )
    if run.returncode:
        print(run.stdout)
        print(run.stderr, file=sys.stderr)
        raise SystemExit(run.returncode)
    rows = [json.loads(line) for line in run.stdout.split("\n") if line.strip()]
assert Counter(row["name"] for row in rows) == Counter(cases.keys())
failures = []
reason_differences = []
for row in rows:
    name = row["name"]
    try:
        oracle.check_case(name, cases[name], row, "javascript")
    except AssertionError as error:
        # Native Erlang already uses syntax for malformed scalar escapes. Keep
        # these diagnostic differences visible; acceptance is still rejection.
        if "rejected" in row and "expected " in str(error) and "got " in str(error):
            reason_differences.append({"name": name, "difference": str(error)})
        else:
            failures.append({"name": name, "failure": str(error)})
print(
    json.dumps(
        {
            "cases": len(cases),
            "upstream": 318,
            "generated": len(cases) - 318,
            "failures": failures,
            "reason_differences": reason_differences,
        },
        indent=2,
    )
)
if failures:
    raise SystemExit(1)
