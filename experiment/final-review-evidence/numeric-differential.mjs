// Run with: node numeric-differential.mjs /absolute/path/to/json_blueprint
import { pathToFileURL } from "node:url";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
const root = process.argv[2];
const n = await import(
  pathToFileURL(
    root + "/build/dev/javascript/json_blueprint/json/blueprint/number.mjs",
  )
);
const { Ok } = await import(
  pathToFileURL(root + "/build/dev/javascript/json_blueprint/gleam.mjs")
);
const max = 9007199254740991n;
function canonical(s) {
  const [m, e = "0"] = s.toLowerCase().split("e");
  const [a, b = ""] = m.split(".");
  let digits = (a + b).replace(/^0+/, "");
  const stripped = digits.replace(/0+$/, "");
  return [
    stripped,
    BigInt(e) - BigInt(b.length) + BigInt(digits.length - stripped.length),
  ];
}
let count = 0,
  accepted = 0,
  refused = 0,
  wrong = [];
for (const limit of [0n, 2n, 17n, max - 5n, max])
  for (const sign of [-1n, 1n])
    for (let shift = -20n; shift <= 20n; shift++)
      for (const mantissa of [
        "1",
        "1.00",
        "100",
        "0.1",
        "0.01",
        "1.2300",
        "12",
        "123456789",
      ]) {
        const exp = (limit + shift) * sign,
          token = mantissa + "e" + exp;
        const result = n.parse(token, n.limits(100, 100, Number(limit)));
        const [digits, normalized] = canonical(token);
        const magnitude = normalized + BigInt(digits.length);
        const expected =
          exp >= -max &&
          exp <= max &&
          normalized >= -limit &&
          normalized <= limit &&
          normalized >= -max &&
          normalized <= max &&
          magnitude >= -max &&
          magnitude <= max;
        count++;
        if (result instanceof Ok) {
          accepted++;
          const actual = canonical(n.to_string(result[0]));
          if (!expected || actual[0] !== digits || actual[1] !== normalized)
            wrong.push([
              token,
              "accepted",
              n.to_string(result[0]),
              String(limit),
            ]);
        } else {
          refused++;
          if (expected) wrong.push([token, "refused", String(limit)]);
        }
      }
const hash = (p) =>
  createHash("sha256")
    .update(readFileSync(root + "/" + p))
    .digest("hex");
console.log(
  JSON.stringify(
    {
      count,
      accepted,
      refused,
      wrong,
      source_sha256: hash("src/json/blueprint/number.gleam"),
      compiled_sha256: hash(
        "build/dev/javascript/json_blueprint/json/blueprint/number.mjs",
      ),
    },
    null,
    2,
  ),
);
if (wrong.length) process.exitCode = 1;
