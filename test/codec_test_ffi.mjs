import { Ok, Error } from "./gleam.mjs";

// The message of the panic that `run` raises, or `Error(undefined)`.
export function panic_message(run) {
  try {
    run();
    return new Error(undefined);
  } catch (error) {
    if (error && error.gleam_error === "panic") return new Ok(error.message);
    throw error;
  }
}
