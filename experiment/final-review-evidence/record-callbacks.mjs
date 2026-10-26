// Run with: node record-callbacks.mjs /absolute/path/to/json_blueprint
import { pathToFileURL } from "node:url";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
const root = process.argv[2];
const c = await import(
  pathToFileURL(
    root + "/build/dev/javascript/json_blueprint/json/blueprint/codec.mjs",
  )
);
const { Option$None$const: none, Some } = await import(
  pathToFileURL(root + "/build/dev/javascript/gleam_stdlib/gleam/option.mjs")
);
const codec = c.optional_field(
  "x",
  c.int(),
  (a) =>
    c.optional_field(
      "x",
      c.int(),
      (b) => c.success([a, b]),
      (p) => p[1],
    ),
  (p) => p[0],
);
let rejected = 0;
for (const input of [
  [none, none],
  [new Some(1), none],
  [none, new Some(2)],
  [new Some(1), new Some(2)],
])
  try {
    c.encode_json(codec, input);
  } catch (e) {
    if (e.message.includes('field "x" appears twice')) rejected++;
  }
const seen = [];
const valid = c.field(
  "x",
  c.int(),
  (a) => {
    seen.push("next-x:" + a);
    return c.optional_field(
      "y",
      c.int(),
      (b) => {
        seen.push("next-y");
        return c.success([a, b]);
      },
      (p) => {
        seen.push("get-y");
        return p[1];
      },
    );
  },
  (p) => {
    seen.push("get-x");
    return p[0];
  },
);
c.decode_json(valid, '{"x":1,"y":2}');
const decode_callbacks = [...seen];
seen.length = 0;
c.encode_json(valid, [1, new Some(2)]);
const encode_callbacks = [...seen];
const hash = (p) =>
  createHash("sha256")
    .update(readFileSync(root + "/" + p))
    .digest("hex");
console.log(
  JSON.stringify(
    {
      rejected,
      decode_callbacks,
      encode_callbacks,
      source_sha256: hash("src/json/blueprint/codec.gleam"),
      compiled_sha256: hash(
        "build/dev/javascript/json_blueprint/json/blueprint/codec.mjs",
      ),
    },
    null,
    2,
  ),
);
if (
  rejected !== 4 ||
  JSON.stringify(decode_callbacks) !== JSON.stringify(["next-x:1", "next-y"]) ||
  JSON.stringify(encode_callbacks) !==
    JSON.stringify(["get-x", "next-x:1", "get-y", "next-y"])
)
  process.exitCode = 1;
