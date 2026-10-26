#!/usr/bin/env python3
"""THROWAWAY specialized generation: matched decoding timing + whole-VM peak RSS."""

import argparse, hashlib, json, os, platform, statistics, subprocess, tempfile, time
from pathlib import Path


def run(root, target, env):
    if target == "javascript":
        cmd = [
            "node",
            "--input-type=module",
            "-e",
            "import {main} from './build/dev/javascript/json_blueprint/prototype_bench.mjs'; main();",
        ]
    else:
        cmd = [
            "erl",
            "+S",
            "1:1",
            "-noshell",
            "-pa",
            *[str(p) for p in sorted((root / "build/dev/erlang").glob("*/ebin"))],
            "-eval",
            "prototype_bench:main(), halt().",
        ]
    with tempfile.TemporaryFile() as stdout, tempfile.TemporaryFile() as stderr:
        child = subprocess.Popen(cmd, cwd=root, env=env, stdout=stdout, stderr=stderr)
        deadline = time.monotonic() + 60
        while True:
            pid, status, usage = os.wait4(child.pid, os.WNOHANG)
            if pid:
                break
            if time.monotonic() > deadline:
                child.kill()
                os.wait4(child.pid, 0)
                raise TimeoutError(str(cmd))
            time.sleep(0.01)
        child.returncode = os.waitstatus_to_exitcode(status)
        stdout.seek(0)
        stderr.seek(0)
        output = stdout.read().decode()
        errors = stderr.read().decode()
        if child.returncode:
            raise RuntimeError(f"{root} {target}: {output}\n{errors}")
        return json.loads(output), usage.ru_maxrss * (
            1 if platform.system() == "Darwin" else 1024
        )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--baseline", type=Path, required=True)
    ap.add_argument("--candidate", type=Path, required=True)
    ap.add_argument("--output", type=Path, required=True)
    ap.add_argument("--build", action="store_true")
    a = ap.parse_args()
    a.output.mkdir(exist_ok=False, parents=True)
    roots = {"baseline": a.baseline, "candidate": a.candidate}
    if a.build:
        for root in roots.values():
            for target in ("erlang", "javascript"):
                subprocess.run(
                    ["gleam", "build", "--target", target, "--warnings-as-errors"],
                    cwd=root,
                    check=True,
                )
    row = {
        "order_id": 42,
        'items_"list"': [["apple", 2], ["雪", 3]],
        "customer\n\r\f\t\\note": "hello",
        "type": True,
        "status": "pending",
    }
    fixtures = {}
    for count in (50, 5000):
        p = a.output / f"response{count}.json"
        p.write_text(
            json.dumps([row] * count, ensure_ascii=False, separators=(",", ":"))
        )
        assert p.stat().st_size < 1048576
        fixtures[count] = p.resolve()
    sources = [
        "src/json/blueprint/codegen.gleam",
        "src/json/blueprint/codec.gleam",
        "src/json/blueprint/internal/generated.gleam",
        "test/generated/order_codec.gleam",
        "test/prototype_bench.gleam",
        "flake.lock",
    ]
    hashes = {
        v: {f: hashlib.sha256((r / f).read_bytes()).hexdigest() for f in sources}
        for v, r in roots.items()
    }
    results = []
    for trial in range(3):
        # Alternate candidate order by trial to reduce fixed-order drift.
        for variant in (
            ["baseline", "candidate"] if trial % 2 == 0 else ["candidate", "baseline"]
        ):
            root = roots[variant]
            for target in ("erlang", "javascript"):
                for count, path in fixtures.items():
                    for decoder in ("generated", "runtime", "vanilla"):
                        for mode in ("memory", "timing"):
                            env = dict(
                                os.environ,
                                PROTOTYPE_INPUT=str(path),
                                PROTOTYPE_COUNT=str(count),
                                PROTOTYPE_DECODER=decoder,
                                PROTOTYPE_MODE=mode,
                                PROTOTYPE_ITERATIONS="100" if count == 50 else "3",
                            )
                            output, rss = run(root, target, env)
                            if mode == "memory":
                                assert output == {"accepted": True}
                            else:
                                assert len(output["samples_ns"]) == 5
                            results.append(
                                dict(
                                    variant=variant,
                                    target=target,
                                    count=count,
                                    decoder=decoder,
                                    mode=mode,
                                    trial=trial,
                                    input_bytes=path.stat().st_size,
                                    peak_rss_bytes=rss if mode == "memory" else None,
                                    **output,
                                )
                            )
    summary = []
    for variant in roots:
        for target in ("erlang", "javascript"):
            for count in fixtures:
                for decoder in ("generated", "runtime", "vanilla"):
                    selected = [
                        r
                        for r in results
                        if r["variant"] == variant
                        and r["target"] == target
                        and r["count"] == count
                        and r["decoder"] == decoder
                    ]
                    timings = [
                        statistics.median(r["samples_ns"]) / 1000
                        for r in selected
                        if r["mode"] == "timing"
                    ]
                    memory = [
                        r["peak_rss_bytes"] / 1048576
                        for r in selected
                        if r["mode"] == "memory"
                    ]
                    summary.append(
                        dict(
                            variant=variant,
                            target=target,
                            count=count,
                            decoder=decoder,
                            median_us=statistics.median(timings),
                            timing_range_us=[min(timings), max(timings)],
                            peak_rss_mib=statistics.median(memory),
                            rss_range_mib=[min(memory), max(memory)],
                        )
                    )
    assert hashes == {
        v: {f: hashlib.sha256((r / f).read_bytes()).hexdigest() for f in sources}
        for v, r in roots.items()
    }, "source changed during capture"
    data = {
        "method": "Three fresh VMs per target/candidate/decoder/fixture/mode; alternating candidate order. Memory one complete decode only: whole-process high-water RSS includes runtime, module loading, source and retained typed result; no baseline subtraction or isolated heap claim. Timing one warmup batch plus five timed batches; median of VM medians. Codec construction outside timing. First record and list length asserted. Vanilla weaker admission guarantees, representable fixture only. Erlang +S1:1. No CPU pinning.",
        "source_sha256": hashes,
        "versions": {
            k: subprocess.check_output(v, text=True).strip()
            for k, v in {
                "gleam": ["gleam", "--version"],
                "node": ["node", "--version"],
            }.items()
        },
        "results": results,
        "summary": summary,
    }
    (a.output / "results.json").write_text(json.dumps(data, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
