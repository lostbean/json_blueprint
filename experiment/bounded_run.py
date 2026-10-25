"""THROWAWAY. Run from nix develop: python3 experiment/run.py."""

import sys, os, json, tempfile, statistics, hashlib, platform, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(ROOT / "scripts"), str(ROOT / "test")]
import parser_benchmark as b

b.ROOT = ROOT


def command(target):
    cmd = [
        s.replace("parser_benchmark_runner", "native_bounded_runner")
        for s in b.runtime_command(target)
    ]
    if target == "javascript":
        cmd.insert(1, "--expose-gc")
    return cmd


def run(target, settings):
    return b.run_process(command(target), dict(os.environ, **settings))


with tempfile.TemporaryDirectory() as tmp:
    tmp = Path(tmp)
    results = {"platform": platform.platform(), "runs": []}
    for target in ["erlang"]:
        print(
            target,
            run(
                target,
                {"SELECTIVE_CASE": "check"},
            )[0],
            flush=True,
        )
    if "--check-only" in sys.argv:
        sys.exit(0)
    compact = lambda x: json.dumps(x, separators=(",", ":"), ensure_ascii=False)
    records = [{"id": i, "name": "Ada Lovelace", "active": True} for i in range(50)]
    fixtures = [
        ("small_record", "record", compact(records[0])),
        ("records_50", "records", compact(records)),
        ("response_50", "response", compact({"items": records})),
        ("ints_10000", "ints", compact([0] * 10000)),
        ("ints_limit", "ints", compact([0] * 262143)),
        ("nested_100x100", "nested", compact([[0] * 100 for _ in range(100)])),
        (
            "decimals_1000",
            "floats",
            "[" + ",".join(["0.10000000000000001"] * 1000) + "]",
        ),
        (
            "text_records_50",
            "records",
            compact([dict(x, name="Ordinary paragraph. " * 200) for x in records]),
        ),
    ]
    fixtures.extend(
        [
            (
                "optional_51",
                "optional",
                compact([{}, {"note": None}, {"note": "hello"}] * 17),
            ),
            (
                "unicode_strings",
                "strings",
                compact(["Olá, 世界 — café 👋🏽. " * 20] * 50),
            ),
            (
                "escaped_strings",
                "strings",
                compact(['A "quotation" and a newline.\n' * 20] * 50),
            ),
        ]
    )
    fixtures.append(
        (
            "exact_numbers_1000",
            "exact_numbers",
            "[" + ",".join(["0.10000000000000001"] * 1000) + "]",
        )
    )
    selected = (
        sys.argv[sys.argv.index("--fixture") + 1] if "--fixture" in sys.argv else None
    )
    if selected:
        fixtures = [fixture for fixture in fixtures if fixture[0] == selected]
        assert fixtures, selected
    output_name = (
        "experiment/bounded-results.json"
        if not selected
        else f"experiment/bounded-{selected}-results.json"
    )
    for target in ["erlang"]:
        for name, kind, source in fixtures:
            path = tmp / "input.json"
            path.write_text(source)
            settings = {
                "SELECTIVE_CASE": kind,
                "BLUEPRINT_PARSER_BACKEND": "strict",
                "BLUEPRINT_PARSER_INPUT": str(path),
                "BLUEPRINT_PARSER_ITERATIONS": str(
                    max(1, min(200, 200000 // len(source)))
                ),
            }
            run(target, dict(settings, BLUEPRINT_PARSER_MODE="verify"))
            for backend in (
                ["strict", "lossless", "bounded"]
                if kind == "exact_numbers"
                else ["strict", "native", "lossless", "bounded"]
            ):
                timings = []
                mem = []
                for vm in range(3):
                    samples, _ = run(
                        target,
                        dict(
                            settings,
                            BLUEPRINT_PARSER_BACKEND=backend,
                            BLUEPRINT_PARSER_MODE="timing",
                        ),
                    )
                    timings.extend(samples)
                    snapshot, rss = run(
                        target,
                        dict(
                            settings,
                            BLUEPRINT_PARSER_BACKEND=backend,
                            BLUEPRINT_PARSER_MODE="memory",
                        ),
                    )
                    mem.append(dict(snapshot, peak_rss=rss))
                row = dict(
                    target=target,
                    fixture=name,
                    backend=backend,
                    bytes=len(source.encode()),
                    median_ns=statistics.median(timings),
                    samples_ns=timings,
                    memory=mem,
                )
                results["runs"].append(row)
                print(
                    target,
                    name,
                    backend,
                    round(row["median_ns"] / 1000, 2),
                    "us",
                    round(statistics.median(x["peak_rss"] for x in mem) / 1048576, 2),
                    "MiB",
                    flush=True,
                )
                (ROOT / output_name).write_text(json.dumps(results, indent=2) + "\n")
