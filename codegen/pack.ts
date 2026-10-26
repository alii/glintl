// Packs every locale's data into the tables `src/glintl/internal/render.gleam`
// reads. Each table is a tuple, numbered from 1, holding each item once.
//
// - tokens: each distinct token, as a term of `Token`.
// - patterns: a `Pattern`, whose tokens are 16-bit token numbers.
// - formats: 16-bit pattern numbers for each style, then eras.
// - digits: a tuple of ten digits, for locales without ASCII digits.
// - locales: a digits number (0 for ASCII), then formats for each calendar.

import { CALENDARS } from "./calendars.ts";
import { bytes, string } from "./erlang.ts";
import {
  type EraFormats,
  type Formats,
  type GluePiece,
  STYLES,
  type Token,
} from "./patterns.ts";

const STYLE_COUNT = STYLES.length;

const ASCII_DIGITS = "0123456789";

const BYTE = 0xff;
const BITS_PER_BYTE = 8;
const LARGEST_NUMBER = 0xffff;

// Numbers items from 1, as Erlang's `element` does. A repeat gets the number
// it had first.
function table() {
  const numbers = new Map<string, number>();
  const items: string[] = [];

  function add(item: string): number {
    const known = numbers.get(item);

    if (known !== undefined) {
      return known;
    }

    items.push(item);
    const n = items.length;

    if (n > LARGEST_NUMBER) {
      throw new Error("Too many items for a 16-bit number");
    }

    numbers.set(item, n);

    return n;
  }

  return { add, items };
}

export function u8(n: number): number[] {
  if (n < 0 || n > BYTE) {
    throw new Error(`${n} doesn't fit in a byte`);
  }

  return [n];
}

const u16 = (n: number) => [(n >> BITS_PER_BYTE) & BYTE, n & BYTE];

const bool = (b: boolean) => (b ? "true" : "false");

const tuple = (items: string[]) => `{${items.join(",")}}`;

// A token as a term of `Token` in `render.gleam`.
function token(t: Token): string {
  switch (t.t) {
    case "literal":
      return `{literal,${string(t.value)}}`;
    case "ascii":
      return `{ascii_digits,${token(t.token)}}`;
    case "year":
      return `{year,${bool(t.twoDigit)},${string(t.minus)},${string(t.first)},${string(t.minusFirst)}}`;
    case "week_year":
      return `{week_year,${string(t.minus)},${t.firstDay},${t.minimalDays},[${t.exceptions.map(([year, day]) => `{${year},${day}}`).join(",")}]}`;
    case "extended_year":
      return `{extended_year,${string(t.minus)}}`;
    case "related_year":
      return "related_year";
    case "year_name":
    case "month_name":
    case "day_name":
    case "weekday":
    case "era":
      return `{${t.t},${tuple(t.names.map(string))}}`;
    case "month_number":
    case "day":
    case "minute":
    case "second":
      return `{${t.t},${bool(t.pad)}}`;
    case "hour":
      return `{hour,${bool(t.pad)},${t.cycle}}`;
    case "day_period":
      return `{day_period,${tuple(t.byHour.map(string))},${string(t.midnight)},${string(t.noon)}}`;
    case "zone":
      return `{zone,${[
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
      ].join(",")}}`;
  }
}

const has = (tokens: Token[], kind: Token["t"]): boolean =>
  tokens.some((t) => t.t === kind || (t.t === "ascii" && t.token.t === kind));

export function packer() {
  const tokens = table();
  const patterns = table();
  const formats = table();
  const digits = table();
  const locales = table();

  // A `Pattern` term's number, as two bytes.
  const pattern = (
    terms: string[],
    hasMinute: boolean,
    hasSecond: boolean,
  ): number[] =>
    u16(
      patterns.add(
        `{pattern,${bool(hasMinute)},${bool(hasSecond)},${bytes(terms.flatMap((t) => u16(tokens.add(t))))}}`,
      ),
    );

  const tokensPattern = (ts: Token[]) =>
    pattern(ts.map(token), has(ts, "minute"), has(ts, "second"));

  const gluePattern = (pieces: GluePiece[]) =>
    pattern(
      pieces.map((p) =>
        p.t === "text"
          ? `{literal,${string(p.value)}}`
          : p.t === "date"
            ? "glue_date"
            : "glue_time",
      ),
      false,
      false,
    );

  const era = (e: EraFormats): number[] => [
    ...u8(e.era),
    ...e.dates.flatMap(tokensPattern),
    ...(e.combined ? [...u8(1), ...e.combined.flatMap(tokensPattern)] : u8(0)),
  ];

  function packFormats(f: Formats): number {
    if (
      [f.dates, f.times, f.glues].some((s) => s.length !== STYLE_COUNT) ||
      f.eras.some(
        (e) =>
          e.dates.length !== STYLE_COUNT ||
          (e.combined !== undefined &&
            e.combined.length !== STYLE_COUNT * STYLE_COUNT),
      )
    ) {
      throw new Error("A style is missing");
    }

    return formats.add(
      bytes([
        ...f.dates.flatMap(tokensPattern),
        ...f.times.flatMap(tokensPattern),
        ...f.glues.flatMap(gluePattern),
        ...u8(f.eras.length),
        ...f.eras.flatMap(era),
      ]),
    );
  }

  // A locale's number in the locales table.
  function locale(localDigits: string[], all: Formats[]): number {
    if (all.length !== CALENDARS.length) {
      throw new Error("A calendar is missing");
    }

    const digitsNumber =
      localDigits.join("") === ASCII_DIGITS
        ? 0
        : digits.add(tuple(localDigits.map(string)));

    return locales.add(
      bytes([...u16(digitsNumber), ...all.flatMap((f) => u16(packFormats(f)))]),
    );
  }

  return {
    locale,
    // Each table as Erlang terms, once every locale is added.
    tables: () => ({
      tokens: tokens.items,
      patterns: patterns.items,
      formats: formats.items,
      digits: digits.items,
      locales: locales.items,
    }),
  };
}
