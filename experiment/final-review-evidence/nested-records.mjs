import { pathToFileURL } from "node:url";
const root = process.argv[2];
const c = await import(
  pathToFileURL(
    root + "/build/dev/javascript/json_blueprint/json/blueprint/codec.mjs",
  )
);
const { Ok } = await import(
  pathToFileURL(root + "/build/dev/javascript/json_blueprint/gleam.mjs")
);
const inner = c.field(
  "x",
  c.int(),
  (x) => c.success(x),
  (x) => x,
);
const outer = c.field(
  "x",
  inner,
  (x) =>
    c.field(
      "y",
      inner,
      (y) => c.success([x, y]),
      (p) => p[1],
    ),
  (p) => p[0],
);
const decoded = c.decode_json(outer, '{"x":{"x":1},"y":{"x":2}}');
const encoded = c.encode_json(outer, [1, 2]);
console.log(JSON.stringify({ decoded, encoded }));
if (
  !(decoded instanceof Ok) ||
  JSON.stringify(decoded[0]) !== "[1,2]" ||
  !(encoded instanceof Ok) ||
  encoded[0] !== '{"x":{"x":1},"y":{"x":2}}'
)
  process.exitCode = 1;
