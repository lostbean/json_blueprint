"""Fresh optimized-parser versus production native-codec adoption capture."""

import sys, os, json, statistics, hashlib, platform, tempfile, subprocess
from pathlib import Path

PRODUCTION = Path("/Users/edgar/.codex/worktrees/native-direct-decoding/json_blueprint")
BASELINE = Path("/tmp/blueprint-adoption-baseline")
sys.path.insert(0, str(PRODUCTION / "scripts"))
import parser_benchmark as b


def hashes(root):
    return {
        str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted((root / "src").rglob("*"))
        if p.is_file()
    }


def run(root, target, settings):
    b.ROOT = root
    command = [
        s.replace("parser_benchmark_runner", "native_lossless_runner")
        for s in b.runtime_command(target)
    ]
    if target == "javascript":
        command.insert(1, "--expose-gc")
    return b.run_process(command, dict(os.environ, **settings))


compact = lambda x: json.dumps(x, separators=(",", ":"), ensure_ascii=False)
records = [{"id": i, "name": "Ada Lovelace", "active": True} for i in range(50)]
fixtures = [
    ("small_record", "record", compact(records[0])),
    ("response_50", "response", compact({"items": records})),
    ("ints_10000", "ints", compact([0] * 10000)),
    ("ints_limit", "ints", compact([0] * 262143)),
    ("decimals_1000", "floats", "[" + ",".join(["0.10000000000000001"] * 1000) + "]"),
    (
        "exact_numbers_1000",
        "exact_numbers",
        "[" + ",".join(["0.10000000000000001"] * 1000) + "]",
    ),
]
output = PRODUCTION / "experiment/adoption-results.json"
assert not output.exists(), "Refusing to replace capture"
results = {
    "platform": platform.platform(),
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
    "baseline": str(BASELINE),
    "production": str(PRODUCTION),
    "source_hashes": {
        name: hashes(root)
        for name, root in [("baseline", BASELINE), ("production", PRODUCTION)]
    },
    "runner_sha256": hashlib.sha256(
        (PRODUCTION / "test/native_lossless_runner.gleam").read_bytes()
    ).hexdigest(),
    "method": "Baseline first, then production. Three fresh VMs per workload/target/mode, five timed batches after warmup. Both use strict backend dispatch to codec.decode_json. Memory retains the consumed typed result, forces GC, reports process/VM memory (Erlang) or process.memoryUsage (Node), plus total-process high-water RSS from wait4. RSS is not allocated bytes. Erlang verifies against the lossless experiment; JS timed runs assert decode success and portable codec tests supply semantic evidence.",
    "runs": [],
}
with tempfile.TemporaryDirectory(prefix="blueprint-adoption-input-") as tmp:
    for implementation, root in [("baseline", BASELINE), ("production", PRODUCTION)]:
        for target in ["erlang", "javascript"]:
            selected = fixtures if target == "erlang" else fixtures[:3]
            for name, kind, source in selected:
                path = Path(tmp) / "input.json"
                path.write_text(source)
                settings = {
                    "SELECTIVE_CASE": kind,
                    "BLUEPRINT_PARSER_BACKEND": "strict",
                    "BLUEPRINT_PARSER_INPUT": str(path),
                    "BLUEPRINT_PARSER_ITERATIONS": str(
                        max(1, min(200, 200000 // len(source)))
                    ),
                }
                if target == "erlang":
                    run(root, target, dict(settings, BLUEPRINT_PARSER_MODE="verify"))
                trials = []
                for index in range(3):
                    samples, _ = run(
                        root, target, dict(settings, BLUEPRINT_PARSER_MODE="timing")
                    )
                    snapshot, rss = run(
                        root, target, dict(settings, BLUEPRINT_PARSER_MODE="memory")
                    )
                    trials.append(
                        {
                            "samples_ns": samples,
                            "median_ns": statistics.median(samples),
                            "memory": snapshot,
                            "peak_rss_bytes": rss,
                        }
                    )
                medians = [trial["median_ns"] for trial in trials]
                row = {
                    "implementation": implementation,
                    "target": target,
                    "fixture": name,
                    "bytes": len(source.encode()),
                    "input_sha256": hashlib.sha256(source.encode()).hexdigest(),
                    "iterations_per_batch": int(
                        settings["BLUEPRINT_PARSER_ITERATIONS"]
                    ),
                    "median_ns": statistics.median(medians),
                    "vm_median_range_ns": [min(medians), max(medians)],
                    "trials": trials,
                }
                results["runs"].append(row)
                print(
                    implementation,
                    target,
                    name,
                    round(row["median_ns"] / 1000, 3),
                    "us",
                    round(
                        statistics.median(t["peak_rss_bytes"] for t in trials)
                        / 1048576,
                        2,
                    ),
                    "MiB",
                    flush=True,
                )
                output.write_text(json.dumps(results, indent=2) + "\n")
    for name, root in [("baseline", BASELINE), ("production", PRODUCTION)]:
        assert results["source_hashes"][name] == hashes(root), (
            f"{name} source changed during capture"
        )
results["source_hashes_verified_unchanged"] = True
output.write_text(json.dumps(results, indent=2) + "\n")
