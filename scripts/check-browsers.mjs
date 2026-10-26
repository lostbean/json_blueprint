// Build JavaScript first. Pass the installed playwright module path as argv[2].
// Uses actual browser engines over loopback HTTP, with no Node APIs in the probe.
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { resolve, sep } from "node:path";
import { pathToFileURL } from "node:url";

const playwright = await import(pathToFileURL(resolve(process.argv[2])));
const root = resolve("build/dev/javascript");
const server = createServer(async (request, response) => {
  try {
    const pathname = new URL(request.url, "http://localhost").pathname;
    if (pathname === "/") {
      response.end(
        "<!doctype html><title>JSON Blueprint browser checks</title>",
      );
      return;
    }
    const file = resolve(root, "." + pathname);
    if (!file.startsWith(root + sep)) throw new Error("outside build");
    response.setHeader("Content-Type", "text/javascript");
    response.end(await readFile(file));
  } catch {
    response.statusCode = 404;
    response.end();
  }
});
await new Promise((done) => server.listen(0, "127.0.0.1", done));
const results = [];
try {
  for (const engine of ["chromium", "firefox", "webkit"]) {
    const browser = await playwright[engine].launch({ headless: true });
    try {
      const page = await browser.newPage();
      await page.goto(`http://127.0.0.1:${server.address().port}/`);
      const result = await page.evaluate(async () => {
        const c = await import("/json_blueprint/json/blueprint/codec.mjs");
        const v = await import("/json_blueprint/json/blueprint/value.mjs");
        const n = await import("/json_blueprint/json/blueprint/number.mjs");
        const bits = await import("/gleam_stdlib/gleam/bit_array.mjs");
        const { Ok } = await import("/json_blueprint/gleam.mjs");
        const { Option$None$const: none } =
          await import("/gleam_stdlib/gleam/option.mjs");
        const failures = [];
        let checks = 0;
        function check(name, work) {
          checks++;
          try {
            if (!work()) failures.push(name);
          } catch (error) {
            failures.push(name + ": " + error);
          }
        }
        let source;
        JSON.parse("9007199254740993", (_key, value, context) => {
          source = context?.source;
          return value;
        });
        check(
          "native source text available",
          () => source === "9007199254740993",
        );
        const limits = v.default_limits();
        const parse = (text) => v.parse(text, limits);
        const decode = (codec, text) => c.decode_json(codec, text);
        const invalid = [
          '{"x":1,"x":2}',
          '{"x":1,"\\u0078":2}',
          '{"😀":1,"\\ud83d\\ude00":2}',
          '{"a\\nb":1,"a\\u000ab":2}',
          '{"__proto__":1,"\\u005f_proto__":2}',
          '{"n":{"x":1,"\\u0078":2}}',
          '"\\ud800"',
          '"\\udc00"',
          '{"\\ud800":0}',
          '{"ignored":"\\ud800"}',
          "[1,]",
          "[01]",
          "[NaN]",
          "1e",
          '{"x":1} trailing',
          "\ufeffnull",
        ];
        let calls = 0;
        const custom = c.custom(
          (x) => new Ok(x),
          (x) => {
            calls++;
            return new Ok(x);
          },
          none,
          undefined,
        );
        for (const text of invalid) {
          check("reject Value " + text, () => !parse(text).isOk());
          check(
            "reject bytes " + text,
            () => !v.parse_bits(bits.from_string(text), limits).isOk(),
          );
          check("reject before callback " + text, () => {
            calls = 0;
            return !decode(custom, text).isOk() && calls === 0;
          });
        }
        for (let unit = 0xd800; unit <= 0xdfff; unit++) {
          const text = '"' + String.fromCharCode(unit) + '"';
          check("raw surrogate Value " + unit, () => !parse(text).isOk());
          check(
            "raw surrogate codec " + unit,
            () => !decode(c.string(), text).isOk(),
          );
        }
        for (const text of [
          '"\\ud83d\\ude00"',
          '{"__proto__":1,"constructor":2}',
          '{"a":{"x":1},"b":{"x":2}}',
          '{"é":1,"é":2}',
        ])
          check("valid " + text, () => parse(text).isOk());
        for (const [text, accepted] of [
          ["1.00000000000000001", false],
          ["9007199254740993", false],
          ["9007199254740991", true],
          ["9007199254740991.0", true],
          ["1.00e2", true],
        ])
          check("Int " + text, () => decode(c.int(), text).isOk() === accepted);
        for (const text of [
          "1.00000000000000001",
          "9007199254740993",
          "1e400",
          "-1e-400",
        ]) {
          check("exact Number " + text, () => {
            const expected = n.parse(text, n.limits(100, 100, 1000));
            const actual = decode(c.number(), text);
            return (
              expected.isOk() &&
              actual.isOk() &&
              n.to_string(expected[0]) === n.to_string(actual[0])
            );
          });
        }
        check(
          "Float deliberate rounding",
          () => decode(c.float(), "1.00000000000000001")[0] === 1,
        );
        check(
          "Float overflow rejection",
          () => !decode(c.float(), "1e400").isOk(),
        );
        check("negative Float underflow", () =>
          Object.is(decode(c.float(), "-1e-400")[0], -0),
        );
        check(
          "byte bound",
          () => !v.parse('"é"', v.with_max_bytes(limits, 3)).isOk(),
        );
        check("byte boundary", () =>
          v.parse('"a"', v.with_max_bytes(limits, 3)).isOk(),
        );
        check("custom exact subtree", () => {
          calls = 0;
          const result = decode(custom, '{"n":1.00000000000000001}');
          return (
            result.isOk() &&
            calls === 1 &&
            v.to_string(result[0]).includes("1.00000000000000001")
          );
        });
        check("application exception propagates", () => {
          const throwing = c.custom(
            (x) => new Ok(x),
            () => {
              throw new RangeError("application");
            },
            none,
            undefined,
          );
          try {
            decode(throwing, "null");
            return false;
          } catch (error) {
            return (
              error instanceof RangeError && error.message === "application"
            );
          }
        });
        return { checks, failures, userAgent: navigator.userAgent };
      });
      results.push({ engine, version: browser.version(), ...result });
    } finally {
      await browser.close();
    }
  }
} finally {
  server.close();
}
console.log(JSON.stringify({ playwright: "1.58.2", results }, null, 2));
if (results.some((result) => result.failures.length)) process.exitCode = 1;
