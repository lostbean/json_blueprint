// Run in a separate Node process before Blueprint is imported so the feature
// probe observes a runtime without numeric source text. Never changes production
// globals or contaminates the ordinary test runner's module cache.
import assert from "node:assert/strict";

const parse = JSON.parse;
JSON.parse = (source, revive) =>
  parse(
    source,
    typeof revive === "function"
      ? function (key, value) {
          return revive.call(this, key, value);
        }
      : revive,
  );
const v =
  await import("../build/dev/javascript/json_blueprint/json/blueprint/value.mjs");
const c =
  await import("../build/dev/javascript/json_blueprint/json/blueprint/codec.mjs");
const b =
  await import("../build/dev/javascript/gleam_stdlib/gleam/bit_array.mjs");
const { Option$None$const: none } =
  await import("../build/dev/javascript/gleam_stdlib/gleam/option.mjs");
const limits = v.default_limits();
const refused = (result) => {
  assert.equal(result.isOk(), false);
  assert.ok(result[0].reason instanceof v.UnsupportedRuntime);
  assert.equal(v.is_limit_exceeded(result[0]), false);
  assert.equal(
    v.describe_parse_error(result[0]),
    "JavaScript runtime requires JSON.parse reviver context.source",
  );
};
refused(v.parse("1.00000000000000001", limits));
refused(v.parse_bits(b.from_string("null"), limits));
const custom = c.custom(
  () => {
    throw new Error("unexpected encode");
  },
  () => {
    throw new Error("unsupported runtime must precede callbacks");
  },
  none,
  undefined,
);
assert.equal(c.decode_json(custom, "null").isOk(), false);
const decoded = c.decode_json(c.int(), "1");
assert.equal(decoded.isOk(), false);
assert.ok(decoded[0].reason instanceof c.InvalidJson);
assert.ok(decoded[0].reason[0].reason instanceof v.UnsupportedRuntime);
assert.ok(
  v.parse("null", v.with_max_bytes(limits, 1))[0].reason instanceof
    v.ByteLimitExceeded,
);
const legacy =
  await import("../build/dev/javascript/json_blueprint/json/blueprint.mjs");
const legacyResult = legacy.decode(legacy.int(), "42");
assert.equal(legacyResult.isOk(), true);
assert.equal(legacyResult[0], 42);
assert.ok(
  v.parse_bits(b.from_string("null"), v.with_max_bytes(limits, 1))[0]
    .reason instanceof v.ByteLimitExceeded,
);
console.log(
  "Unsupported JavaScript runtime: explicit refusal, byte precedence and diagnostics passed",
);
