import { Ok, Error } from "./gleam.mjs";
import fs from "node:fs";
import path from "node:path";
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
    fs.writeFileSync(name, content);
    return new Ok(undefined);
  } catch (error) {
    return new Error(String(error));
  }
}
export function output_directory() {
  return process.env.SCHEMA_OUTPUT || "../src";
}

export function monotonic_nanos() {
  return Number(process.hrtime.bigint());
}
export function consume(value) {
  globalThis.__schema_generation_benchmark_sink = value;
}
