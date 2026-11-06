// Stops a script that reads Intl unless it runs on the pinned Bun on Linux.
// Other setups have other ICU data, like Apple's on a Mac, so they would make
// different patterns and fixtures.

import { readFileSync } from "node:fs";
import { join } from "node:path";

const PINNED = readFileSync(
  join(import.meta.dir, "..", ".bun-version"),
  "utf8",
).trim();

const DOCKER =
  'docker run --rm -v "$PWD":/repo -w /repo oven/bun:$(cat .bun-version) bun';

export function requirePinnedBun(script: string): void {
  if (process.platform === "linux" && Bun.version === PINNED) {
    return;
  }

  console.error(
    `${script} needs Bun ${PINNED} on Linux, but this is Bun ${Bun.version} on ${process.platform} with ICU ${process.versions.icu}. From the repo root, run:\n\n  ${DOCKER} ${script}`,
  );

  process.exit(1);
}
