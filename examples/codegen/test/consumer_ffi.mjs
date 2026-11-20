import { Ok, Error } from "./gleam.mjs";
import path from "node:path";
import fs from "node:fs";
export function read_file(name) {
  try {
    return new Ok(fs.readFileSync(name, "utf8"));
  } catch (error) {
    return new Error(String(error));
  }
}

export function write_file(name, content) {
  try {
    fs.mkdirSync(path.dirname(name), { recursive: true });
    fs.writeFileSync(name, content, "utf8");
    return new Ok(undefined);
  } catch (error) {
    return new Error(String(error));
  }
}

// Copied size is a BEAM measure; JavaScript has no process copy.
export function flat_size_bytes(_term) {
  return -1;
}
