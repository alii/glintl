// Writes data as Erlang terms matching `src/glintl/internal/data.gleam`.
//
// A module's data is one literal, so the BEAM keeps a single shared copy of
// it. To keep the files small, lists and patterns used more than once are
// bound to variables first; the compiler folds them back into the literal.

import type { Math_ } from "./calendars.ts";
import type { EraFormats, Formats, GluePiece, Token } from "./patterns.ts";

// Characters that are hard to see are escaped, everything else is written as
// it is so the files are easy to review.
const INVISIBLE = /[\p{Cc}\p{Cf}\p{Z}]/u;

export function escape(s: string, hex: (code: string) => string): string {
  return [...s]
    .map((c) => {
      if (c === "\\") return "\\\\";
      if (c === '"') return '\\"';
      if (c === " ") return c;
      if (INVISIBLE.test(c))
        return hex(c.codePointAt(0)!.toString(16).toUpperCase());
      return c;
    })
    .join("");
}

const string = (s: string) => `<<"${escape(s, (h) => `\\x{${h}}`)}"/utf8>>`;
const bool = (b: boolean) => (b ? "true" : "false");

// Builds terms, counting how often each list term is used, so `body` can
// bind repeated ones to variables.
export class Writer {
  private counts = new Map<string, number>();

  private shared(term: string): string {
    this.counts.set(term, (this.counts.get(term) ?? 0) + 1);
    return term;
  }

  list(items: string[]): string {
    return this.shared(`[${items.join(", ")}]`);
  }

  strings(items: string[]): string {
    return this.list(items.map(string));
  }

  token(token: Token): string {
    switch (token.t) {
      case "literal":
        return `{literal, ${string(token.value)}}`;
      case "ascii":
        return `{ascii_digits, ${this.token(token.token)}}`;
      case "year":
        return `{year, ${bool(token.twoDigit)}, ${string(token.minus)}, ${string(token.first)}}`;
      case "week_year":
        return `{week_year, ${string(token.minus)}, ${token.firstDay}, ${token.minimalDays}, ${this.list(
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
        return `{${token.t}, ${this.strings(token.names)}}`;
      case "month_number":
      case "day":
      case "minute":
      case "second":
        return `{${token.t}, ${bool(token.pad)}}`;
      case "hour":
        return `{hour, ${bool(token.pad)}, ${token.cycle}}`;
      case "day_period":
        return `{day_period, ${this.strings(token.byHour)}, ${string(token.midnight)}, ${string(token.noon)}}`;
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

  pattern(tokens: Token[]): string {
    return this.list(tokens.map((t) => this.token(t)));
  }

  glue(pieces: GluePiece[]): string {
    return this.list(
      pieces.map((p) =>
        p.t === "text"
          ? `{glue_text, ${string(p.value)}}`
          : p.t === "date"
            ? "glue_date"
            : "glue_time",
      ),
    );
  }

  era(era: EraFormats): string {
    return `{era_formats, ${era.era}, ${this.list(era.dates.map((p) => this.pattern(p)))}, ${this.list(
      (era.combined ?? []).map((p) => this.pattern(p)),
    )}}`;
  }

  formats(f: Formats): string {
    return `{formats,\n     ${[
      this.list(f.dates.map((p) => this.pattern(p))),
      this.list(f.times.map((p) => this.pattern(p))),
      this.list(f.glues.map((g) => this.glue(g))),
      this.list(f.eras.map((e) => this.era(e))),
    ].join(",\n     ")}}`;
  }

  digits(digits: string[]): string {
    return digits.join("") === "0123456789"
      ? "ascii"
      : `{digits, ${this.strings(digits)}}`;
  }

  // The body of a function returning `term`, with repeated list terms bound
  // to variables. Shorter terms are bound first, so longer ones can use them.
  // Replacing text is safe: a list term always holds a string or a tuple,
  // and the escaped text of a string can't contain `<<"` or `{`.
  body(term: string): string {
    const repeated = [...this.counts]
      .filter(([t, count]) => count > 1 && t.length >= 24 && term.includes(t))
      .map(([t]) => t)
      .sort((a, b) => a.length - b.length);
    const names = new Map(repeated.map((t, n) => [t, `V${n + 1}`]));
    const replace = (text: string, shorterThan: number) => {
      for (const t of [...repeated].reverse())
        if (t.length < shorterThan) text = text.split(t).join(names.get(t)!);
      return text;
    };
    const bindings = repeated.map(
      (t) => `    ${names.get(t)} = ${replace(t, t.length)},\n`,
    );
    return `${bindings.join("")}    ${replace(term, Infinity)}`;
  }
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
    return `    {proleptic, [\n        ${rules.join(",\n        ")}\n    ]}`;
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
     ${tuple(m.shapes)},
     ${tuple(m.months.map((shape) => `[${shape.map(([n, l]) => `{${n}, ${l}}`).join(", ")}]`))},
     [${years.join(",\n      ")}],
     [${m.dayZero.map(([d, month]) => `{${d}, ${month}}`).join(", ")}]}`;
}
