#!/bin/sh
# Compile and test application behavior on both
# targets, for json_blueprint and for the json_blueprint_codegen package in
# codegen/, then the compiled usage examples in examples/ (built with warnings
# as errors, tested on both targets and run once, so API drift fails the gate).
# Each package's own build output is removed first, so a stale
# module cannot hide a missing one. The Python schema oracle then compares
# emitted schemas, decoders and contracts against Draft 2020-12.
set -eu
cd "$(dirname "$0")/.."

codegen_work=$(mktemp -d "${TMPDIR:-/tmp}/blueprint-codegen.XXXXXX")
trap 'rm -rf "$codegen_work"' EXIT HUP INT TERM
find src test codegen/src codegen/test examples/src examples/test -name '*.erl' -type f -exec erlc -Werror -o "$codegen_work" {} +
cp -R codegen/src codegen/test codegen/gleam.toml codegen/manifest.toml "$codegen_work/"
python3 - "$codegen_work/gleam.toml" "$PWD" <<'PYCODE'
import json
from pathlib import Path
import sys
path = Path(sys.argv[1])
path.write_text(path.read_text().replace('path = ".."', 'path = ' + json.dumps(sys.argv[2])))
PYCODE
for package in . "$codegen_work"; do
  echo "== $package"
  (
    cd "$package"
    rm -rf build/dev/erlang/json_blueprint build/dev/javascript/json_blueprint \
      build/dev/erlang/json_blueprint_codegen build/dev/javascript/json_blueprint_codegen

    if [ "$package" = "$codegen_work" ]; then
      gleam run -m compiled_codec_runner
      gleam run -m schema_codegen_runner

    fi
    gleam build --target=erlang --warnings-as-errors
    gleam build --target=javascript --warnings-as-errors
    gleam test --target=erlang
    gleam test --target=javascript
  )
done

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
