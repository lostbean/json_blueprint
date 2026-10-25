"""THROWAWAY: reproducible bounded-native corpus and numeric comparisons."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(ROOT / "test"), str(ROOT / "scripts")]
import parser_check
import parser_benchmark

parser_benchmark.ROOT = ROOT


def run(module, settings):
    command = [
        part.replace("parser_benchmark_runner", module)
        for part in parser_benchmark.runtime_command("erlang")
    ]
    subprocess.run(command, cwd=ROOT, env=dict(os.environ, **settings), check=True)


with tempfile.TemporaryDirectory() as temp:
    root = Path(temp)
    for name, raw in parser_check.load_cases().items():
        (root / name).write_bytes(raw)
    run("native_bounded_probe", {"BLUEPRINT_PARSER_CORPUS": str(root)})
run(
    "native_bounded_numeric_probe",
    {"BLUEPRINT_PARSER_INPUT": str(ROOT / "experiment/bounded-numeric-tokens.txt")},
)
