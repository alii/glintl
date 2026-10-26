// Packs locale data into the binaries `src/glintl/internal/render.gleam`
// reads. Each table is a tuple, numbered from 1, and repeats are stored once.
//
// - ops: the `Op` for each op byte.
// - strings: every piece of text.
// - lists: lists of names, as tuples of string numbers.
// - patterns: a flags byte, then tokens, each an op byte and its fields.
// - formats: 16-bit pattern numbers for each style, then eras.
// - locales: a digits list (0 for ASCII), then formats for each calendar.

import { CALENDARS } from "./calendars.ts";
import {
  type EraFormats,
  type Formats,
  type GluePiece,
  STYLES,
  type Token,
} from "./patterns.ts";

const STYLE_COUNT = STYLES.length;

// Op bytes, most common first. Written to `glintl_generated_data:ops/0` as
// the atoms of `Op` in `render.gleam`, like `day_op`.
export const OPS = [
  "literal",
  "day",
  "month_name",
  "year",
  "hour",
  "minute",
  "month_number",
  "weekday",
  "second",
  "day_period",
  "era",
  "zone",
  "glue_date",
  "glue_time",
  "ascii",
  "week_year",
  "extended_year",
  "related_year",
  "year_name",
  "day_name",
] as const;

// In the order of `HourCycle` in `render.gleam`.
const CYCLES = ["h11", "h12", "h23", "h24"] as const;

const HAS_MINUTE = 1;
const HAS_SECOND = 2;

const BYTE = 0xff;
const BITS_PER_BYTE = 8;
const LARGEST_NUMBER = 0xffff;
const INT_BYTES = 4;

// Numbers things from 1, as Erlang's `element` does, giving repeats the
// number they had first.
function table<T>(key: (item: T) => string) {
  const numbers = new Map<string, number>();
  const items: T[] = [];

  function add(item: T): number {
    const k = key(item);
    const known = numbers.get(k);

    if (known !== undefined) {
      return known;
    }

    items.push(item);
    const n = items.length;

    if (n > LARGEST_NUMBER) {
      throw new Error("Too many items for a 16-bit number");
    }

    numbers.set(k, n);

    return n;
  }

  return { add, items };
}

function u8(n: number): number[] {
  if (n < 0 || n > BYTE) {
    throw new Error(`${n} doesn't fit in a byte`);
  }

  return [n];
}

const u16 = (n: number) => [(n >> BITS_PER_BYTE) & BYTE, n & BYTE];

const i32 = (n: number) =>
  Array.from(
    { length: INT_BYTES },
    (_, i) => (n >> ((INT_BYTES - 1 - i) * BITS_PER_BYTE)) & BYTE,
  );

const flag = (b: boolean) => u8(b ? 1 : 0);

const op = (name: (typeof OPS)[number]) => u8(OPS.indexOf(name));

export function packer() {
  const strings = table((s: string) => s);
  const lists = table((l: number[]) => l.join(","));
  const patterns = table((p: number[]) => p.join(","));
  const formats = table((f: number[]) => f.join(","));
  const locales = table((l: number[]) => l.join(","));

  const str = (s: string) => u16(strings.add(s));
  const list = (names: string[]) => u16(lists.add(names.map(strings.add)));

  function token(t: Token): number[] {
    switch (t.t) {
      case "literal":
        return [...op("literal"), ...str(t.value)];
      case "ascii":
        return [...op("ascii"), ...token(t.token)];
      case "year":
        return [
          ...op("year"),
          ...flag(t.twoDigit),
          ...str(t.minus),
          ...str(t.first),
          ...str(t.minusFirst),
        ];
      case "week_year":
        return [
          ...op("week_year"),
          ...str(t.minus),
          ...u8(t.firstDay),
          ...u8(t.minimalDays),
          ...u8(t.exceptions.length),
          ...t.exceptions.flatMap(([year, day]) => [...i32(year), ...i32(day)]),
        ];
      case "extended_year":
        return [...op("extended_year"), ...str(t.minus)];
      case "related_year":
        return op("related_year");
      case "year_name":
      case "month_name":
      case "day_name":
      case "weekday":
      case "era":
        return [...op(t.t), ...list(t.names)];
      case "month_number":
      case "day":
      case "minute":
      case "second":
        return [...op(t.t), ...flag(t.pad)];
      case "hour":
        return [...op("hour"), ...flag(t.pad), ...u8(CYCLES.indexOf(t.cycle))];
      case "day_period":
        return [
          ...op("day_period"),
          ...list(t.byHour),
          ...str(t.midnight),
          ...str(t.noon),
        ];
      case "zone":
        return [
          ...op("zone"),
          ...str(t.zero),
          ...str(t.positive),
          ...str(t.positiveSuffix),
          ...str(t.positiveWholeSuffix),
          ...str(t.negative),
          ...str(t.negativeSuffix),
          ...str(t.negativeWholeSuffix),
          ...flag(t.padHours),
          ...str(t.separator),
          ...flag(t.optionalMinutes),
        ];
    }
  }

  const has = (tokens: Token[], kind: Token["t"]): boolean =>
    tokens.some((t) => t.t === kind || (t.t === "ascii" && t.token.t === kind));

  function pattern(tokens: Token[]): number[] {
    const flags =
      (has(tokens, "minute") ? HAS_MINUTE : 0) |
      (has(tokens, "second") ? HAS_SECOND : 0);

    return u16(patterns.add([...u8(flags), ...tokens.flatMap(token)]));
  }

  function glue(pieces: GluePiece[]): number[] {
    const tokens = pieces.flatMap((p) =>
      p.t === "text"
        ? [...op("literal"), ...str(p.value)]
        : op(p.t === "date" ? "glue_date" : "glue_time"),
    );

    return u16(patterns.add([...u8(0), ...tokens]));
  }

  function era(e: EraFormats): number[] {
    return [
      ...u8(e.era),
      ...e.dates.flatMap(pattern),
      ...(e.combined
        ? [...flag(true), ...e.combined.flatMap(pattern)]
        : flag(false)),
    ];
  }

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

    return formats.add([
      ...f.dates.flatMap(pattern),
      ...f.times.flatMap(pattern),
      ...f.glues.flatMap(glue),
      ...u8(f.eras.length),
      ...f.eras.flatMap(era),
    ]);
  }

  // A locale's number in the locales table.
  function locale(digits: string[], all: Formats[]): number {
    if (all.length !== CALENDARS.length) {
      throw new Error("A calendar is missing");
    }

    const digitsList =
      digits.join("") === "0123456789" ? 0 : lists.add(digits.map(strings.add));

    return locales.add([
      ...u16(digitsList),
      ...all.flatMap((f) => u16(packFormats(f))),
    ]);
  }

  return {
    locale,
    // Called after every locale is added.
    tables: () => ({
      strings: strings.items,
      lists: lists.items,
      patterns: patterns.items,
      formats: formats.items,
      locales: locales.items,
    }),
  };
}
