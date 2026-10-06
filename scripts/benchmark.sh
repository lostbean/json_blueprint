#!/bin/sh
# Observational timing only; the package gate owns semantic acceptance.
set -eu
cd "$(dirname "$0")/.."
output=${BLUEPRINT_BENCH_OUTPUT:-"$(pwd)/.ci-results/benchmarks-$(date -u +%Y%m%dT%H%M%SZ)-$$"}
mkdir -p "$(dirname "$output")"
mkdir "$output"
output=$(cd "$output" && pwd)
{
  git rev-parse HEAD
  git status --porcelain
  sha256sum flake.lock gleam.toml manifest.toml codegen/gleam.toml codegen/manifest.toml
  gleam --version
  erl +S 1:1 -noshell -eval 'io:format("Erlang/OTP ~s~n", [erlang:system_info(otp_release)]), halt().'
  node --version
  python3 --version
  python3 -c 'from importlib.metadata import version; print("jsonschema " + version("jsonschema"))'
  uname -s -m
} >"$output/provenance.txt"
for target in erlang javascript; do
  if (cd codegen && gleam run --target "$target" -m bench_test) >"$output/$target.log" 2>&1; then
    cat "$output/$target.log"
  else
    status=$?
    cat "$output/$target.log"
    exit "$status"
  fi
done
echo "Benchmark observations: $output"
