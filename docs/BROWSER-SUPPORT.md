# JavaScript browser validation

The native hybrid requires `JSON.parse` to pass the original primitive source
text to its reviver as `context.source`. This preserves the original decimal
token even when JavaScript's native numeric value has rounded it. A runtime
without this capability cannot supply the strict exact-number contract through
plain native parsing. Strict parsing returns `UnsupportedRuntime` on those
runtimes. There is no portable parser fallback. This keeps one JavaScript
parsing implementation without silently weakening exact numbers. The frozen
legacy API retains its existing parser and compatibility behavior.

The [MDN browser compatibility data](https://github.com/mdn/browser-compat-data/blob/main/javascript/builtins/JSON.json)
records this feature from Chrome 114, Firefox 135, Safari 18.4 (including iOS),
Node.js 21.0.0, Deno 1.33 and Bun 1.1.43. Edge follows Chromium. These are feature
introduction versions, not a claim that each historical release was executed or
that all are still maintained. The feature probe is the authoritative runtime
capability check.

## Executed evidence

On 2026-10-25, macOS arm64 with Playwright 1.58.2:

| Engine | Executed version | Public API checks | Failures |
| --- | --- | ---: | ---: |
| Chromium | 145.0.7632.6 | 4,165 | 0 |
| Firefox | 146.0.1 | 4,165 | 0 |
| WebKit | 26.0 | 4,165 | 0 |

The checks execute built Gleam modules in actual headless browser engines over
loopback HTTP. They cover duplicate keys (including equivalent escapes and
special property names), all raw unpaired UTF-16 surrogate units through Value
and codec entry points, malformed escaped surrogates, BOM/text/byte parity,
exact Number and checked Int projection, deliberate Float rounding and overflow,
byte limits, and custom callback ownership. Native source-text availability is
asserted before the public checks. A separate [missing-feature regression](../test/unsupported_runtime_check.mjs)
in the ordinary gate checks explicit refusal through the public strict APIs.

This is engine coverage, not execution of every browser version or physical iOS
device. Playwright WebKit is not the shipping Safari application. These checks
supplement the Node/Erlang full gate and parser corpus; they are not a complete
browser conformance proof. The historical minimum versions above are sourced
compatibility facts, not tested minimums.

## Reproduce

Use a separate temporary installation, so browser tooling does not become a
runtime package dependency:

```sh
nix develop --command gleam build --target javascript --warnings-as-errors
npm install --prefix /tmp/blueprint-browser-validation playwright@1.58.2
PLAYWRIGHT_BROWSERS_PATH=/tmp/blueprint-browser-validation/browsers \
  node /tmp/blueprint-browser-validation/node_modules/playwright/cli.js \
  install chromium firefox webkit
PLAYWRIGHT_BROWSERS_PATH=/tmp/blueprint-browser-validation/browsers \
  node scripts/check-browsers.mjs \
  /tmp/blueprint-browser-validation/node_modules/playwright/index.mjs
```

Browser launch requires the host permissions needed by those engines. The
macOS execution sandbox used during this validation denied Chromium's Mach-port
registration; the same local command succeeded with the sandbox restriction
lifted. No user browser profile or remote service was used.
