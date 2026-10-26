"""THROWAWAY: does native JS parsing with strict admission beat the current parser?

One command in nix develop: python3 experiment/js-hybrid-benchmark.py --work
/tmp/blueprint-js-hybrid-new --output /tmp/blueprint-js-hybrid-new.json
Use --prepare-baseline while implementation is changing; --prepare-only snapshots
and builds both candidates without timing. --capture uses the frozen snapshots.
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
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parent.parent
BASE = "2c6df6148c9357b03041be2c95a3a46a6694120d"
sys.path.insert(0, str(ROOT / "scripts"))
import parser_benchmark as shared


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def hashes(path):
    return {
        str(p.relative_to(path)): digest(p)
        for p in sorted((path / "src").rglob("*"))
        if p.is_file()
    }


def prepare_package(work, name):
    package = work / name
    if package.exists():
        raise FileExistsError(package)
    package.mkdir(parents=True)
    if name == "current":
        archive = subprocess.check_output(
            ["git", "archive", BASE, "src", "gleam.toml", "manifest.toml"],
            cwd=ROOT,
            env={
                key: value
                for key, value in os.environ.items()
                if key not in ("DEVELOPER_DIR", "SDKROOT")
            },
        )
        with tarfile.open(fileobj=io.BytesIO(archive)) as source:
            for entry in source.getmembers():
                assert (
                    not entry.name.startswith("/")
                    and ".." not in Path(entry.name).parts
                )
            source.extractall(package, filter="data")
    else:
        shutil.copytree(ROOT / "src", package / "src")
        for name in ("gleam.toml", "manifest.toml"):
            shutil.copy2(ROOT / name, package / name)
    (package / "test").mkdir()
    for name in (
        "bench_ffi.mjs",
        "parser_benchmark_ffi.mjs",
        "host_string_test_ffi.mjs",
    ):
        shutil.copy2(ROOT / "test" / name, package / "test" / name)
    for name in (
        "native_direct.gleam",
        "native_direct_ffi.mjs",
        "native_lossless.gleam",
    ):
        shutil.copy2(ROOT / "experiment/prototypes" / name, package / "test" / name)
    shutil.copy2(
        ROOT / "experiment/js-hybrid-runner.gleam",
        package / "test/js_hybrid_benchmark_runner.gleam",
    )
    shutil.copy2(
        ROOT / "experiment/js-hybrid-bench-ffi.mjs",
        package / "test/js_hybrid_bench_ffi.mjs",
    )
    subprocess.run(
        ["gleam", "build", "--target", "javascript", "--warnings-as-errors"],
        cwd=package,
        check=True,
    )


def fixtures():
    compact = lambda x: json.dumps(x, separators=(",", ":"), ensure_ascii=False)
    records = [{"id": i, "name": "Ada Lovelace", "active": True} for i in range(50)]
    decimals = "[" + ",".join(["0.10000000000000001"] * 1000) + "]"
    cases = [
        ("small_record", "record", compact(records[0]), "typed"),
        ("response_50", "response", compact({"items": records}), "typed"),
        ("ints_10000", "ints", compact([0] * 10000), "typed"),
        ("ints_262143", "ints", compact([0] * 262143), "typed"),
        ("decimals_float_1000", "floats", decimals, "typed"),
        ("decimals_exact_1000", "exact_numbers", decimals, "typed"),
        (
            "optional_51",
            "optional",
            compact([{}, {"note": None}, {"note": "hello"}] * 17),
            "typed",
        ),
        (
            "unicode_strings",
            "strings",
            compact(["Olá, 世界 — café 👋🏽. " * 20] * 50),
            "typed",
        ),
        (
            "text_records_50",
            "records",
            compact([dict(x, name="Ordinary paragraph. " * 200) for x in records]),
            "typed",
        ),
        (
            "nested_arrays",
            "nested",
            compact([[i, i + 1, i + 2] for i in range(100)]),
            "typed",
        ),
    ]
    cases += [
        ("value_" + name, kind, source, "value")
        for name, kind, source, _ in list(cases)
        if name in ("response_50", "ints_262143", "decimals_exact_1000")
    ]
    cases += [
        ("custom_response_50", "custom_response", compact({"items": records}), "typed"),
        ("custom_ints_10000", "custom_ints", compact([0] * 10000), "typed"),
    ]
    cases += [
        ("value_" + f.name, "", f.text, "value")
        for f in shared.representative_fixtures()
        if f.name in ("tagged_event", "schema_document")
    ]
    return cases


def run(package, env):
    shared.ROOT = package
    command = [
        part.replace("parser_benchmark_runner", "js_hybrid_benchmark_runner")
        for part in shared.runtime_command("javascript")
    ]
    command.insert(1, "--expose-gc")
    return shared.run_process(command, dict(os.environ, **env))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument(
        "--output", type=Path, default=ROOT / "experiment/js-hybrid-results.json"
    )
    parser.add_argument("--prepare-baseline", action="store_true")
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--capture", action="store_true")
    parser.add_argument("--trials", type=int, default=6)
    args = parser.parse_args()
    if args.prepare_baseline:
        prepare_package(args.work, "current")
        return
    if not args.capture:
        if not (args.work / "current").exists():
            prepare_package(args.work, "current")
        prepare_package(args.work, "hybrid")
    if args.prepare_only:
        return
    assert not args.output.exists(), "Refusing to overwrite captured evidence"
    assert args.trials >= 4
    packages = {name: args.work / name for name in ("current", "hybrid")}
    assert hashes(packages["hybrid"]) == hashes(ROOT), "Hybrid snapshot is stale"
    feature_support = {
        name: json.loads(
            subprocess.check_output(
                [
                    "node",
                    "--input-type=module",
                    "-e",
                    "import {supported} from './build/dev/javascript/json_blueprint/json/blueprint/internal/native.mjs'; console.log(JSON.stringify(supported()));",
                ],
                cwd=package,
                text=True,
            )
        )
        for name, package in packages.items()
    }
    assert feature_support == {"current": False, "hybrid": True}, feature_support
    source_hashes = {name: hashes(path) for name, path in packages.items()}
    support_paths = [
        Path(__file__),
        ROOT / "experiment/js-hybrid-runner.gleam",
        ROOT / "experiment/js-hybrid-bench-ffi.mjs",
        ROOT / "scripts/parser_benchmark.py",
        ROOT / "gleam.toml",
        ROOT / "manifest.toml",
    ]
    support_hashes = {str(p.relative_to(ROOT)): digest(p) for p in support_paths}
    data = {
        "captured_at_utc": datetime.now(timezone.utc).isoformat(),
        "baseline_revision": BASE,
        "host": platform.platform(),
        "versions": {
            name: subprocess.check_output(command, text=True).strip()
            for name, command in [
                ("node", ["node", "--version"]),
                ("gleam", ["gleam", "--version"]),
                ("python", [sys.executable, "--version"]),
            ]
        },
        "method": "Fresh paired VMs, rotating implementation order for six trials. Each timing VM warms up then measures five batches, observable escaped result. Separate fresh memory VMs force GC before and after one decode. Peak RSS via wait4 is entire process, not allocation size. Before/after heap delta includes the retained result but may include lazy runtime allocations. Codec construction, input loading, compilation and equality preflight excluded from timing. Node --expose-gc; no CPU affinity/frequency controls. Plain native deliberately lacks strict duplicate/precision guarantees; only a cost reference.",
        "native_feature_support": feature_support,
        "source_hashes": source_hashes,
        "support_hashes": support_hashes,
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
    with tempfile.TemporaryDirectory(prefix="blueprint-js-hybrid-inputs-") as directory:
        for fixture, kind, source, operation in fixtures():
            selected = ["current", "hybrid"]
            if operation == "typed" and kind not in (
                "exact_numbers",
                "custom_response",
                "custom_ints",
            ):
                selected.append("plain_native")
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
            expected = None
            rows = {}
            for variant in selected:
                package = packages["current" if variant == "plain_native" else variant]
                backend = "native" if variant == "plain_native" else "strict"
                encoded, _ = run(
                    package,
                    dict(
                        settings,
                        BLUEPRINT_PARSER_BACKEND=backend,
                        BLUEPRINT_PARSER_MODE="result",
                    ),
                )
                assert isinstance(encoded, str)
                if expected is None:
                    expected = encoded
                assert encoded == expected, (fixture, variant, "result mismatch")
                row = {
                    "target": "javascript",
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
            trial_count = ((args.trials + len(selected) - 1) // len(selected)) * len(
                selected
            )
            for trial in range(trial_count):
                shift = trial % len(selected)
                order = selected[shift:] + selected[:shift]
                data["order"].append(
                    {"fixture": fixture, "trial": trial, "variants": order}
                )
                for variant in order:
                    package = packages[
                        "current" if variant == "plain_native" else variant
                    ]
                    env = dict(
                        settings,
                        BLUEPRINT_PARSER_BACKEND="native"
                        if variant == "plain_native"
                        else "strict",
                    )
                    samples, _ = run(package, dict(env, BLUEPRINT_PARSER_MODE="timing"))
                    memory, rss = run(
                        package, dict(env, BLUEPRINT_PARSER_MODE="memory")
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
                medians = [x["median_ns"] for x in row["trials"]]
                row.update(
                    median_ns=statistics.median(medians),
                    vm_median_range_ns=[min(medians), max(medians)],
                    median_peak_rss_bytes=statistics.median(
                        x["peak_rss_bytes"] for x in row["trials"]
                    ),
                    median_retained_heap_delta_bytes=statistics.median(
                        x["memory"]["delta"]["heapUsed"] for x in row["trials"]
                    ),
                    median_retained_heap_bytes=statistics.median(
                        x["memory"]["after"]["heapUsed"] for x in row["trials"]
                    ),
                )
                print(
                    fixture,
                    variant,
                    round(row["median_ns"] / 1000, 3),
                    "us",
                    round(row["median_peak_rss_bytes"] / 1048576, 2),
                    "MiB",
                    flush=True,
                )
            args.output.write_text(json.dumps(data, indent=2) + "\n")
    assert {name: hashes(path) for name, path in packages.items()} == source_hashes
    assert hashes(ROOT) == source_hashes["hybrid"]
    assert {
        str(p.relative_to(ROOT)): digest(p) for p in support_paths
    } == support_hashes
    data["source_and_support_hashes_verified_unchanged"] = True
    args.output.write_text(json.dumps(data, indent=2) + "\n")


if __name__ == "__main__":
    main()
