import { Ok, Error, toList } from "./gleam.mjs";

let trace = [];

export function log(entry) {
  trace.push(entry);
  return undefined;
}

export function take() {
  const taken = trace;
  trace = [];
  return toList(taken);
}

export function panic_message(run) {
  try {
    return new Ok(run());
  } catch (error) {
    if (error && error.gleam_error === "panic") return new Error(error.message);
    throw error;
  }
}
