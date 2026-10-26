// JavaScript has no way to count one function's allocations, so this only
// measures time.
export function measure(f) {
  const start = performance.now();
  f();
  return [0, Math.round((performance.now() - start) * 1000)];
}

export function code_bytes() {
  return 0;
}
