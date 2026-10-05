#!/bin/sh
# The repository gate: formatting, compiler warnings and the tests on both
# targets, for json_blueprint and for the json_blueprint_codegen package in
# codegen/. Each package's own build output is removed first, so a stale
# module cannot hide a missing one. The Python schema oracle then compares
# emitted schemas, decoders and contracts against Draft 2020-12.
set -eu
cd "$(dirname "$0")/.."

run() {
  output=$("$@" 2>&1) || {
    echo "$output"
    echo "gate: failed: $*" >&2
    exit 1
  }
  if echo "$output" | grep -q "^warning"; then
    echo "$output"
    echo "gate: warnings: $*" >&2
    exit 1
  fi
  echo "$output" | grep -E "passed|failures" || true
}

for package in . codegen; do
  echo "== $package"
  (
    cd "$package"
    rm -rf build/dev/erlang/json_blueprint build/dev/javascript/json_blueprint \
      build/dev/erlang/json_blueprint_codegen build/dev/javascript/json_blueprint_codegen
    gleam format --check src test
    run gleam build --target=erlang --warnings-as-errors
    run gleam build --target=javascript --warnings-as-errors
    run gleam test --target=erlang
    run gleam test --target=javascript
  )
done

python3 test/schema_check.py
