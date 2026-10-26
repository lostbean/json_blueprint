// THROWAWAY: can the hybrid preserve strict admission and typed semantics?
// node experiment/js-hybrid-review.mjs <package>
import { pathToFileURL } from "node:url";
import { resolve } from "node:path";
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
const root = resolve(process.argv[2] || ".");
const mod = async (path) =>
  import(pathToFileURL(root + "/build/dev/javascript/" + path));
const c = await mod("json_blueprint/json/blueprint/codec.mjs");
const v = await mod("json_blueprint/json/blueprint/value.mjs");
const n = await mod("json_blueprint/json/blueprint/number.mjs");
const native = await mod("json_blueprint/json/blueprint/internal/native.mjs");
const { Ok } = await mod("json_blueprint/gleam.mjs");
const { Option$None$const: none } = await mod("gleam_stdlib/gleam/option.mjs");
const limits = v.default_limits();
const failures = [],
  observations = [];
let checks = 0;
function check(name, work, expected) {
  checks++;
  try {
    const actual = work();
    if (!expected(actual)) failures.push({ name, actual });
  } catch (error) {
    failures.push({ name, threw: String(error) });
  }
}
const rejects = (x) => !x.isOk(),
  accepts = (x) => x.isOk();
const parse = (text) => v.parse(text, limits);
const decode = (codec, text) => c.decode_json(codec, text);
const rejected = [
  '{"x":1,"x":2}',
  '{"x":1,"\\u0078":2}',
  '{"nested":{"x":1,"\\u0078":2}}',
  '{"😀":1,"\\ud83d\\ude00":2}',
  '{"__proto__":0,"\\u005f_proto__":1}',
  '{"constructor":1,"constructor":2}',
  '{"a\\nb":1,"a\\u000ab":2}',
  '{"x":"\\ud800"}',
  '{"\\udc00":1}',
  '{"x":["\\ud800"]}',
  '{"x":"\\ud800\\ud800"}',
  '{"x":1,"ignored":"\\ud800"}',
  "[1,2,]",
  '{"x":1} garbage',
  "[NaN]",
  "[Infinity]",
  "[01]",
  "[+1]",
  "[1.]",
  "[.1]",
  "[1e]",
  "[1e+]",
  '{"x":1,"x":}',
  '{"x":1,"x":2} garbage',
];
for (const [i, text] of rejected.entries()) {
  check("bad-value-" + i, () => parse(text), rejects);
  check("bad-codec-" + i, () => decode(c.value(), text), rejects);
}
for (const text of [
  '{"a":{"x":1},"b":{"x":2}}',
  '{"__proto__":1,"constructor":2}',
  '{"é":1,"é":2}',
  '{"\uFFFD":1}',
  '"\\ud83d\\ude00"',
  '{"2":2,"1":1,"x":3}',
  '["[{}]","\\\"",null,true,false]',
])
  check("valid-" + text, () => parse(text), accepts);
for (let unit = 0xd800; unit <= 0xdfff; unit++) {
  const raw = String.fromCharCode(unit);
  for (const text of ['"' + raw + '"', '{"' + raw + '":0}']) {
    check("raw-value-" + unit, () => parse(text), rejects);
    check("raw-codec-" + unit, () => decode(c.value(), text), rejects);
  }
}
for (const unit of [0, 1, 8, 9, 10, 13, 31]) {
  check(
    "literal-control-" + unit,
    () => parse('"' + String.fromCharCode(unit) + '"'),
    rejects,
  );
  check(
    "escaped-control-" + unit,
    () => parse('"\\u' + unit.toString(16).padStart(4, "0") + '"'),
    accepts,
  );
}
const byteLimits = v.with_max_bytes(limits, 3);
check("byte-limit-unicode", () => v.parse('"é"', byteLimits), rejects);
check("byte-limit-ascii", () => v.parse('"a"', byteLimits), accepts);
check(
  "byte-limit-before-scalar",
  () => v.parse('"\ud800"', v.with_max_bytes(limits, 1)),
  (x) => rejects(x) && x[0].reason.constructor.name === "ByteLimitExceeded",
);
for (const [text, ok] of [
  ["1.00000000000000001", false],
  ["9007199254740993", false],
  ["9007199254740991", true],
  ["9007199254740991.0", true],
  ["1.00e2", true],
  ["-0.0", true],
  ["1e-1", false],
])
  check(
    "int-" + text,
    () => decode(c.int(), text),
    (x) => x.isOk() === ok,
  );
for (const text of [
  "0.10000000000000001",
  "9007199254740993",
  "1.00000000000000001",
  "1e400",
  "-1e-400",
]) {
  const expected = n.parse(text, n.limits(100, 100, 1000));
  check(
    "exact-" + text,
    () => decode(c.number(), text),
    (x) =>
      x.isOk() &&
      expected.isOk() &&
      n.to_string(x[0]) === n.to_string(expected[0]),
  );
}
for (const [text, ok] of [
  ["1e400", false],
  ["1e-400", true],
  ["-1e-400", true],
  ["-0", true],
])
  check(
    "float-" + text,
    () => decode(c.float(), text),
    (x) => x.isOk() === ok,
  );
check(
  "negative-underflow",
  () => decode(c.float(), "-1e-400"),
  (x) => x.isOk() && Object.is(x[0], -0),
);
check(
  "mathematical-negative-zero",
  () => decode(c.float(), "-0"),
  (x) => x.isOk() && Object.is(x[0], 0),
);
let callbacks = 0;
const custom = c.custom(
  (raw) => new Ok(raw),
  (raw) => {
    callbacks++;
    return new Ok(raw);
  },
  none,
  undefined,
);
for (const text of rejected) {
  callbacks = 0;
  check(
    "syntax-before-callback-" + text,
    () => decode(custom, text),
    (x) => rejects(x) && callbacks === 0,
  );
}
callbacks = 0;
check(
  "custom-value-subtree",
  () => decode(custom, '{"n":1.00000000000000001}'),
  (x) =>
    x.isOk() &&
    callbacks === 1 &&
    v.to_string(x[0]).includes("1.00000000000000001"),
);
const record = c.field(
  "x",
  c.int(),
  (x) => c.success(x),
  (x) => x,
);
check("closed-record", () => decode(record, '{"x":1,"extra":2}'), rejects);
check("nested-name-scope", () => parse('{"x":{"x":1},"y":{"x":2}}'), accepts);
for (const depth of [100, 500, 2000, 20000])
  for (const valid of [true, false]) {
    const text =
      "[".repeat(depth) + "0" + "]".repeat(valid ? depth : depth - 1);
    check(
      "depth-no-crash-" + depth + "-" + valid,
      () => parse(text),
      (x) => (valid ? typeof x.isOk() === "boolean" : rejects(x)),
    );
  }
for (const text of [
  "1e9007199254740993",
  "1e-9007199254740993",
  "0e9999999999999999999999",
]) {
  const variants = {};
  for (const [name, codec] of [
    ["number", c.number()],
    ["float", c.float()],
    ["int", c.int()],
  ]) {
    try {
      const x = decode(codec, text);
      variants[name] = x.isOk() ? "accepted" : x[0].reason.constructor.name;
    } catch (error) {
      variants[name] = "THREW:" + error;
      failures.push({ name: "huge-no-crash", text, error: String(error) });
    }
  }
  observations.push({ text, variants });
}
// User callback exceptions are application failures, never parse-capacity errors.
checks++;
try {
  const throwing = c.custom(
    (raw) => new Ok(raw),
    () => {
      throw new RangeError("application callback");
    },
    none,
    undefined,
  );
  decode(throwing, "null");
  failures.push({ name: "callback-rangeerror-propagates", actual: "returned" });
} catch (error) {
  if (
    !(error instanceof RangeError) ||
    error.message !== "application callback"
  )
    failures.push({
      name: "callback-rangeerror-propagates",
      actual: String(error),
    });
}
for (const size of [1100, 10000]) {
  const text = "0." + "1".repeat(size);
  const row = { numericTokenBytes: text.length };
  for (const [name, work] of [
    ["value", () => parse(text)],
    ["number", () => decode(c.number(), text)],
    ["float", () => decode(c.float(), text)],
    ["int", () => decode(c.int(), text)],
  ]) {
    checks++;
    try {
      const result = work();
      row[name] = result.isOk()
        ? "accepted"
        : result[0].reason.constructor.name;
    } catch (error) {
      failures.push({
        name: "long-number-no-crash",
        size,
        error: String(error),
      });
    }
  }
  observations.push(row);
}
const paddedExponent = "1e" + "0".repeat(10000) + "2";
check(
  "padded-exponent-capacity-is-not-syntax",
  () => parse(paddedExponent),
  (result) =>
    result.isOk() ||
    result[0].reason.constructor.name === "RuntimeCapacityExceeded",
);
const objectOrder = parse('{"2":2,"1":1,"x":3}');
observations.push({
  objectOrder: objectOrder.isOk() ? v.to_string(objectOrder[0]) : "rejected",
});
const hash = (p) =>
  createHash("sha256")
    .update(readFileSync(root + "/" + p))
    .digest("hex");
console.log(
  JSON.stringify(
    {
      node: process.version,
      nativeSupported: native.supported(),
      checks,
      failures,
      observations,
      sourceHashes: {
        native: hash("src/json/blueprint/internal/native.gleam"),
        value: hash("src/json/blueprint/value.gleam"),
      },
    },
    null,
    2,
  ),
);
if (failures.length) process.exitCode = 1;
