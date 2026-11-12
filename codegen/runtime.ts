// Stops a script that reads Intl unless it runs on the pinned Bun on Linux.
// Other setups have other ICU data, like Apple's on a Mac, so they would make
// different patterns and fixtures.
//
// `.bun-image` pins a Docker image by digest, then the build of Bun in it. A
// canary calls itself the same version as the release before it, so the build
// is what tells them apart.

import { readFileSync } from "node:fs";
import { join } from "node:path";

const [IMAGE, REVISION] = readFileSync(
  join(import.meta.dir, "..", ".bun-image"),
  "utf8",
)
  .trim()
  .split("\n");

const DOCKER =
  'docker run --rm -v "$PWD":/repo -w /repo $(head -n1 .bun-image) bun';

export function requirePinnedBun(script: string): void {
  if (process.platform === "linux" && Bun.revision === REVISION) {
    return;
  }

  console.error(
    `${script} needs the Bun in ${IMAGE}, build ${REVISION}, on Linux. This is Bun ${Bun.version}, build ${Bun.revision}, on ${process.platform} with ICU ${process.versions.icu}. From the repo root, run:\n\n  ${DOCKER} ${script}`,
  );

  process.exit(1);
}
