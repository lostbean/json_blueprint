"""THROWAWAY: compare final typed decoding with frozen strict/native prototypes.

Run in nix develop. --prepare-only builds isolated packages; --capture performs
fresh interleaved timing/memory trials after independent correctness preflight.
Existing captures are never overwritten. No production source is changed.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import statistics
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import parser_benchmark as shared


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def hashes(root):
    return {
        str(p.relative_to(root)): digest(p)
        for p in sorted((root / "src").rglob("*"))
        if p.is_file()
    }


def prepare(work):
    for name in ("strict", "final"):
        package = work / name
        package.mkdir(parents=True, exist_ok=False)
        if name == "strict":
            with zipfile.ZipFile(
                ROOT / "experiment/final-strict-source.zip"
            ) as archive:
                for entry in archive.infolist():
                    assert (
                        entry.filename.startswith("src/")
                        and ".." not in Path(entry.filename).parts
                    )
                archive.extractall(package)
        else:
            shutil.copytree(ROOT / "src", package / "src")
        for filename in ("gleam.toml", "manifest.toml"):
            shutil.copy2(ROOT / filename, package / filename)
        (package / "test").mkdir()
        for filename in (
            "bench_ffi.erl",
            "bench_ffi.mjs",
            "parser_benchmark_ffi.erl",
            "parser_benchmark_ffi.mjs",
            "host_string_test_ffi.mjs",
        ):
            shutil.copy2(ROOT / "test" / filename, package / "test" / filename)
        for filename in (
            "native_direct.gleam",
            "native_direct_ffi.erl",
            "native_direct_ffi.mjs",
            "native_lossless.gleam",
            "native_lossless_ffi.erl",
            "selective_ffi.erl",
            "selective_ffi.mjs",
        ):
            shutil.copy2(
                ROOT / "experiment/prototypes" / filename, package / "test" / filename
            )
        shutil.copy2(
            ROOT / "experiment/final-runner.gleam",
            package / "test/native_lossless_runner.gleam",
        )
        for target in ("erlang", "javascript"):
            subprocess.run(
                ["gleam", "build", "--target", target, "--warnings-as-errors"],
                cwd=package,
                check=True,
            )


def run(package, target, settings):
    shared.ROOT = package
    command = [
        part.replace("parser_benchmark_runner", "native_lossless_runner")
        for part in shared.runtime_command(target)
    ]
    if target == "javascript":
        command.insert(1, "--expose-gc")
    return shared.run_process(command, dict(os.environ, **settings))


def fixtures():
    compact = lambda item: json.dumps(item, separators=(",", ":"), ensure_ascii=False)
    records = [{"id": i, "name": "Ada Lovelace", "active": True} for i in range(50)]
    decimals = "[" + ",".join(["0.10000000000000001"] * 1000) + "]"
    cases = [
        ("small_record", "record", compact(records[0])),
        ("response_50", "response", compact({"items": records})),
        ("ints_10000", "ints", compact([0] * 10000)),
        ("ints_262143", "ints", compact([0] * 262143)),
        ("decimals_float_1000", "floats", decimals),
        ("decimals_exact_1000", "exact_numbers", decimals),
        (
            "optional_51",
            "optional",
            compact([{}, {"note": None}, {"note": "hello"}] * 17),
        ),
        ("unicode_strings", "strings", compact(["Olá, 世界 — café 👋🏽. " * 20] * 50)),
        (
            "text_records_50",
            "records",
            compact(
                [dict(item, name="Ordinary paragraph. " * 200) for item in records]
            ),
        ),
    ]

    return cases + [
        ("value_" + name, kind, source)
        for name, kind, source in cases
        if name in ("response_50", "ints_262143", "decimals_exact_1000")
    ]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--work", type=Path, default=Path("/tmp/blueprint-final-benchmark")
    )
    parser.add_argument(
        "--output", type=Path, default=ROOT / "experiment/final-results.json"
    )
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--capture", action="store_true")
    parser.add_argument("--trials", type=int, default=4)
    args = parser.parse_args()
    if not args.capture:
        prepare(args.work)
    if args.prepare_only:
        return
    assert args.trials >= 3
    assert not args.output.exists(), "Refusing to overwrite a capture"
    packages = {name: args.work / name for name in ("strict", "final")}
    baseline_hashes = json.loads(
        (ROOT / "experiment/adoption-results.json").read_text()
    )["source_hashes"]["baseline"]
    assert hashes(packages["strict"]) == baseline_hashes, (
        "Strict source differs from prior captured baseline"
    )
    assert hashes(packages["final"]) == hashes(ROOT), (
        "Final snapshot differs from current production source"
    )
    variant_config = {
        "strict": (packages["strict"], "strict"),
        "plain_native": (packages["strict"], "native"),
        "mitigated_native": (packages["strict"], "lossless"),
        "final": (packages["final"], "strict"),
    }
    data = {
        "captured_at_utc": datetime.now(timezone.utc).isoformat(),
        "revision": subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
        ).strip(),
        "host": platform.platform(),
        "versions": {
            name: subprocess.check_output(command, text=True).strip()
            for name, command in [
                ("gleam", ["gleam", "--version"]),
                ("node", ["node", "--version"]),
                ("python", [sys.executable, "--version"]),
                (
                    "erlang",
                    [
                        "erl",
                        "+S",
                        "1:1",
                        "-noshell",
                        "-eval",
                        'io:format("OTP ~s ERTS ~s",[erlang:system_info(otp_release),erlang:system_info(version)]), halt().',
                    ],
                ),
            ]
        },
        "method": "At least four fresh VM timing trials and separate one-decode memory trials for each fixture/variant/target, rounded up to complete variant-order rotations (four or six by default). Rotate variant order each trial. Each timing VM warms up then measures five batches; retain result in observable sink. Fixture loading, codec construction, compilation and equality preflight excluded from timing. Memory forces GC for retained process/VM observations; peak RSS from child wait4 includes entire runtime/input/result/intermediates. Erlang +S 1:1; Node --expose-gc. No CPU affinity/frequency control. Plain native is not semantically equivalent on duplicates/exact numbers; exact Number comparison intentionally N/A. JavaScript mitigated prototype unavailable.",
        "source_hashes": {name: hashes(package) for name, package in packages.items()},
        "support_hashes": {
            str(p.relative_to(ROOT)): digest(p)
            for p in [
                Path(__file__),
                ROOT / "experiment/final-runner.gleam",
                ROOT / "experiment/final-strict-source.zip",
                ROOT / "scripts/parser_benchmark.py",
                ROOT / "gleam.toml",
                ROOT / "manifest.toml",
                *sorted((ROOT / "experiment/prototypes").glob("native_direct*")),
                *sorted((ROOT / "experiment/prototypes").glob("native_lossless*")),
            ]
        },
        "harness_hashes": {
            name: {
                str(p.relative_to(package)): digest(p)
                for p in sorted((package / "test").rglob("*"))
                if p.is_file()
            }
            for name, package in packages.items()
        },
        "order": [],
        "runs": [],
    }
    with tempfile.TemporaryDirectory(prefix="blueprint-final-inputs-") as directory:
        for target in ("erlang", "javascript"):
            for fixture, kind, source in fixtures():
                selected = (
                    ["strict", "plain_native", "mitigated_native", "final"]
                    if target == "erlang"
                    else ["strict", "plain_native", "final"]
                )
                operation = "value" if fixture.startswith("value_") else "typed"
                if operation == "value":
                    selected = ["strict", "final"]
                elif kind == "exact_numbers":
                    selected.remove("plain_native")
                path = Path(directory) / (fixture + ".json")
                path.write_text(source)
                settings = {
                    "SELECTIVE_CASE": kind,
                    "BLUEPRINT_PARSER_OPERATION": operation,
                    "BLUEPRINT_PARSER_INPUT": str(path),
                    "BLUEPRINT_PARSER_ITERATIONS": str(
                        max(1, min(200, 200000 // len(source.encode())))
                    ),
                }
                # All variants must produce identical codec-encoded result text on this fixture.
                expected = None
                rows = {}
                for variant in selected:
                    package, backend = variant_config[variant]
                    encoded, _ = run(
                        package,
                        target,
                        dict(
                            settings,
                            BLUEPRINT_PARSER_BACKEND=backend,
                            BLUEPRINT_PARSER_MODE="result",
                        ),
                    )
                    assert isinstance(encoded, str)
                    if expected is None:
                        expected = encoded
                    assert encoded == expected, (
                        target,
                        fixture,
                        variant,
                        "typed result mismatch",
                    )
                    row = {
                        "target": target,
                        "fixture": fixture,
                        "kind": kind,
                        "operation": operation,
                        "variant": variant,
                        "bytes": len(source.encode()),
                        "input_sha256": hashlib.sha256(source.encode()).hexdigest(),
                        "result_sha256": hashlib.sha256(encoded.encode()).hexdigest(),
                        "iterations_per_batch": int(
                            settings["BLUEPRINT_PARSER_ITERATIONS"]
                        ),
                        "trials": [],
                    }
                    rows[variant] = row
                    data["runs"].append(row)
                trial_count = (
                    (args.trials + len(selected) - 1) // len(selected)
                ) * len(selected)
                for trial in range(trial_count):
                    shift = trial % len(selected)
                    order = selected[shift:] + selected[:shift]
                    data["order"].append(
                        {
                            "target": target,
                            "fixture": fixture,
                            "trial": trial,
                            "variants": order,
                        }
                    )
                    for variant in order:
                        package, backend = variant_config[variant]
                        env = dict(settings, BLUEPRINT_PARSER_BACKEND=backend)
                        samples, _ = run(
                            package, target, dict(env, BLUEPRINT_PARSER_MODE="timing")
                        )
                        memory, rss = run(
                            package, target, dict(env, BLUEPRINT_PARSER_MODE="memory")
                        )
                        rows[variant]["trials"].append(
                            {
                                "samples_ns": samples,
                                "median_ns": statistics.median(samples),
                                "memory": memory,
                                "peak_rss_bytes": rss,
                            }
                        )
                        args.output.write_text(json.dumps(data, indent=2) + "\n")
                for variant, row in rows.items():
                    medians = [trial["median_ns"] for trial in row["trials"]]
                    row.update(
                        median_ns=statistics.median(medians),
                        vm_median_range_ns=[min(medians), max(medians)],
                        median_peak_rss_bytes=statistics.median(
                            trial["peak_rss_bytes"] for trial in row["trials"]
                        ),
                    )
                    print(
                        target,
                        fixture,
                        variant,
                        round(row["median_ns"] / 1000, 3),
                        "us",
                        round(row["median_peak_rss_bytes"] / 1048576, 2),
                        "MiB",
                        flush=True,
                    )
                args.output.write_text(json.dumps(data, indent=2) + "\n")
    for name, package in packages.items():
        assert hashes(package) == data["source_hashes"][name]
    assert hashes(ROOT) == data["source_hashes"]["final"], (
        "Current production source changed during measurement"
    )
    data["source_hashes_verified_unchanged"] = True
    args.output.write_text(json.dumps(data, indent=2) + "\n")


if __name__ == "__main__":
    main()
