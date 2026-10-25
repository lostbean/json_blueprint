import { readFileSync } from "node:fs";

export function setting(name) {
  const value = process.env[name];
  if (value === undefined)
    throw new Error(`Missing benchmark setting: ${name}`);
  return value;
}

export function read_text(path) {
  return readFileSync(path, "utf8");
}
