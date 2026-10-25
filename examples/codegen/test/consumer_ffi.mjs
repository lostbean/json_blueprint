import { Ok, Error } from "./gleam.mjs";
import fs from "node:fs";
export function read_file(name) {
  try {
    return new Ok(fs.readFileSync(name, "utf8"));
  } catch (error) {
    return new Error(String(error));
  }
}
