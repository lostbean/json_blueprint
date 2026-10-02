import { Ok, Error } from "./gleam.mjs";
import * as fs from "node:fs";

export function read_file_to_string(path) {
  try {
    const str = fs.readFileSync(path, "utf-8");
    return new Ok(str);
  } catch (err) {
    return new Error(String(err));
  }
}
