// Native JSON parsing with exact numeric evidence and strict name/Unicode checks.
import { Ok, Error as GleamError, List } from "./gleam.mjs";
import {
  Syntax,
  DuplicateKey,
  RuntimeCapacity,
  NumberRepresentation,
  UnsupportedRuntime,
  Null,
  Bool,
  String as StringKind,
  Number as NumberKind,
  Array as ArrayKind,
  Object as ObjectKind,
  Integer,
  Decimal,
  Other,
} from "./json/blueprint/internal/native.mjs";

let sourceContext = false;
JSON.parse("1", (_key, value, context) => {
  sourceContext = context?.source === "1";
  return value;
});
export function supported() {
  return sourceContext;
}
class DecimalToken {
  constructor(token, rounded) {
    this.token = token;
    this.rounded = rounded;
  }
}
const representationFailure = {};

// JSON.parse already validated grammar. Match the existing exact Number target
// representation, without constructing its digit list for a Float-only codec.
function representable(token) {
  let digits = 0,
    first = -1,
    last = -1,
    fraction = 0,
    afterDot = false,
    i = 0;
  if (token[0] === "-") i++;
  for (; i < token.length; i++) {
    const code = token.charCodeAt(i);
    if (code === 101 || code === 69) break;
    if (code === 46) {
      afterDot = true;
      continue;
    }
    if (code !== 48) {
      if (first < 0) first = digits;
      last = digits;
    }
    digits++;
    if (afterDot) fraction++;
  }
  if (first < 0) return true;
  const written = i < token.length ? Number(token.slice(i + 1)) : 0;
  if (!Number.isSafeInteger(written)) return false;
  const exponent = written + (digits - last - 1 - fraction);
  return (
    Number.isSafeInteger(exponent) &&
    Number.isSafeInteger(exponent + (last - first + 1))
  );
}
function revive(_key, value, context) {
  if (typeof value !== "number") return value;
  const token = context.source;
  if (Number.isSafeInteger(value) && !/[.eE]/.test(token))
    return value === 0 ? 0 : value;
  if (!representable(token)) throw representationFailure;
  return new DecimalToken(token, value);
}

// Syntax is native-owned. This scan sees every original member, including those
// JSON.parse overwrote, and keeps only key sets for currently open objects.
function strictScan(source) {
  const objects = [];
  let duplicate;
  for (let i = 0; i < source.length;) {
    const c = source.charCodeAt(i);
    if (c === 123) {
      objects.push(new Set());
      i++;
      continue;
    }
    if (c === 125) {
      objects.pop();
      i++;
      continue;
    }
    if (c !== 34) {
      i++;
      continue;
    }
    const start = i++;
    let escaped = false;
    while (source.charCodeAt(i) !== 34) {
      if (source.charCodeAt(i) !== 92) {
        i++;
        continue;
      }
      escaped = true;
      if (source.charCodeAt(i + 1) !== 117) {
        i += 2;
        continue;
      }
      const unit = parseInt(source.slice(i + 2, i + 6), 16);
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (source.charCodeAt(i + 6) !== 92 || source.charCodeAt(i + 7) !== 117)
          return new Syntax("unpaired escaped surrogate");
        const low = parseInt(source.slice(i + 8, i + 12), 16);
        if (!(low >= 0xdc00 && low <= 0xdfff))
          return new Syntax("unpaired escaped surrogate");
        i += 12;
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        return new Syntax("unpaired escaped surrogate");
      } else i += 6;
    }
    const end = ++i;
    while (
      source[i] === " " ||
      source[i] === "\t" ||
      source[i] === "\n" ||
      source[i] === "\r"
    )
      i++;
    if (source.charCodeAt(i) === 58) {
      const key = escaped
        ? JSON.parse(source.slice(start, end))
        : source.slice(start + 1, end - 1);
      const keys = objects[objects.length - 1];
      if (keys.has(key)) duplicate ??= key;
      else keys.add(key);
    }
  }
  return duplicate === undefined ? undefined : new DuplicateKey(duplicate);
}
export function parse(source) {
  if (!sourceContext) return new GleamError(new UnsupportedRuntime());
  try {
    const raw = JSON.parse(source, revive);
    const refusal = strictScan(source);
    return refusal === undefined ? new Ok(raw) : new GleamError(refusal);
  } catch (error) {
    if (error === representationFailure)
      return new GleamError(new NumberRepresentation());
    if (error instanceof SyntaxError)
      return new GleamError(new Syntax("invalid JSON"));
    if (error instanceof RangeError)
      return new GleamError(new RuntimeCapacity());
    throw error;
  }
}
function isObject(raw) {
  return (
    raw !== null &&
    typeof raw === "object" &&
    !Array.isArray(raw) &&
    !(raw instanceof DecimalToken)
  );
}
export function kind(raw) {
  if (raw === null) return new Null();
  if (typeof raw === "boolean") return new Bool();
  if (typeof raw === "string") return new StringKind();
  if (typeof raw === "number" || raw instanceof DecimalToken)
    return new NumberKind();
  if (Array.isArray(raw)) return new ArrayKind();
  return new ObjectKind();
}
export function string(raw) {
  return typeof raw === "string" ? new Ok(raw) : new GleamError(undefined);
}
export function boolean(raw) {
  return typeof raw === "boolean" ? new Ok(raw) : new GleamError(undefined);
}
export function is_null(raw) {
  return raw === null;
}
export function keys(raw) {
  return isObject(raw)
    ? new Ok(List.fromArray(Object.keys(raw)))
    : new GleamError(undefined);
}
export function field(raw, key) {
  return isObject(raw) && Object.hasOwn(raw, key)
    ? new Ok(raw[key])
    : new GleamError(undefined);
}
export function array_items(raw) {
  return Array.isArray(raw)
    ? new Ok(List.fromArray(raw))
    : new GleamError(undefined);
}
export function array_decode(raw, decode, mismatch) {
  if (!Array.isArray(raw)) return new GleamError(mismatch);
  const values = [];
  for (let i = 0; i < raw.length; i++) {
    const result = decode(raw[i], i);
    if (result instanceof GleamError) return result;
    values.push(result[0]);
  }
  return new Ok(List.fromArray(values));
}
export function number_input(raw) {
  if (typeof raw === "number") return new Integer(raw);
  if (raw instanceof DecimalToken) return new Decimal(raw.token);
  return new Other();
}
export function floating(raw) {
  if (typeof raw === "number") return new Ok(raw);
  if (!(raw instanceof DecimalToken) || !Number.isFinite(raw.rounded))
    return new GleamError(undefined);
  return new Ok(
    raw.rounded === 0 && /^-?0(?:\.0*)?(?:[eE][+-]?\d+)?$/.test(raw.token)
      ? 0
      : raw.rounded,
  );
}

// Only exact numeric kernel work is wrapped; user callbacks remain outside.
export function with_projection_capacity(work, refusal) {
  try {
    return work();
  } catch (error) {
    if (error instanceof RangeError) return new GleamError(refusal);
    throw error;
  }
}
