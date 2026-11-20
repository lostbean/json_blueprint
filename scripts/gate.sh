#!/bin/sh
# Compile and test the runtime and source generators in one package on both
# targets, then the separate usage and schema-generation consumers.
# Each package's own build output is removed first, so a stale module cannot
# hide a missing one. Python oracles compare the finite schema and number cases.
set -eu
cd "$(dirname "$0")/.."

native_output=$(mktemp -d)
trap 'rm -rf "$native_output"' EXIT HUP INT TERM
erlang_sources="src test examples/src examples/test examples/codegen/src examples/codegen/test examples/codegen/generate/src"
# A consumer builds its path dependency's test modules too, so two Erlang
# modules with one name would shadow each other depending on code-path order.
duplicate_modules=$(find $erlang_sources -name '*.erl' -type f -exec basename {} \; | sort | uniq -d)
if [ -n "$duplicate_modules" ]; then
  echo "Erlang module names must be unique across packages: $duplicate_modules" >&2
  exit 1
fi
find $erlang_sources -name '*.erl' -type f -exec erlc -Werror -o "$native_output" {} +

echo "== json_blueprint"
rm -rf build/dev/erlang/json_blueprint build/dev/javascript/json_blueprint
gleam build --target=erlang --warnings-as-errors
gleam build --target=javascript --warnings-as-errors
gleam test --target=erlang
gleam test --target=javascript
node test/unsupported_runtime_check.mjs
node test/source_text_oracle_check.mjs

# Compile freshly regenerated typed and schema fixtures without modifying the
# committed fixtures used by the parity tests above.
generation_work="$native_output/generation"
mkdir "$generation_work"
cp -R src test gleam.toml manifest.toml "$generation_work/"
(
  cd "$generation_work"
  gleam run -m compiled_codec_runner
  gleam run -m schema_codegen_runner
  gleam build --target=erlang --warnings-as-errors
  gleam build --target=javascript --warnings-as-errors
)

echo "== examples"
(
  cd examples
  rm -rf build/dev/erlang/json_blueprint_examples build/dev/javascript/json_blueprint_examples

  gleam build --target=erlang --warnings-as-errors
  gleam build --target=javascript --warnings-as-errors
  gleam test --target=erlang
  gleam test --target=javascript
  gleam run --target=erlang >/dev/null
)

sh scripts/check-schema-consumer.sh

python3 test/schema_check.py
python3 test/schema_profile_check.py
python3 test/upstream_schema_check.py

python3 test/number_check.py

python3 test/parser_check.py

python3 test/copy_cost_coverage_check.py
