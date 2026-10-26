// THROWAWAY: all existing tests must pass without JSON.parse source context.
// node experiment/js-hybrid-review-fallback.mjs <built package>
import { pathToFileURL } from "node:url";
import { resolve } from "node:path";
const root = resolve(process.argv[2] || ".");
const original = JSON.parse;
JSON.parse = function (text, reviver) {
  return original(
    text,
    typeof reviver === "function"
      ? function (key, value) {
          return reviver.call(this, key, value);
        }
      : reviver,
  );
};
const native = await import(
  pathToFileURL(
    root +
      "/build/dev/javascript/json_blueprint/json/blueprint/internal/native.mjs",
  )
);
if (native.supported()) throw new Error("fallback probe still native");
const { main } = await import(
  pathToFileURL(
    root + "/build/dev/javascript/json_blueprint/json_blueprint_test.mjs",
  )
);
await main();
