import { Ok, Error } from "./gleam.mjs";
import * as fs from "node:fs";
import * as path from "node:path";

export function write_file(filePath, content) {
  try {
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    fs.writeFileSync(filePath, content, "utf-8");
    return new Ok(undefined);
  } catch (err) {
    return new Error(String(err));
  }
}

export function make_directory(dirPath) {
  try {
    fs.mkdirSync(dirPath, { recursive: true });
    return new Ok(undefined);
  } catch (err) {
    return new Error(String(err));
  }
}
