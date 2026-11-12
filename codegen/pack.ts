// Packs every locale's data into the tables `src/glintl/internal/render.gleam`
// reads. Each table is a tuple, numbered from 1, holding each item once.
//
// - tokens: each distinct token, as a term of `Token`.
// - patterns: a `Pattern`, whose tokens are 16-bit token numbers.
// - formats: 16-bit pattern numbers for each style, dates with times if they
//   aren't glued, then eras.
// - digits: a tuple of ten digits, for locales without ASCII digits.
// - locales: a digits number (0 for ASCII), the default hour cycle, then for
//   each calendar its formats, then its formats in each hour cycle, then for
//   each calendar its fields.
// - fields: what the matcher needs for a locale and calendar. The letter for
//   the locale's own hour, its entries, its texts, then its runs for each
//   field. Most fields' runs are the same in every calendar, so they're
//   shared.
// - field_entries: each stored pattern's skeleton and pattern, as numbers in
//   field_strings, then 1 if CLDR gave the skeleton.
// - field_texts: numbers in field_strings for the append items and display
//   names by field, the glues by style, then the decimal separator.
// - field_runs: each run's letter, length and flags, then its token.

import { CALENDARS } from "./calendars.ts";
import type { FieldsData } from "./fields.ts";
import { FIELD_COUNT, fieldOf, keyParts } from "./matcher.ts";
import { bytes, string } from "./erlang.ts";
import {
  type EraFormats,
  type Formats,
  type GluePiece,
  HOUR_CYCLES,
  type HourCycle,
  STYLES,
  type Token,
} from "./patterns.ts";

const STYLE_COUNT = STYLES.length;

const ASCII_DIGITS = "0123456789";

// How an era joins its dates to times, in the order of `render.gleam`.
const ERA_JOINED = 0;
const ERA_COMBINED = 1;
const ERA_GLUES = 2;

const BYTE = 0xff;
const BITS_PER_BYTE = 8;
const LARGEST_NUMBER = 0xffff;

// Numbers items from 1, because Erlang's `element` counts from 1. A repeat
// gets the number it had first.
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

// Writes a token as a term of `Token` in `render.gleam`.
function token(t: Token): string {
  switch (t.t) {
    case "literal":
      return `{literal,${string(t.value)}}`;
    case "ascii":
      return `{ascii_digits,${token(t.token)}}`;
    case "year":
      return `{year,${bool(t.twoDigit)},${t.minDigits},${string(t.minus)},${string(t.first)},${string(t.minusFirst)}}`;
    case "week_year":
      return `{week_year,${string(t.minus)},${bool(t.twoDigit)},${t.minDigits},${t.firstDay},${t.minimalDays},[${t.exceptions.map(([year, day]) => `{${year},${day}}`).join(",")}]}`;
    case "extended_year":
      return `{extended_year,${string(t.minus)},${bool(t.twoDigit)}}`;
    case "related_year":
      return `{related_year,${bool(t.pad)}}`;
    case "cycle_era":
      return "cycle_era";
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
    case "fraction":
      return `{fraction,${t.digits}}`;
    case "day_period":
      return `{day_period,${tuple(t.byHour.map(string))},${string(t.midnight)},${string(t.noon)}}`;
    case "zone":
      return `{zone,${[
        t.names,
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
  const fieldStrings = table();
  const fieldEntries = table();
  const fieldTexts = table();
  const fieldRuns = table();
  const fields = table();

  const fieldString = (s: string) => u16(fieldStrings.add(string(s)));

  function packFields(f: FieldsData): number {
    if (
      f.appendItems.length !== FIELD_COUNT ||
      f.displayNames.length !== FIELD_COUNT ||
      f.glues.length !== STYLE_COUNT
    ) {
      throw new Error("A field's texts are missing");
    }

    const entries = fieldEntries.add(
      bytes(
        f.entries.flatMap(([skeleton, pattern, specified]) => [
          ...fieldString(skeleton),
          ...fieldString(pattern),
          ...u8(specified ? 1 : 0),
        ]),
      ),
    );

    const texts = fieldTexts.add(
      bytes(
        [...f.appendItems, ...f.displayNames, ...f.glues, f.decimal].flatMap(
          fieldString,
        ),
      ),
    );

    const runs = Array.from({ length: FIELD_COUNT }, (_, field) =>
      fieldRuns.add(
        bytes(
          f.runs.flatMap(([key, t]) => {
            const [letter, length, flags] = keyParts(key);

            return fieldOf(letter) === field
              ? [
                  ...u8(letter.charCodeAt(0)),
                  ...u8(length),
                  ...u8(flags),
                  ...u16(tokens.add(token(t))),
                ]
              : [];
          }),
        ),
      ),
    );

    return fields.add(
      bytes([
        ...u8(f.hourLetter.charCodeAt(0)),
        ...u16(entries),
        ...u16(texts),
        ...runs.flatMap(u16),
      ]),
    );
  }

  // Adds a `Pattern` term and returns its number as two bytes.
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
      pieces.map((p) => {
        switch (p.t) {
          case "text":
            return `{literal,${string(p.value)}}`;
          case "token":
            return token(p.token);
          case "date":
            return "glue_date";
          case "time":
            return "glue_time";
        }
      }),
      false,
      false,
    );

  // Packs an era's dates, then how it joins them to times.
  const era = (e: EraFormats): number[] => [
    ...u8(e.era),
    ...e.dates.flatMap(tokensPattern),
    ...(e.combined
      ? [...u8(ERA_COMBINED), ...e.combined.flatMap(tokensPattern)]
      : e.glues
        ? [...u8(ERA_GLUES), ...e.glues.flatMap(gluePattern)]
        : u8(ERA_JOINED)),
  ];

  function packFormats(f: Formats): number {
    if (
      [f.dates, f.times, f.glues].some((s) => s.length !== STYLE_COUNT) ||
      (f.combined !== undefined &&
        f.combined.length !== STYLE_COUNT * STYLE_COUNT) ||
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
        ...(f.combined
          ? [...u8(1), ...f.combined.flatMap(tokensPattern)]
          : u8(0)),
        ...u8(f.eras.length),
        ...f.eras.flatMap(era),
      ]),
    );
  }

  // Adds a locale and returns its number in the locales table.
  function locale(
    localDigits: string[],
    hourCycle: HourCycle,
    all: Formats[][],
    allFields: FieldsData[],
  ): number {
    if (
      all.length !== CALENDARS.length ||
      allFields.length !== CALENDARS.length ||
      all.some((f) => f.length !== HOUR_CYCLES.length + 1)
    ) {
      throw new Error("A calendar or hour cycle is missing");
    }

    const digitsNumber =
      localDigits.join("") === ASCII_DIGITS
        ? 0
        : digits.add(tuple(localDigits.map(string)));

    return locales.add(
      bytes([
        ...u16(digitsNumber),
        ...u16(HOUR_CYCLES.indexOf(hourCycle)),
        ...all.flat().flatMap((f) => u16(packFormats(f))),
        ...allFields.flatMap((f) => u16(packFields(f))),
      ]),
    );
  }

  return {
    locale,
    // Gives each table as Erlang terms. Call it after adding every locale.
    tables: () => ({
      tokens: tokens.items,
      patterns: patterns.items,
      formats: formats.items,
      digits: digits.items,
      locales: locales.items,
      fields: fields.items,
      field_entries: fieldEntries.items,
      field_texts: fieldTexts.items,
      field_runs: fieldRuns.items,
      field_strings: fieldStrings.items,
    }),
  };
}
