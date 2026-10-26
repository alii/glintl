// Writes Erlang source for the generated modules.

import type { Math_ } from "./calendars.ts";

const INVISIBLE = /[\p{Cc}\p{Cf}\p{Z}]/u;

const HEXADECIMAL = 16;

export function escape(s: string, hex: (code: string) => string): string {
  return [...s]
    .map((c) => {
      if (c === "\\") {
        return "\\\\";
      }

      if (c === '"') {
        return '\\"';
      }

      if (c === " ") {
        return c;
      }

      if (INVISIBLE.test(c)) {
        return hex(c.codePointAt(0)!.toString(HEXADECIMAL).toUpperCase());
      }

      return c;
    })
    .join("");
}

export const string = (s: string) =>
  `<<"${escape(s, (h) => `\\x{${h}}`)}"/utf8>>`;

export const bytes = (b: number[]) => `<<${b.join(",")}>>`;

export const tuple = (items: string[]) => `{\n    ${items.join(",\n    ")}\n}`;

export function module(
  name: string,
  header: string,
  exports: string[],
  functions: string[][],
): string {
  return `${header}
-module(${name}).
-export([${exports.join(", ")}]).
${functions.map((clauses) => `\n${clauses.join(";\n")}.\n`).join("")}`;
}

// A big negative number standing in for the start of time.
const START_OF_TIME = -1_000_000_000_000;

export function math(m: Math_): string {
  if (m.kind === "proleptic") {
    const rules = m.eras.map(
      (e) =>
        `{era_rule, ${Number.isFinite(e.start) ? e.start : START_OF_TIME}, ${e.era}, ${e.base}, ${e.sign}}`,
    );

    const julianBefore = Number.isFinite(m.julianBefore)
      ? m.julianBefore
      : START_OF_TIME;

    return `    {proleptic, [\n        ${rules.join(",\n        ")}\n    ], ${julianBefore}}`;
  }

  const items = (values: (string | number)[]) => `{${values.join(", ")}}`;

  const years = [...m.years]
    .reverse()
    .map(
      (y) =>
        `{year_rule, ${y.from}, ${y.era}, ${y.year}, ${y.yearStep}, ${y.extended}, ${y.related}, ${y.cycle}}`,
    );

  return `    {table,
     ${m.cyclic ? "true" : "false"},
     ${items(m.starts)},
     ${items(m.layouts)},
     ${items(m.months.map((layout) => `[${layout.map(([n, l]) => `{${n}, ${l}}`).join(", ")}]`))},
     [${years.join(",\n      ")}],
     [${m.dayZero.map(([d, month]) => `{${d}, ${month}}`).join(", ")}]}`;
}
