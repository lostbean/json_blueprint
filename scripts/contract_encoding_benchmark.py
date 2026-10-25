#!/usr/bin/env python3
"""Capture observational contract encoding timings; run inside nix develop."""

import argparse
from collections import defaultdict
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess


ROOT = Path(__file__).resolve().parent.parent
MODULE = "contract_encoding_bench_test"


def command(*args, cwd=ROOT, env=None):
    return subprocess.check_output(args, cwd=cwd, env=env, text=True).strip()


def source_hashes():
    paths = []
    for directory in ("src", "test"):
        paths.extend(
            path
            for path in (ROOT / directory).rglob("*")
            if path.is_file() and path.suffix in (".gleam", ".erl", ".mjs")
        )
    paths.extend(
        ROOT / path
        for path in (
            "flake.lock",
            "gleam.toml",
            "manifest.toml",
            "scripts/contract_encoding_benchmark.py",
        )
    )
    return {
        str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(paths)
    }


def summarize(samples):
    groups = defaultdict(lambda: defaultdict(list))
    for sample in samples:
        key = (sample["target"], sample["case"], sample["operation"], sample["outcome"])
        groups[key][sample["trial"]].append(sample["elapsed_ns"] / sample["iterations"])
    summaries = []
    for (target, case, operation, outcome), trials in sorted(groups.items()):
        medians = [statistics.median(values) for _, values in sorted(trials.items())]
        batches = [value for values in trials.values() for value in values]
        summaries.append(
            {
                "target": target,
                "case": case,
                "operation": operation,
                "outcome": outcome,
                "median_ns": statistics.median(medians),
                "trial_median_min_ns": min(medians),
                "trial_median_max_ns": max(medians),
                "batch_min_ns": min(batches),
                "batch_max_ns": max(batches),
                "trial_medians_ns": medians,
            }
        )
    return summaries


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--trials", type=int, default=3)
    args = parser.parse_args()
    if args.trials < 1:
        parser.error("--trials must be positive")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    environment = dict(os.environ, ERL_FLAGS="+S 1:1")
    versions = {
        "gleam": command("gleam", "--version"),
        "erlang": command(
            "erl",
            "+S",
            "1:1",
            "-noshell",
            "-eval",
            'io:format("~s", [erlang:system_info(system_version)]), halt().',
        ),
        "node": command("node", "--version"),
        "python": platform.python_version(),
    }
    hashes = source_hashes()
    provenance = {
        "started_utc": datetime.now(timezone.utc).isoformat(),
        "head": command("git", "rev-parse", "HEAD"),
        "git_status": command("git", "status", "--porcelain"),
        "versions": versions,
        "platform": platform.platform(),
        "cpu": json.loads(command("lscpu", "--json")),
        "cpu_affinity": sorted(os.sched_getaffinity(0)),
        "erlang_flags": environment["ERL_FLAGS"],
        "node_options": os.environ.get("NODE_OPTIONS", ""),
        "trials": args.trials,
        "batches_per_trial": 7,
        "source_sha256": hashes,
        "source_manifest_sha256": hashlib.sha256(
            json.dumps(hashes, sort_keys=True).encode()
        ).hexdigest(),
    }
    (output / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    samples = []
    for target in ("erlang", "javascript"):
        build = subprocess.run(
            ["gleam", "build", "--target", target, "--warnings-as-errors"],
            cwd=ROOT,
            env=environment,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        (output / f"{target}-build.log").write_text(build.stdout)
        build.check_returncode()
        for trial in range(1, args.trials + 1):
            print(f"{target} trial {trial}/{args.trials}", flush=True)
            result = subprocess.run(
                ["gleam", "run", "--target", target, "-m", MODULE],
                cwd=ROOT,
                env=environment,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
                timeout=600,
            )
            (output / f"{target}-{trial}.log").write_text(result.stdout)
            result.check_returncode()
            for line in result.stdout.splitlines():
                if line.startswith('{"case":'):
                    samples.append(dict(json.loads(line), target=target, trial=trial))
    if source_hashes() != hashes:
        raise RuntimeError("Measured source changed during benchmark; discard this run")
    (output / "samples.json").write_text(json.dumps(samples, indent=2) + "\n")
    (output / "summary.json").write_text(
        json.dumps(summarize(samples), indent=2) + "\n"
    )
    print(f"Saved {len(samples)} timed batches to {output}")


if __name__ == "__main__":
    main()
