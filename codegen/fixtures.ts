// Expected output for the Gleam tests, from Intl.DateTimeFormat. Every case
// is checked on both targets.

import {
  CALENDARS,
  type CalendarId,
  type Math_,
  calendarDate,
  day,
} from "./calendars.ts";
import { escape } from "./erlang.ts";
import { STYLES } from "./patterns.ts";

// Date style and time style, each 0 for none or 1 to 4 for full to short.
type Pair = [number, number];

const PAIRS: Pair[] = [];
for (let d = 0; d < 5; d++)
  for (let t = 0; t < 5; t++) if (d || t) PAIRS.push([d, t]);

// Locales with something odd in at least one calendar.
const EDGE_LOCALES = ["en-GB", "ja", "zh", "ko", "ar-SA", "fa", "gl", "ak"];

const OFFSETS = [0, 60, -480, 330, 345, -210, 840, -600, 525];

// Seeded, so the fixtures only change when ICU does.
function random(seed: number): () => number {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// [Unix seconds, offset in minutes]
type Moment = [number, number];

function at(
  epochDay: number,
  hour: number,
  minute: number,
  second: number,
  offset: number,
): Moment {
  return [
    epochDay * 86400 + (hour * 60 + minute) * 60 + second - offset * 60,
    offset,
  ];
}

function moments(): Moment[] {
  const next = random(42);
  const result: Moment[] = [
    at(day(2026, 3, 5), 0, 0, 0, 0),
    at(day(2026, 3, 5), 12, 0, 0, 0),
    at(day(2026, 3, 5), 12, 30, 0, 0),
    at(day(2026, 12, 31), 23, 59, 59, 60),
    at(day(5, 7, 1), 8, 0, 0, -480),
    at(day(-100, 3, 5), 15, 0, 0, 330),
    at(day(1999, 12, 31), 23, 0, 0, 60),
  ];
  for (let i = 0; i < 8; i++) {
    const d =
      day(1 + Math.floor(next() * 2400), 1, 1) + Math.floor(next() * 366);
    result.push(at(d, 0, 0, 0, OFFSETS[Math.floor(next() * OFFSETS.length)]!));
  }
  return result;
}

// Days worth checking in a calendar: era changes, leap months, the edges of
// its table, and odd years.
function edgeDays(math: Math_): number[] {
  const days = new Set<number>([day(2026, 3, 5)]);
  if (math.kind === "proleptic") {
    const starts = math.eras.map((e) => e.start).filter(Number.isFinite);
    for (const start of starts.slice(0, 4)) days.add(start - 1).add(start);
    days
      .add(day(-1000, 6, 1))
      .add(day(1, 1, 1))
      .add(day(1582, 10, 15));
  } else {
    const first = math.starts[0]!;
    const last = math.starts.at(-1)! - 1;
    days.add(first).add(last);
    for (const d of math.eraDays) days.add(d);
    // Every month name, in its occurrence nearest 2026.
    const target = day(2026, 3, 5);
    math.shapes.forEach((shape, i) => {
      if (Math.abs(math.starts[i]! - target) > 365 * 40) return;
      let start = math.starts[i]!;
      for (const [, length] of math.months[shape]!) {
        days.add(start + 3);
        start += length;
      }
    });
  }
  return [...days].sort((a, b) => a - b).slice(0, 60);
}

function offsetString(minutes: number): string {
  const sign = minutes < 0 ? "-" : "+";
  const abs = Math.abs(minutes);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${sign}${pad(Math.floor(abs / 60))}:${pad(abs % 60)}`;
}

const formatters = new Map<string, Intl.DateTimeFormat>();
function expected(
  tag: string,
  calendar: string,
  [d, t]: Pair,
  [seconds, offset]: Moment,
): string {
  const key = `${tag} ${calendar} ${d} ${t} ${offset}`;
  let f = formatters.get(key);
  if (!f) {
    f = new Intl.DateTimeFormat(tag, {
      calendar,
      timeZone: offsetString(offset),
      dateStyle: d ? STYLES[d - 1] : undefined,
      timeStyle: t ? STYLES[t - 1] : undefined,
    });
    formatters.set(key, f);
    if (formatters.size > 5000) formatters.clear();
  }
  return f.format(seconds * 1000);
}

const gleamString = (s: string) => `"${escape(s, (h) => `\\u{${h}}`)}"`;

export function fixtures(
  locales: [string, string][],
  mathFor: (id: CalendarId) => Math_,
  runtime: string,
): string {
  const all = moments();
  // Table calendars only cover years 1 to 4000 on Erlang.
  const covered = (calendar: string, [seconds, offset]: Moment) =>
    calendarDate(
      mathFor(calendar as CalendarId),
      Math.floor((seconds + offset * 60) / 86400),
    ) !== undefined;
  const lines: string[] = [];
  const add = (
    tag: string,
    calendar: string,
    isDefault: boolean,
    pair: Pair,
    moment: Moment,
  ) => {
    if (!covered(calendar, moment)) return;
    lines.push(
      `    #("${tag}", "${isDefault ? "" : calendar}", ${pair[0]}, ${pair[1]}, ${moment[0]}, ${moment[1]}, ${gleamString(
        expected(tag, calendar, pair, moment),
      )}),`,
    );
  };

  // Every locale and style pair in the locale's own calendar.
  let turn = 0;
  for (const [tag, calendar] of locales)
    for (const pair of PAIRS)
      add(tag, calendar, true, pair, all[turn++ % all.length]!);

  // Every locale in every other calendar, with styles and moments taking turns.
  for (const [tag, calendar] of locales)
    for (const { id } of CALENDARS)
      if (id !== calendar)
        add(
          tag,
          id,
          false,
          PAIRS[turn % PAIRS.length]!,
          all[turn++ % all.length]!,
        );

  // The odd days of each calendar, in locales with odd formats.
  const pairs: Pair[] = [
    [1, 0],
    [2, 0],
    [3, 0],
    [4, 0],
    [1, 1],
    [4, 4],
  ];
  for (const tag of EDGE_LOCALES) {
    const calendar = locales.find(([t]) => t === tag)?.[1];
    if (!calendar) continue;
    for (const { id } of CALENDARS)
      for (const d of edgeDays(mathFor(id)))
        for (const pair of pairs)
          add(tag, id, id === calendar, pair, at(d, 9, 7, 4, 0));
  }

  return `//// Expected output, made with \`Intl.DateTimeFormat\` in ${runtime}.
//// Generated by \`codegen/generate.ts\`. Do not edit.

/// Locale tag, calendar (empty for the locale's own), date style, time style,
/// Unix seconds, offset minutes, output. Styles are 0 for none, then full,
/// long, medium, short.
pub fn cases() -> List(#(String, String, Int, Int, Int, Int, String)) {
  [
${lines.join("\n")}
  ]
}
`;
}

// Raw calendar fields for days in every calendar, to check the Erlang
// calendar maths directly rather than through formatted text.
export function calendarFixtures(
  mathFor: (id: CalendarId) => Math_,
  runtime: string,
): string {
  const next = random(7);
  const lines: string[] = [];
  CALENDARS.forEach(({ id }, index) => {
    const math = mathFor(id);
    const days = new Set(edgeDays(math));
    if (math.kind === "table") {
      const first = math.starts[0]!;
      const last = math.starts.at(-1)!;
      days
        .add(first - 1)
        .add(last)
        .add(last - 1);
      // The first day of a year, and the last, for every 40th year.
      for (let i = 0; i < math.starts.length - 1; i += 40)
        days.add(math.starts[i]!).add(math.starts[i + 1]! - 1);
      for (let n = 0; n < 300; n++)
        days.add(first + Math.floor(next() * (last - first)));
    } else {
      for (const era of math.eras)
        if (Number.isFinite(era.start)) days.add(era.start - 1).add(era.start);
      for (let n = 0; n < 300; n++)
        days.add(day(-5000, 1, 1) + Math.floor(next() * 3_300_000));
    }
    for (const d of [...days].sort((a, b) => a - b)) {
      const c = calendarDate(math, d);
      const fields = c
        ? [c.era, c.year, c.extended, c.related, c.cycle, c.month, c.day].join(
            ", ",
          )
        : "";
      lines.push(`    #(${index}, ${d}, [${fields}]),`);
    }
  });
  return `//// Calendar fields, from glintl's calendar maths after checking it against
//// \`Intl.DateTimeFormat\` on every day, in ${runtime}.
//// Generated by \`codegen/generate.ts\`. Do not edit.

/// Calendar (by \`glintl.Calendar\` order), days since 1970-01-01, and the era,
/// year, extended year, related year, cycle year, month and day. Empty when
/// the calendar's table doesn't cover the day.
pub fn cases() -> List(#(Int, Int, List(Int))) {
  [
${lines.join("\n")}
  ]
}
`;
}
