// Writes data as Erlang terms matching `src/glintl/internal/data.gleam`.

import type { Math_ } from "./calendars.ts";
import {
  type EraFormats,
  type Formats,
  type GluePiece,
  STYLES,
  type Token,
} from "./patterns.ts";

const STYLE_COUNT = STYLES.length;

const INVISIBLE = /[\p{Cc}\p{Cf}\p{Z}]/u;

const HEXADECIMAL = 16;

// Shorter terms aren't worth a variable or a call.
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

export type Term =
  | { t: "text"; text: string }
  | { t: "list"; items: Term[] }
  | { t: "tuple"; items: Term[]; separator: string; repeatable: boolean };

const SEPARATOR = ", ";

const raw = (text: string): Term => ({ t: "text", text });

const string = (s: string) =>
  raw(`<<"${escape(s, (h) => `\\x{${h}}`)}"/utf8>>`);

const bool = (b: boolean) => raw(b ? "true" : "false");

const atom = raw;

const number = (n: number) => raw(`${n}`);

const list = (items: Term[]): Term => ({ t: "list", items });

const tuple = (items: Term[]): Term => ({
  t: "tuple",
  items,
  separator: SEPARATOR,
  repeatable: false,
});

const strings = (items: string[]) => list(items.map(string));

function write(
  term: Term,
  replace: (term: Term) => string | undefined,
): string {
  const replaced = replace(term);

  if (replaced !== undefined) {
    return replaced;
  }

  switch (term.t) {
    case "text":
      return term.text;
    case "list":
      return `[${term.items.map((item) => write(item, replace)).join(SEPARATOR)}]`;
    case "tuple":
      return `{${term.items.map((item) => write(item, replace)).join(term.separator)}}`;
  }
}

const texts = new WeakMap<Term, string>();

export function text(term: Term): string {
  const known = texts.get(term);

  if (known !== undefined) {
    return known;
  }

  const written = write(term, (item) =>
    item === term ? undefined : text(item),
  );

  texts.set(term, written);

  return written;
}

function subterms(term: Term): Term[] {
  return term.t === "text" ? [term] : [term, ...term.items.flatMap(subterms)];
}

function token(t: Token): Term {
  switch (t.t) {
    case "literal":
      return tuple([atom("literal"), string(t.value)]);
    case "ascii":
      return tuple([atom("ascii_digits"), token(t.token)]);
    case "year":
      return tuple([
        atom("year"),
        bool(t.twoDigit),
        string(t.minus),
        string(t.first),
        string(t.minusFirst),
      ]);
    case "week_year":
      return tuple([
        atom("week_year"),
        string(t.minus),
        number(t.firstDay),
        number(t.minimalDays),
        list(
          t.exceptions.map(([year, day]) => tuple([number(year), number(day)])),
        ),
      ]);
    case "extended_year":
      return tuple([atom("extended_year"), string(t.minus)]);
    case "related_year":
      return atom("related_year");
    case "year_name":
    case "month_name":
    case "day_name":
    case "weekday":
    case "era":
      return tuple([atom(t.t), strings(t.names)]);
    case "month_number":
    case "day":
    case "minute":
    case "second":
      return tuple([atom(t.t), bool(t.pad)]);
    case "hour":
      return tuple([atom("hour"), bool(t.pad), atom(t.cycle)]);
    case "day_period":
      return tuple([
        atom("day_period"),
        strings(t.byHour),
        string(t.midnight),
        string(t.noon),
      ]);
    case "zone":
      return tuple([
        atom("zone"),
        string(t.zero),
        string(t.positive),
        string(t.positiveSuffix),
        string(t.positiveWholeSuffix),
        string(t.negative),
        string(t.negativeSuffix),
        string(t.negativeWholeSuffix),
        bool(t.padHours),
        string(t.separator),
        bool(t.optionalMinutes),
      ]);
  }
}

const pattern = (tokens: Token[]) => list(tokens.map(token));

function glue(pieces: GluePiece[]): Term {
  return list(
    pieces.map((p) =>
      p.t === "text"
        ? tuple([atom("glue_text"), string(p.value)])
        : atom(p.t === "date" ? "glue_date" : "glue_time"),
    ),
  );
}

function styles<T>(items: T[], each: (item: T) => Term): Term {
  if (items.length !== STYLE_COUNT) {
    throw new Error("A style is missing");
  }

  return {
    t: "tuple",
    items: [atom("styles"), ...items.map(each)],
    separator: SEPARATOR,
    repeatable: true,
  };
}

function era(e: EraFormats): Term {
  // `combined` is by date style, then time style.
  const combined = e.combined;

  const byDate = combined
    ? tuple([
        atom("combined"),
        styles(
          e.dates.map((_, d) =>
            combined.slice(d * STYLE_COUNT, (d + 1) * STYLE_COUNT),
          ),
          (times) => styles(times, pattern),
        ),
      ])
    : atom("joined");

  return tuple([
    atom("era_formats"),
    number(e.era),
    styles(e.dates, pattern),
    byDate,
  ]);
}

const FORMATS_SEPARATOR = ",\n     ";

export function formats(f: Formats): Term {
  return {
    t: "tuple",
    items: [
      atom("formats"),
      styles(f.dates, pattern),
      styles(f.times, pattern),
      styles(f.glues, glue),
      list(f.eras.map(era)),
    ],
    separator: FORMATS_SEPARATOR,
    repeatable: false,
  };
}

export function digits(d: string[]): Term {
  return d.join("") === "0123456789"
    ? atom("ascii")
    : tuple([atom("digits"), strings(d)]);
}

export function data(d: string[], f: Formats): Term {
  return tuple([atom("data"), digits(d), formats(f)]);
}

const INDENT = "    ";

// Repeats in a literal are copied when it loads, so bind them to variables.
export function body(term: Term): string {
  const counts = subterms(term)
    .filter((t) => t.t === "list" || (t.t === "tuple" && t.repeatable))
    .reduce(
      (seen, t) => seen.set(text(t), (seen.get(text(t)) ?? 0) + 1),
      new Map<string, number>(),
    );

  const repeated = counts
    .entries()
    .filter(([t, count]) => count > 1 && t.length >= SHORTEST_SHARED)
    .map(([t]) => t)
    .toArray()
    .sort((a, b) => a.length - b.length);

  const names = new Map(repeated.map((t, n) => [t, `V${n + 1}`]));

  const firsts = new Map(
    subterms(term).map((t): [string, Term] => [text(t), t]),
  );

  const writeUsing = (self: Term) =>
    write(self, (t) => (t === self ? undefined : names.get(text(t))));

  const bindings = repeated.map(
    (t) => `${INDENT}${names.get(t)} = ${writeUsing(firsts.get(t)!)},\n`,
  );

  return `${bindings.join("")}${INDENT}${writeUsing(term)}`;
}

// Terms a language's calendars modules repeat, stored once as `piece/1`.
export type Pieces = { module: string; numbers: Map<string, number> };

export function pieces(module: string, terms: Term[]): Pieces {
  const counts = terms
    .flatMap(subterms)
    .values()
    .map(text)
    .filter((t) => t.length >= SHORTEST_SHARED)
    .reduce(
      (seen, t) => seen.set(t, (seen.get(t) ?? 0) + 1),
      new Map<string, number>(),
    );

  const numbers = new Map(
    counts
      .entries()
      .filter(([, count]) => count > 1)
      .map(([t], n): [string, number] => [t, n + 1]),
  );

  return { module, numbers };
}

function writeWith(term: Term, p: Pieces, self: Term | undefined): string {
  return write(term, (t) => {
    const n = t === self ? undefined : p.numbers.get(text(t));

    return n === undefined ? undefined : `${p.module}:piece(${n})`;
  });
}

export const using = (term: Term, p: Pieces) => writeWith(term, p, undefined);

export function pieceClauses(terms: Term[], p: Pieces): string[] {
  const firsts = new Map(
    terms.flatMap(subterms).map((t): [string, Term] => [text(t), t]),
  );

  return [...p.numbers].map(([t, n]) => {
    const term = firsts.get(t)!;

    return `piece(${n}) ->\n${INDENT}${writeWith(term, p, term)}`;
  });
}

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
