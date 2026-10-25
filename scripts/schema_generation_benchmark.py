#!/usr/bin/env python3
"""Capture bounded schema-consumer CPU and allocation evidence in the Nix shell."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess

ROOT = Path(__file__).resolve().parent.parent
CONSUMER = ROOT / "examples/codegen"


def run(command, cwd, output, env):
    result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True)
    output.with_suffix(".stdout").write_text(result.stdout)
    output.with_suffix(".stderr").write_text(result.stderr)
    if result.returncode:
        raise RuntimeError(f"Failed: {command}; see {output}.stderr")
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    env = dict(os.environ, ERL_FLAGS="+S 1:1")
    versions = {}
    for name, command in {
        "gleam": ["gleam", "--version"],
        "node": ["node", "--version"],
        "erlang": [
            "erl",
            "-noshell",
            "-eval",
            'io:format("OTP ~s ERTS ~s word bytes ~p~n", [erlang:system_info(otp_release), erlang:system_info(version), erlang:system_info(wordsize)]), halt().',
        ],
        "revision": ["git", "rev-parse", "HEAD"],
    }.items():
        versions[name] = run(command, ROOT, output / name, env).strip()
    versions["platform"] = platform.platform()
    versions["cpu_count"] = os.cpu_count()
    versions["erlang_flags"] = env["ERL_FLAGS"]
    (output / "environment.json").write_text(json.dumps(versions, indent=2) + "\n")
    inputs = {}
    for source_root in [ROOT / "src", CONSUMER]:
        for path in sorted(source_root.rglob("*")):
            if (
                path.is_file()
                and "build" not in path.parts
                and path.suffix in {".gleam", ".erl", ".mjs", ".json", ".toml"}
            ):
                inputs[str(path.relative_to(ROOT))] = hashlib.sha256(
                    path.read_bytes()
                ).hexdigest()
    own_path = Path(__file__).resolve()
    inputs[str(own_path.relative_to(ROOT))] = hashlib.sha256(
        own_path.read_bytes()
    ).hexdigest()
    (output / "inputs.sha256.json").write_text(json.dumps(inputs, indent=2) + "\n")
    for project, cwd in [("consumer", CONSUMER), ("generate", CONSUMER / "generate")]:
        for target in ["erlang", "javascript"]:
            run(
                ["gleam", "build", f"--target={target}", "--warnings-as-errors"],
                cwd,
                output / f"build-{project}-{target}",
                env,
            )
    rows = []
    for trial in range(1, 4):
        trial_env = dict(env, BENCH_REVERSE="1" if trial == 2 else "0")
        for target in ["erlang", "javascript"]:
            for mode, module, cwd, package in [
                ("cpu", "schema_bench", CONSUMER, "schema_order_consumer"),
                (
                    "allocation",
                    "schema_allocation_bench",
                    CONSUMER,
                    "schema_order_consumer",
                ),
                (
                    "generation",
                    "generation_bench",
                    CONSUMER / "generate",
                    "schema_order_generate",
                ),
            ]:
                if target == "erlang":
                    command = ["gleam", "run", "--target=erlang", "-m", module]
                else:
                    entry = f"./build/dev/javascript/{package}/{module}.mjs"
                    command = [
                        "node",
                        "--expose-gc",
                        "--input-type=module",
                        "-e",
                        f"const module = await import('{entry}'); await module.main();",
                    ]
                label = f"{mode}-{target}-{trial}"
                print(label, flush=True)
                stdout = run(command, cwd, output / label, trial_env)
                records = [
                    json.loads(line)
                    for line in stdout.splitlines()
                    if line.startswith("{")
                ]
                expected = 1 if mode == "generation" else 39
                if len(records) != expected:
                    raise RuntimeError(
                        f"{label}: expected {expected} rows, got {len(records)}"
                    )
                rows.extend(
                    dict(trial=trial, target=target, mode=mode, **record)
                    for record in records
                )
    (output / "results.json").write_text(json.dumps(rows, indent=2) + "\n")


if __name__ == "__main__":
    main()
