// Run after `gleam build --target javascript`. Offline, pinned Test262 inputs
// exercise the host feature and public Blueprint behavior separately.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import * as v from "../build/dev/javascript/json_blueprint/json/blueprint/value.mjs";
import * as c from "../build/dev/javascript/json_blueprint/json/blueprint/codec.mjs";
import * as bits from "../build/dev/javascript/gleam_stdlib/gleam/bit_array.mjs";
import { Ok } from "../build/dev/javascript/json_blueprint/gleam.mjs";
import { Option$None$const as none } from "../build/dev/javascript/gleam_stdlib/gleam/option.mjs";

const corpus = new URL("./oracle/test262-source/", import.meta.url);
const provenance = JSON.parse(
  await readFile(new URL("provenance.json", corpus)),
);
for (const file of provenance.files) {
  const bytes = await readFile(new URL(file.local_path, corpus));
  assert.equal(createHash("sha256").update(bytes).digest("hex"), file.sha256);
}
const cases = JSON.parse(await readFile(new URL("cases.json", corpus)));
assert.equal(cases.length, 23);
assert.equal(new Set(cases.map((entry) => entry.id)).size, cases.length);
const limits = v.default_limits();
function ok(result, name) {
  assert.equal(result.isOk(), true, name);
  return result[0];
}

// Independent symbolic decimal normalization; never passes an exact decimal
// through binary64 and does not call Blueprint's number parser as an oracle.
function exact(token) {
  const match = /^(-?)(\d+)(?:\.(\d+))?(?:[eE]([+-]?\d+))?$/.exec(token);
  assert.ok(match, token);
  let coefficient = BigInt(match[1] + match[2] + (match[3] ?? ""));
  let exponent = BigInt(match[4] ?? "0") - BigInt((match[3] ?? "").length);
  if (coefficient === 0n) return ["decimal", "0", "0"];
  while (coefficient % 10n === 0n) {
    coefficient /= 10n;
    exponent++;
  }
  return ["decimal", String(coefficient), String(exponent)];
}
function meaning(source) {
  return JSON.parse(source, (_key, value, context) =>
    typeof value === "number" ? exact(context.source) : value,
  );
}
let callbacks = 0;
const custom = c.custom(
  (value) => new Ok(value),
  (value) => {
    callbacks++;
    return new Ok(value);
  },
  none,
  undefined,
);
function publicAgreement(source, name) {
  const expected = meaning(source);
  for (const result of [
    v.parse(source, limits),
    v.parse_bits(bits.from_string(source), limits),
    c.decode_json(custom, source),
  ]) {
    assert.deepEqual(meaning(v.to_string(ok(result, name))), expected, name);
  }
}
for (const { id, source, primitive_sources } of cases) {
  const observed = [];
  JSON.parse(source, (_key, value, context) => {
    assert.equal(Object.getPrototypeOf(context), Object.prototype, id);
    if (value === null || typeof value !== "object") {
      assert.deepEqual(Reflect.ownKeys(context), ["source"], id);
      const descriptor = Object.getOwnPropertyDescriptor(context, "source");
      assert.equal(descriptor.writable, true, id);
      assert.equal(descriptor.enumerable, true, id);
      assert.equal(descriptor.configurable, true, id);
      observed.push(context.source);
    } else {
      assert.deepEqual(Reflect.ownKeys(context), [], id);
    }
    return value;
  });
  assert.deepEqual(observed, primitive_sources, id);
  publicAgreement(source, id);
}

// Local extensions cover values for which ordinary native decoding loses
// evidence. These are not represented as upstream Test262 test cases.
const numbers = [
  "1.00000000000000001",
  "9007199254740993",
  "9007199254740991.0",
  "-9007199254740993",
  "1e400",
  "-1e-400",
  "-0",
  "1.00E+2",
  "0.1000000000000000055511151231257827021181583404541015625",
];
for (const token of numbers) {
  const number = ok(c.decode_json(c.number(), token), token);
  const encoded = ok(c.encode_json(c.number(), number), token);
  assert.deepEqual(exact(encoded), exact(token), token);
  const list = c.list(c.number());
  const listText = `[${token},${token}]`;
  const listValue = ok(c.decode_json(list, listText), token);
  assert.deepEqual(
    meaning(ok(c.encode_json(list, listValue), token)),
    meaning(listText),
  );
  publicAgreement(token, token);
  publicAgreement(`{"__proto__":${token},"nested":[${token}]}`, token);
}
for (const [source, accepted, expected] of [
  ["1.00000000000000001", false],
  ["9007199254740993", false],
  ["9007199254740991.0", true, 9007199254740991],
  ["1.00E+2", true, 100],
]) {
  const result = c.decode_json(c.int(), source);
  assert.equal(result.isOk(), accepted, source);
  if (accepted) assert.equal(result[0], expected, source);
}
assert.equal(ok(c.decode_json(c.float(), numbers[0]), "rounded Float"), 1);
assert.equal(c.decode_json(c.float(), "1e400").isOk(), false);
assert.equal(ok(c.decode_json(c.float(), "-1e-400"), "signed underflow"), -0);

const duplicates = [
  '{"__proto__":1,"\\u005f_proto__":2}',
  '{"n":{"x":1,"\\u0078":2}}',
  '{"😀":1,"\\ud83d\\ude00":2}',
];
for (const source of duplicates) {
  // Native JSON accepts these; the scanner must preserve Blueprint's policy.
  assert.doesNotThrow(() => JSON.parse(source));
  for (const result of [
    v.parse(source, limits),
    v.parse_bits(bits.from_string(source), limits),
  ]) {
    assert.equal(result.isOk(), false);
    assert.ok(result[0].reason instanceof v.DuplicateObjectKey);
  }
  callbacks = 0;
  const decoded = c.decode_json(custom, source);
  assert.equal(decoded.isOk(), false);
  assert.ok(decoded[0].reason instanceof c.InvalidJson);
  assert.ok(decoded[0].reason[0].reason instanceof v.DuplicateObjectKey);
  assert.equal(callbacks, 0);
}
console.log(
  `Source-text oracle: ${cases.length} Test262-derived cases, ${numbers.length} exact-number extensions, 4 Int projections, 3 Float projections, ${duplicates.length} strict duplicate refusals passed`,
);
