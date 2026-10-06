#!/bin/sh
# Gleam's warnings-as-errors flag does not reject native Erlang warnings.
set -eu
cd "$(dirname "$0")/.."
build_root=$(mktemp -d "${TMPDIR:-/tmp}/blueprint-native.XXXXXX")
trap 'rm -rf "$build_root"' EXIT HUP INT TERM
if [ "$#" -gt 0 ]; then
  erlc -Werror -o "$build_root" "$@"
else
  git ls-files -z -- '*.erl' >"$build_root/sources"
  xargs -0 -r erlc -Werror -o "$build_root" <"$build_root/sources"
fi
