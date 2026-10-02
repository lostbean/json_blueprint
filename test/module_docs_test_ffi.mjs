import { toList } from "./gleam.mjs";
import * as fs from "node:fs";
import * as path from "node:path";

function walk(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(directory, entry.name);
    return entry.isDirectory() ? walk(full) : [full];
  });
}

// Every module under src/ that is not internal, with its source text.
export function public_sources() {
  const paths = walk("src")
    .filter((p) => p.endsWith(".gleam") && !p.includes("/internal/"))
    .sort();
  return toList(paths.map((p) => [p, fs.readFileSync(p, "utf-8")]));
}
