import { BitArray, toList } from "./gleam.mjs";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

export function read_cases() {
  const root = process.env.BLUEPRINT_PARSER_CORPUS;
  return toList(
    readdirSync(root)
      .filter((name) => name.endsWith(".json"))
      .sort()
      .map((name) => [name, new BitArray(readFileSync(join(root, name)))]),
  );
}
