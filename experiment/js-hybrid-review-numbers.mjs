// THROWAWAY: independent BigInt oracle for hybrid numeric admission.
// node experiment/js-hybrid-review-numbers.mjs <built package>
import { pathToFileURL } from "node:url";
import { resolve } from "node:path";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
const root = resolve(process.argv[2] || ".");
const c = await import(
  pathToFileURL(
    root + "/build/dev/javascript/json_blueprint/json/blueprint/codec.mjs",
  )
);
const n = await import(
  pathToFileURL(
    root + "/build/dev/javascript/json_blueprint/json/blueprint/number.mjs",
  )
);
const max = 9007199254740991n;
function canonical(token) {
  const neg = token.startsWith("-");
  const [m, e = "0"] = (neg ? token.slice(1) : token).toLowerCase().split("e");
  const [a, b = ""] = m.split(".");
  let digits = (a + b).replace(/^0+/, "");
  if (!digits) return [false, "0", 0n];
  const coefficient = digits.replace(/0+$/, "");
  return [
    neg,
    coefficient,
    BigInt(e) - BigInt(b.length) + BigInt(digits.length - coefficient.length),
  ];
}
const failures = [];
let cases = 0,
  accepted = 0,
  refused = 0,
  kernelDisagreements = 0;
for (const base of [0n, max - 5n, max])
  for (const sign of [-1n, 1n])
    for (let shift = -20n; shift <= 20n; shift++)
      for (const mantissa of [
        "0",
        "0.000",
        "1",
        "1.00",
        "100",
        "0.1",
        "0.01",
        "0.000001200",
        "1.2300",
        "12",
        "123456789",
        "100000.00001",
      ])
        for (const negative of ["", "-"]) {
          const written = (base + shift) * sign;
          const token = negative + mantissa + "e" + written;
          const [neg, digits, exp] = canonical(token);
          const magnitude = exp + BigInt(digits.length);
          const expected =
            digits === "0" ||
            (written >= -max &&
              written <= max &&
              exp >= -max &&
              exp <= max &&
              magnitude >= -max &&
              magnitude <= max);
          cases++;
          try {
            const result = c.decode_json(c.number(), token);
            const kernel = n.from_json_token(token);
            if (result.isOk() !== kernel.isOk()) kernelDisagreements++;
            if (result.isOk()) {
              accepted++;
              const actual = canonical(n.to_string(result[0]));
              if (
                !expected ||
                actual[0] !== neg ||
                actual[1] !== digits ||
                actual[2] !== exp
              )
                failures.push({
                  token,
                  kind: "wrong acceptance/value",
                  actual: n.to_string(result[0]),
                });
            } else {
              refused++;
              if (expected)
                failures.push({
                  token,
                  kind: "wrong refusal",
                  reason: result[0].reason.constructor.name,
                });
            }
          } catch (error) {
            failures.push({ token, kind: "threw", message: String(error) });
          }
        }
const hash = (p) =>
  createHash("sha256")
    .update(readFileSync(root + "/" + p))
    .digest("hex");
console.log(
  JSON.stringify(
    {
      cases,
      accepted,
      refused,
      kernelDisagreements,
      failures,
      sourceSha256: hash("src/json_blueprint_native_ffi.mjs"),
    },
    null,
    2,
  ),
);
if (failures.length || kernelDisagreements) process.exitCode = 1;
