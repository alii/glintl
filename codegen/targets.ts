// Fails if `@target` is on a public definition other than an opaque type or
// an `@internal` one, as the compiler lets each target give it a different
// type.
//
//   bun codegen/targets.ts

import { Glob } from "bun";
import { join } from "node:path";

const ROOT = join(import.meta.dir, "..");

const files = await Array.fromAsync(
  new Glob("{src,test,dev}/**/*.gleam").scan(ROOT),
);

const problems = await Promise.all(
  files.map(async (file) => {
    const lines = (await Bun.file(join(ROOT, file)).text()).split("\n");

    return lines.flatMap((line, i) => {
      if (!line.startsWith("@target(")) {
        return [];
      }

      const rest = lines.slice(i);
      const end = rest.findIndex((l) => !l.startsWith("@"));
      const attributes = rest.slice(0, end);
      const definition = rest[end] ?? "";

      const allowed =
        !definition.startsWith("pub ") ||
        definition.startsWith("pub opaque type ") ||
        attributes.includes("@internal");

      return allowed ? [] : [`${file}:${i + 1}: ${definition}`];
    });
  }),
);

const all = problems.flat();

if (all.length > 0) {
  console.error(
    `\`@target\` on a public definition:\n${all.join("\n")}\n\nKeep public types and functions the same on every target.`,
  );
  process.exit(1);
}
