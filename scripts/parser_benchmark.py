"""Fresh-process parser timings and whole-process peak RSS; never a speed gate."""

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent


@dataclass(frozen=True)
class Fixture:
    name: str
    text: str
    accepted: bool = True


def fixtures() -> list[Fixture]:
    compact = lambda item: json.dumps(item, ensure_ascii=True, separators=(",", ":"))
    dense = "[" + ",".join(["0"] * 262_143) + "]"
    return [
        Fixture("baseline_null", "null"),
        Fixture("small_record", compact({"id": 42, "name": "Ada", "active": True})),
        *[
            Fixture(f"object_{width}", compact({f"k{i}": i for i in range(width)}))
            for width in (10, 100, 500)
        ],
        Fixture("dense_10000", "[" + ",".join(["0"] * 10_000) + "]"),
        Fixture("dense_value_limit", dense),
        Fixture("escaped_unicode", compact(['雪 🚀\\"\n' * 10] * 100)),
        Fixture("decimals_1000", "[" + ",".join(["123.456789012345"] * 1000) + "]"),
        Fixture("reject_early", "?" + dense[1:], False),
        Fixture("reject_late", dense[:-1] + ",?]", False),
    ]


def representative_fixtures() -> list[Fixture]:
    """Application-shaped fixtures, not a measured production distribution."""
    compact = lambda item: json.dumps(item, ensure_ascii=False, separators=(",", ":"))
    record = {
        "id": 42,
        "name": "Ada Lovelace",
        "active": True,
        "email": "ada@example.test",
        "roles": ["reader", "editor"],
        "address": {"city": "São Paulo", "country": "BR"},
        "note": None,
        "score": 12.5,
    }
    schema = {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "type": "object",
        "additionalProperties": False,
        "required": ["id", "name", "active"],
        "properties": {
            "id": {"type": "integer", "minimum": 0},
            "name": {"type": "string"},
            "active": {"type": "boolean"},
            "tags": {"type": "array", "items": {"enum": ["reader", "editor"]}},
            "note": {"anyOf": [{"type": "null"}, {"type": "string"}]},
        },
    }
    return [
        Fixture("record", compact(record)),
        Fixture(
            "response_50",
            compact({"items": [record | {"id": i} for i in range(50)], "next": None}),
        ),
        Fixture(
            "tagged_event",
            compact(
                {
                    "tag": "updated",
                    "value": {
                        "user": record,
                        "changes": ["name", "address"],
                        "version": 3,
                    },
                }
            ),
        ),
        Fixture(
            "text_plain",
            compact(
                {
                    "id": 42,
                    "text": "A typical paragraph with ordinary words and punctuation. "
                    * 200,
                }
            ),
        ),
        Fixture(
            "text_escaped",
            compact(
                {
                    "id": 42,
                    "text": 'A paragraph with a "quotation", a line break.\n' * 200,
                }
            ),
        ),
        Fixture(
            "text_unicode", compact({"id": 42, "text": "Olá, 世界 — café 👋🏽. " * 200})
        ),
        Fixture("schema_document", compact(schema)),
    ]


def command_output(command: list[str]) -> str:
    return subprocess.check_output(command, cwd=ROOT, text=True).strip()


def runtime_command(target: str) -> list[str]:
    if target == "javascript":
        return [
            "node",
            "--input-type=module",
            "-e",
            "import { main } from './build/dev/javascript/json_blueprint/parser_benchmark_runner.mjs'; main();",
        ]
    return [
        "erl",
        "+S",
        "1:1",
        "-noshell",
        "-pa",
        *[str(path) for path in sorted((ROOT / "build/dev/erlang").glob("*/ebin"))],
        "-eval",
        "parser_benchmark_runner:main(), halt().",
    ]


def run_process(command: list[str], env: dict[str, str]) -> tuple[object, int]:
    # wait4 reports this child only; RUSAGE_CHILDREN would accumulate earlier VMs.
    with tempfile.TemporaryFile() as stdout, tempfile.TemporaryFile() as stderr:
        child = subprocess.Popen(
            command, cwd=ROOT, env=env, stdout=stdout, stderr=stderr
        )
        deadline = time.monotonic() + 60
        while True:
            pid, status, usage = os.wait4(child.pid, os.WNOHANG)
            if pid:
                break
            if time.monotonic() >= deadline:
                child.kill()
                _, status, _ = os.wait4(child.pid, 0)
                child.returncode = os.waitstatus_to_exitcode(status)
                raise TimeoutError(f"benchmark exceeded 60 seconds: {command[0]}")
            time.sleep(0.01)
        child.returncode = os.waitstatus_to_exitcode(status)
        stdout.seek(0)
        stderr.seek(0)
        output = stdout.read().decode()
        errors = stderr.read().decode()
        if child.returncode:
            raise RuntimeError(f"{command[0]} failed: {output}\n{errors}")
        peak_bytes = int(usage.ru_maxrss) * (
            1 if platform.system() == "Darwin" else 1024
        )
        return json.loads(output), peak_bytes


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--trials", type=int, default=3)
    parser.add_argument(
        "--workloads", choices=("stress", "representative"), default="stress"
    )
    args = parser.parse_args()
    if args.trials < 1 or platform.system() not in {"Darwin", "Linux"}:
        parser.error("positive trials and Darwin/Linux wait4 RSS accounting required")
    args.output.mkdir(parents=True, exist_ok=False)
    for target in ("erlang", "javascript"):
        subprocess.run(
            ["gleam", "build", "--target", target, "--warnings-as-errors"],
            cwd=ROOT,
            check=True,
        )
    cases = (
        representative_fixtures() if args.workloads == "representative" else fixtures()
    )
    files = sorted((ROOT / "src").rglob("*")) + [
        ROOT / "test/parser_benchmark_runner.gleam",
        ROOT / "test/parser_benchmark_ffi.erl",
        ROOT / "test/parser_benchmark_ffi.mjs",
        ROOT / "test/bench_ffi.erl",
        ROOT / "test/bench_ffi.mjs",
        Path(__file__).resolve(),
        ROOT / "gleam.toml",
        ROOT / "manifest.toml",
        ROOT / "flake.lock",
    ]
    provenance = {
        "captured_at_utc": datetime.now(timezone.utc).isoformat(),
        "revision": command_output(["git", "rev-parse", "HEAD"]),
        "dirty_status": command_output(["git", "status", "--porcelain"]),
        "host": platform.platform(),
        "machine": platform.machine(),
        "gleam": command_output(["gleam", "--version"]),
        "node": command_output(["node", "--version"]),
        "erlang": command_output(
            [
                "erl",
                "+S",
                "1:1",
                "-noshell",
                "-eval",
                'io:format("~s", [erlang:system_info(system_version)]), halt().',
            ]
        ),
        "trials": args.trials,
        "workloads": args.workloads,
        "commands": {
            target: runtime_command(target) for target in ("erlang", "javascript")
        },
        "method": "One fresh VM per target/backend/fixture/mode/trial; timing: one warmup batch and five timed batches; actual parse Result escapes to observable sink, with acceptance assertion. Memory: one parse only, total process high-water RSS includes runtime, input and result. No baseline subtraction, allocation or isolated peak-heap claim. Targets differ in representation and guarantees.",
        "source_sha256": {
            str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in files
            if path.is_file()
        },
        "fixture_sha256": {
            case.name: hashlib.sha256(case.text.encode()).hexdigest() for case in cases
        },
    }
    (args.output / "provenance.json").write_text(
        json.dumps(provenance, indent=2) + "\n"
    )
    rows = []
    with tempfile.TemporaryDirectory(prefix="blueprint-parser-bench-") as directory:
        for case in cases:
            path = Path(directory) / f"{case.name}.json"
            path.write_text(case.text)
            size = len(case.text.encode())
            iterations = max(1, min(200, 100_000 // max(size, 1)))
            for target in ("erlang", "javascript"):
                for backend in ("native", "strict"):
                    for mode in ("timing", "memory"):
                        for trial in range(args.trials):
                            env = os.environ | {
                                "BLUEPRINT_PARSER_INPUT": str(path),
                                "BLUEPRINT_PARSER_ACCEPTED": str(case.accepted).lower(),
                                "BLUEPRINT_PARSER_BACKEND": backend,
                                "BLUEPRINT_PARSER_MODE": mode,
                                "BLUEPRINT_PARSER_ITERATIONS": str(iterations),
                            }
                            output, peak = run_process(runtime_command(target), env)
                            if mode == "timing" and not (
                                isinstance(output, list)
                                and len(output) == 5
                                and all(
                                    type(item) is int and item >= 0 for item in output
                                )
                            ):
                                raise ValueError(f"invalid timing output: {output!r}")
                            if mode == "memory" and output != {
                                "accepted": case.accepted
                            }:
                                raise ValueError(f"invalid memory output: {output!r}")
                            rows.append(
                                {
                                    "fixture": case.name,
                                    "bytes": size,
                                    "target": target,
                                    "backend": backend,
                                    "mode": mode,
                                    "trial": trial + 1,
                                    "iterations": iterations if mode == "timing" else 1,
                                    "batch_ns_per_op": output
                                    if mode == "timing"
                                    else None,
                                    "peak_rss_bytes": peak
                                    if mode == "memory"
                                    else None,
                                }
                            )
                    print(f"measured {case.name} {target} {backend}", flush=True)
    for name, digest in provenance["source_sha256"].items():
        if hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != digest:
            raise RuntimeError(f"source changed during capture: {name}")
    (args.output / "results.json").write_text(json.dumps(rows, indent=2) + "\n")
    summary = []
    for case in cases:
        for target in ("erlang", "javascript"):
            for backend in ("native", "strict"):
                selected = [
                    row
                    for row in rows
                    if (row["fixture"], row["target"], row["backend"])
                    == (case.name, target, backend)
                ]
                times = [
                    statistics.median(row["batch_ns_per_op"])
                    for row in selected
                    if row["mode"] == "timing"
                ]
                peaks = [
                    row["peak_rss_bytes"] for row in selected if row["mode"] == "memory"
                ]
                summary.append(
                    {
                        "fixture": case.name,
                        "target": target,
                        "backend": backend,
                        "median_ns_per_op": statistics.median(times),
                        "vm_median_range_ns": [min(times), max(times)],
                        "median_peak_rss_bytes": statistics.median(peaks),
                        "peak_rss_range_bytes": [min(peaks), max(peaks)],
                    }
                )
    (args.output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")


if __name__ == "__main__":
    main()
