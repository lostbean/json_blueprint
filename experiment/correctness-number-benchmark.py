"""Disposable before/after benchmark of standalone number.parse; run in nix develop.

Prepare isolated builds first; capture separately when other benchmarks are idle.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import shutil
import statistics
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import parser_benchmark as shared

WORKLOADS = [
    ("ordinary_decimal", "19.90", "default"),
    ("ordinary_exponent", "-6.02214076e23", "default"),
    ("large_safe_exponent", "1e-9007199254740991", "large"),
]
WORKLOADS += [
    ("record_20", "record_20", "default"),
    ("record_100", "record_100", "default"),
]
BOUNDARIES = ["1.00e-9007199254740991", "100e-9007199254740993"]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def hashes(root):
    return {
        str(p.relative_to(root)): digest(p)
        for p in sorted((root / "src").rglob("*"))
        if p.is_file()
    }


def prepare(work):
    work.mkdir(parents=True, exist_ok=False)
    revision = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
    ).strip()
    for variant in ("before", "after"):
        package = work / variant
        package.mkdir()
        if variant == "before":
            archive = subprocess.check_output(
                ["git", "archive", "--format=zip", revision, "src"], cwd=ROOT
            )
            with zipfile.ZipFile(io.BytesIO(archive)) as source:
                source.extractall(package)
        else:
            shutil.copytree(ROOT / "src", package / "src")
        for name in ("gleam.toml", "manifest.toml"):
            shutil.copy2(ROOT / name, package / name)
        (package / "test").mkdir()
        for name in (
            "bench_ffi.erl",
            "bench_ffi.mjs",
            "parser_benchmark_ffi.erl",
            "parser_benchmark_ffi.mjs",
        ):
            shutil.copy2(ROOT / "test" / name, package / "test" / name)
        shutil.copy2(
            ROOT / "experiment/correctness-number-runner.gleam",
            package / "test/correctness_number_runner.gleam",
        )
        for target in ("erlang", "javascript"):
            subprocess.run(
                ["gleam", "build", "--target", target, "--warnings-as-errors"],
                cwd=package,
                check=True,
            )
    (work / "preparation.json").write_text(
        json.dumps(
            {
                "before_revision": revision,
                "source_hashes": {v: hashes(work / v) for v in ("before", "after")},
            },
            indent=2,
        )
        + "\n"
    )


def run(package, target, token, limits, mode):
    shared.ROOT = package
    command = [
        part.replace("parser_benchmark_runner", "correctness_number_runner")
        for part in shared.runtime_command(target)
    ]
    return shared.run_process(
        command,
        dict(os.environ, NUMBER_TOKEN=token, NUMBER_LIMITS=limits, NUMBER_MODE=mode),
    )[0]


def capture(work, output):
    assert not output.exists()
    data = json.loads((work / "preparation.json").read_text())
    assert data["source_hashes"]["after"] == hashes(ROOT), (
        "Source changed after preparation"
    )
    data.update(
        captured_at_utc=datetime.now(timezone.utc).isoformat(),
        host=platform.platform(),
        versions={
            name: subprocess.check_output(cmd, text=True).strip()
            for name, cmd in [
                ("gleam", ["gleam", "--version"]),
                ("node", ["node", "--version"]),
                (
                    "erlang",
                    [
                        "erl",
                        "+S",
                        "1:1",
                        "-noshell",
                        "-eval",
                        'io:format("OTP ~s ERTS ~s", [erlang:system_info(otp_release), erlang:system_info(version)]), halt().',
                    ],
                ),
            ]
        },
        method="Six fresh VMs per variant/target/workload, alternating order. Each VM warms then measures five batches: 5000 calls for numbers, 500 for records. Median of VM medians; per-call nanoseconds. Observable sink retains last Result. Compilation, environment lookup, limit construction and outcome checks excluded. Erlang +S 1:1; Node default GC. No machine affinity/frequency control. Boundary outcomes measured separately, not timed. Wide-record codecs use unique names and required integer fields; construction, source generation and equality preflight excluded.",
        support_hashes={
            str(p.relative_to(ROOT)): digest(p)
            for p in [
                Path(__file__),
                ROOT / "experiment/correctness-number-runner.gleam",
                ROOT / "scripts/parser_benchmark.py",
                ROOT / "test/bench_ffi.erl",
                ROOT / "test/bench_ffi.mjs",
            ]
        },
        runs=[],
        boundaries=[],
        order=[],
    )
    for target in ("erlang", "javascript"):
        for name, token, limits in WORKLOADS:
            outcomes = {
                v: run(work / v, target, token, limits, "result")
                for v in ("before", "after")
            }
            assert outcomes["before"] == outcomes["after"] and outcomes[
                "after"
            ].startswith("Ok:")
            samples = {v: [] for v in ("before", "after")}
            for trial in range(6):
                order = ("before", "after") if trial % 2 == 0 else ("after", "before")
                data["order"].append([target, name, trial, list(order)])
                for variant in order:
                    samples[variant].append(
                        run(work / variant, target, token, limits, "timing")
                    )
            for variant in samples:
                medians = [statistics.median(batch) for batch in samples[variant]]
                data["runs"].append(
                    dict(
                        target=target,
                        workload=name,
                        token=token,
                        limits=limits,
                        variant=variant,
                        outcome=outcomes[variant],
                        samples_ns=samples[variant],
                        vm_medians_ns=medians,
                        median_ns=statistics.median(medians),
                    )
                )
        for token in BOUNDARIES:
            outcomes = {
                v: run(work / v, target, token, "large", "result")
                for v in ("before", "after")
            }
            expected = (
                "Error:ExponentOutOfRange"
                if target == "javascript" and token == BOUNDARIES[1]
                else "Ok:1e-9007199254740991"
            )
            assert outcomes["after"] == expected, outcomes
            data["boundaries"].append(dict(target=target, token=token, **outcomes))
    assert hashes(ROOT) == data["source_hashes"]["after"]
    output.write_text(json.dumps(data, indent=2) + "\n")
    print(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--prepare", action="store_true")
    parser.add_argument("--capture", action="store_true")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.prepare:
        prepare(args.work)
    if args.capture:
        assert args.output
        capture(args.work, args.output)
