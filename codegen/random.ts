// A small seeded random number generator, so generated files and test runs
// only change when ICU does, or when the seed does. This is mulberry32, by
// Tommy Ettinger; its numbers are part of the algorithm as published.
export function random(seed: number): () => number {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    const t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    const u = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;

    return ((u ^ (u >>> 14)) >>> 0) / 4294967296;
  };
}
