/**
 * JavaScript has no way to count one function's allocations or reductions,
 * so `measure` only measures time.
 * @param {() => undefined} f
 * @returns {[number, number, number]} Bytes allocated, always 0,
 *   microseconds, and reductions, always 0.
 */
export function measure(f) {
  const start = performance.now();
  f();
  return [0, Math.round((performance.now() - start) * 1000), 0];
}
