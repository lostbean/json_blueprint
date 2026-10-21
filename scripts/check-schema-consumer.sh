#!/bin/sh
# Run from the repository Nix shell. Generation is a development-only package.
set -eu
cd "$(dirname "$0")/.."
repository=$(pwd)
consumer="$repository/codegen/consumer"
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT HUP INT TERM
(
  cd "$consumer/generate"
  rm -rf build/dev/erlang/schema_order_generate build/dev/javascript/schema_order_generate

  gleam build --warnings-as-errors
  SCHEMA_OUTPUT="$output" gleam run -m generate_order
)

mkdir -p "$output/consumer"
cp -R "$consumer/src" "$consumer/test" "$consumer/schema" "$consumer/gleam.toml" "$consumer/manifest.toml" "$output/consumer/"
cp -R "$output/commerce" "$output/projection" "$output/consumer/src/"
python3 - "$output/consumer/gleam.toml" "$repository" <<'PYCODE'
import json
from pathlib import Path
import sys
path = Path(sys.argv[1])
path.write_text(path.read_text().replace('path = "../.."', 'path = ' + json.dumps(sys.argv[2])))
PYCODE
consumer="$output/consumer"
(
  cd "$consumer"
  rm -rf build/dev/erlang/schema_order_consumer build/dev/javascript/schema_order_consumer

  for target in erlang javascript; do
    gleam build --target="$target" --warnings-as-errors
    gleam test --target="$target"
  done
)
# Compile only production source, with development dependencies removed.
mkdir -p "$output/production"
cp -R "$consumer/src" "$output/production/src"
python3 - "$consumer" "$output/production" <<'PYCODE'
import json
from pathlib import Path
import sys
consumer, production = map(Path, sys.argv[1:])
manifest = (consumer / "gleam.toml").read_text().split("[dev-dependencies]")[0]
manifest = manifest.replace('path = "../.."', "path = " + json.dumps(str(consumer.parent.parent)))
(production / "gleam.toml").write_text(manifest)
PYCODE
(
  cd "$output/production"
  for target in erlang javascript; do
    gleam build --target="$target" --warnings-as-errors
  done
  if grep json_blueprint_codegen manifest.toml; then
    echo "The generator leaked into production dependencies" >&2
    exit 1
  fi
  # The positive production build above rules out unrelated dependency failures.
  cp "$repository/codegen/consumer/number_is_not_float.gleam.txt" src/number_is_not_float.gleam
  for target in erlang javascript; do
    if gleam check --target="$target" >number-negative.log 2>&1; then
      echo "An exact Number was accepted as a native Float" >&2
      exit 1
    fi
    for expected in 'Type mismatch' 'number_is_not_float.gleam' 'Number' 'Float'; do
      if ! grep -qF "$expected" number-negative.log; then
        cat number-negative.log >&2
        exit 1
      fi
    done
  done

)
