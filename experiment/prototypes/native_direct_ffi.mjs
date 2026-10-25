// THROWAWAY: narrow native data access for direct typed decoding.
import { Ok, Error, toList } from "./gleam.mjs";
export function keys(x) {
  return x !== null && typeof x === "object" && !Array.isArray(x)
    ? new Ok(toList(Object.keys(x)))
    : new Error(undefined);
}
export function field(x, k) {
  return Object.hasOwn(x, k) ? new Ok(x[k]) : new Error(undefined);
}
export function integer(x) {
  return Number.isSafeInteger(x) ? new Ok(x) : new Error(undefined);
}
export function floating(x) {
  return typeof x === "number" && Number.isFinite(x)
    ? new Ok(x)
    : new Error(undefined);
}
export function numeric(x) {
  return typeof x === "number";
}
export function is_null(x) {
  return x === null;
}
export function array_decode(x, inner, mismatch) {
  if (!Array.isArray(x)) return new Error(mismatch);
  const done = [];
  for (let i = 0; i < x.length; i++) {
    const r = inner(x[i], i);
    if (r instanceof Error) return r;
    done.push(r[0]);
  }
  return new Ok(toList(done));
}
