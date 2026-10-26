// Writes data as Erlang terms matching `src/glintl/internal/data.gleam`.
//
// A module's data is one literal, so the BEAM keeps a single shared copy of
// it. To keep the files small, lists and patterns used more than once are
// bound to variables first; the compiler folds them back into the literal.

import type { Math_ } from "./calendars.ts";
import {
  type EraFormats,
  type Formats,
  type GluePiece,
  STYLES,
  type Token,
} from "./patterns.ts";

const STYLE_COUNT = STYLES.length;

// Characters that are hard to see are escaped, everything else is written as
// it is so the files are easy to review.
const INVISIBLE = /[\p{Cc}\p{Cf}\p{Z}]/u;

const HEXADECIMAL = 16;

// Terms shorter than this are written out each time, as a variable would
// barely be shorter.
const SHORTEST_SHARED = 24;

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

const string = (s: string) => `<<"${escape(s, (h) => `\\x{${h}}`)}"/utf8>>`;
const bool = (b: boolean) => (b ? "true" : "false");

// Builds terms, counting how often each list term is used, so `body` can
// bind repeated ones to variables.
export type Writer = ReturnType<typeof writer>;

export function writer() {
  const counts = new Map<string, number>();

  function shared(term: string): string {
    counts.set(term, (counts.get(term) ?? 0) + 1);

    return term;
  }

  function list(items: string[]): string {
    return shared(`[${items.join(", ")}]`);
  }

  function strings(items: string[]): string {
    return list(items.map(string));
  }

  function writeToken(token: Token): string {
    switch (token.t) {
      case "literal":
        return `{literal, ${string(token.value)}}`;
      case "ascii":
        return `{ascii_digits, ${writeToken(token.token)}}`;
      case "year":
        return `{year, ${bool(token.twoDigit)}, ${string(token.minus)}, ${string(token.first)}, ${string(token.minusFirst)}}`;
      case "week_year":
        return `{week_year, ${string(token.minus)}, ${token.firstDay}, ${token.minimalDays}, ${list(
          token.exceptions.map(([year, d]) => `{${year}, ${d}}`),
        )}}`;
      case "extended_year":
        return `{extended_year, ${string(token.minus)}}`;
      case "related_year":
        return "related_year";
      case "year_name":
      case "month_name":
      case "day_name":
      case "weekday":
      case "era":
        return `{${token.t}, ${strings(token.names)}}`;
      case "month_number":
      case "day":
      case "minute":
      case "second":
        return `{${token.t}, ${bool(token.pad)}}`;
      case "hour":
        return `{hour, ${bool(token.pad)}, ${token.cycle}}`;
      case "day_period":
        return `{day_period, ${strings(token.byHour)}, ${string(token.midnight)}, ${string(token.noon)}}`;
      case "zone":
        return `{zone, ${[
          string(token.zero),
          string(token.positive),
          string(token.positiveSuffix),
          string(token.positiveWholeSuffix),
          string(token.negative),
          string(token.negativeSuffix),
          string(token.negativeWholeSuffix),
          bool(token.padHours),
          string(token.separator),
          bool(token.optionalMinutes),
        ].join(", ")}}`;
    }
  }

  function pattern(tokens: Token[]): string {
    return list(tokens.map(writeToken));
  }

  function glue(pieces: GluePiece[]): string {
    return list(
      pieces.map((p) =>
        p.t === "text"
          ? `{glue_text, ${string(p.value)}}`
          : p.t === "date"
            ? "glue_date"
            : "glue_time",
      ),
    );
  }

  // One of something for each style, from full to short, like Gleam's
  // `Styles`.
  function styles<T>(items: T[], write: (item: T) => string): string {
    if (items.length !== STYLE_COUNT) {
      throw new Error("A style is missing");
    }

    return shared(`{styles, ${items.map(write).join(", ")}}`);
  }

  function era(era: EraFormats): string {
    const dates = styles(era.dates, pattern);
    // `combined` is by date style, then time style.
    const combined = era.combined;

    const byDate = combined
      ? `{combined, ${styles(
          era.dates.map((_, d) =>
            combined.slice(d * STYLE_COUNT, (d + 1) * STYLE_COUNT),
          ),
          (times) => styles(times, pattern),
        )}}`
      : "joined";

    return `{era_formats, ${era.era}, ${dates}, ${byDate}}`;
  }

  function formats(f: Formats): string {
    return `{formats,\n     ${[
      styles(f.dates, pattern),
      styles(f.times, pattern),
      styles(f.glues, glue),
      list(f.eras.map(era)),
    ].join(",\n     ")}}`;
  }

  function digits(digits: string[]): string {
    return digits.join("") === "0123456789"
      ? "ascii"
      : `{digits, ${strings(digits)}}`;
  }

  // The body of a function returning `term`, with repeated list terms bound
  // to variables. Shorter terms are bound first, so longer ones can use them.
  // Replacing text is safe: a list term always holds a string or a tuple,
  // and the escaped text of a string can't contain `<<"` or `{`.
  function body(term: string): string {
    const repeated = [...counts]
      .flatMap(([t, count]) =>
        count > 1 && t.length >= SHORTEST_SHARED && term.includes(t) ? [t] : [],
      )
      .sort((a, b) => a.length - b.length);

    const names = new Map(repeated.map((t, n) => [t, `V${n + 1}`]));

    const replace = (text: string, shorterThan: number) =>
      repeated
        .toReversed()
        .reduce(
          (replaced, t) =>
            t.length < shorterThan
              ? replaced.split(t).join(names.get(t)!)
              : replaced,
          text,
        );

    const bindings = repeated.map(
      (t) => `    ${names.get(t)} = ${replace(t, t.length)},\n`,
    );

    return `${bindings.join("")}    ${replace(term, Infinity)}`;
  }

  return {
    list,
    strings,
    token: writeToken,
    pattern,
    glue,
    styles,
    era,
    formats,
    digits,
    body,
  };
}

export function module(
  name: string,
  header: string,
  functions: [string, string][],
): string {
  return `${header}
-module(${name}).
-export([${functions.map(([f]) => `${f}/0`).join(", ")}]).
${functions.map(([f, body]) => `\n${f}() ->\n${body}.\n`).join("")}`;
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

  const tuple = (items: (string | number)[]) => `{${items.join(", ")}}`;

  const years = [...m.years]
    .reverse()
    .map(
      (y) =>
        `{year_rule, ${y.from}, ${y.era}, ${y.year}, ${y.yearStep}, ${y.extended}, ${y.related}, ${y.cycle}}`,
    );

  return `    {table,
     ${bool(m.cyclic)},
     ${tuple(m.starts)},
     ${tuple(m.layouts)},
     ${tuple(m.months.map((layout) => `[${layout.map(([n, l]) => `{${n}, ${l}}`).join(", ")}]`))},
     [${years.join(",\n      ")}],
     [${m.dayZero.map(([d, month]) => `{${d}, ${month}}`).join(", ")}]}`;
}
