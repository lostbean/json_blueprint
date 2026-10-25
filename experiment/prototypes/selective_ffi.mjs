// THROWAWAY: measure memory and callback parity for selective typed decoding.
import { toList } from "../gleam_stdlib/gleam.mjs";
let calls = [];
export function reset() {
  calls = [];
}
export function log(x) {
  calls.push(x);
}
export function entries() {
  return toList(calls);
}
export function snapshot() {
  globalThis.gc();
  return JSON.stringify(process.memoryUsage());
}
