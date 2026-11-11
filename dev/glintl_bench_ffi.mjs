/**
 * JavaScript has no way to count one function's allocations, so this only
 * measures time.
 * @param {() => undefined} f
 * @returns {[number, number]} Bytes allocated, always 0, and microseconds.
 */
export function measure(f) {
  const start = performance.now();
  f();
  return [0, Math.round((performance.now() - start) * 1000)];
}
