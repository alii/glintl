// Expected output for the Gleam tests, from Intl.DateTimeFormat. Every case
// is checked on both targets.

import {
  CALENDARS,
  type CalendarId,
  LAST_YEAR,
  MID_YEAR,
  MONTHS_PER_YEAR,
  type Math_,
  SCAN_FROM,
  calendarDate,
  day,
} from "./calendars.ts";
import { escape } from "./erlang.ts";
import { STYLES } from "./patterns.ts";
import { random } from "./random.ts";
import {
  HOURS_PER_HALF_DAY,
  MINUTES_PER_HOUR,
  MS_PER_SECOND,
  SECONDS_PER_DAY,
  SECONDS_PER_MINUTE,
  offsetString,
} from "./time.ts";

// Date style and time style, each 0 for none or 1 to 4 for full to short.
type Pair = [number, number];

const PAIRS: Pair[] = [];
for (let d = 0; d <= STYLES.length; d++)
  for (let t = 0; t <= STYLES.length; t++) if (d || t) PAIRS.push([d, t]);

// Locales with something odd in at least one calendar.
const EDGE_LOCALES = ["en-GB", "ja", "zh", "ko", "ar-SA", "fa", "gl", "ak"];

// Offsets in minutes, including half and quarter hours, and both ends of the
// world: +1, -8, +5:30, +5:45, -3:30, +14, -10 and +8:45.
const OFFSETS = [0, 60, -480, 330, 345, -210, 840, -600, 525];

const MOMENT_SEED = 42;
const FIELDS_SEED = 7;

// How many random moments to add to the fixed ones, and the years they come
// from.
const RANDOM_MOMENTS = 8;
const RANDOM_MOMENT_YEARS = 2400;
const DAYS_IN_LONGEST_YEAR = 366;

// Months to sample in each table calendar are the ones this many years
// either side of the probe day.
const SAMPLE_MONTHS_WITHIN_YEARS = 40;
const DAYS_IN_YEAR = 365;

// A few days into each month, to land in even the shortest.
const INTO_MONTH = 3;

// At most this many edge days per calendar, and era starts per calendar
// with Gregorian months.
const MOST_EDGE_DAYS = 60;
const MOST_ERA_STARTS = 4;

// How many random days to check calendar fields on, and every how many
// table years to check the first and last day of.
const RANDOM_FIELD_DAYS = 300;
const EVERY_NTH_YEAR = 40;

// Intl formatters are slow to make, so some are kept, but not too many.
const MOST_FORMATTERS = 5000;

const PROBE_DAY = day(2026, 3, 5);

// The time of day edge days are checked at: every number is different.
const EDGE_TIME: [number, number, number] = [9, 7, 4];

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
    epochDay * SECONDS_PER_DAY +
      (hour * MINUTES_PER_HOUR + minute) * SECONDS_PER_MINUTE +
      second -
      offset * SECONDS_PER_MINUTE,
    offset,
  ];
}

// Moments every locale is checked on: midnight, noon, half past noon, the
// last second of a year, a year with one digit, a year BC, and the turn of
// a millennium, then some at random.
function moments(): Moment[] {
  const next = random(MOMENT_SEED);
  const [plusOne, minusEight, plusFiveThirty] = [
    OFFSETS[1]!,
    OFFSETS[2]!,
    OFFSETS[3]!,
  ];
  const result: Moment[] = [
    at(PROBE_DAY, 0, 0, 0, 0),
    at(PROBE_DAY, HOURS_PER_HALF_DAY, 0, 0, 0),
    at(PROBE_DAY, HOURS_PER_HALF_DAY, MINUTES_PER_HOUR / 2, 0, 0),
    at(day(2026, MONTHS_PER_YEAR, 31), 23, 59, 59, plusOne),
    at(day(5, ...MID_YEAR), 8, 0, 0, minusEight),
    at(day(-100, 3, 5), 15, 0, 0, plusFiveThirty),
    at(day(1999, MONTHS_PER_YEAR, 31), 23, 0, 0, plusOne),
  ];
  for (let i = 0; i < RANDOM_MOMENTS; i++) {
    const d =
      day(1 + Math.floor(next() * RANDOM_MOMENT_YEARS), 1, 1) +
      Math.floor(next() * DAYS_IN_LONGEST_YEAR);
    result.push(at(d, 0, 0, 0, OFFSETS[Math.floor(next() * OFFSETS.length)]!));
  }
  return result;
}

// The day ICU's calendars switch from Julian dates, and the day before.
const GREGORIAN_REFORM = day(1582, 10, 15);

// Days worth checking in a calendar: era changes, leap months, the edges of
// its table, and odd years.
function edgeDays(math: Math_): number[] {
  const days = new Set<number>([PROBE_DAY]);
  if (math.kind === "proleptic") {
    const starts = math.eras.map((e) => e.start).filter(Number.isFinite);
    for (const start of starts.slice(0, MOST_ERA_STARTS))
      days.add(start - 1).add(start);
    days
      .add(day(-1000, ...MID_YEAR))
      .add(day(1, 1, 1))
      .add(GREGORIAN_REFORM)
      .add(GREGORIAN_REFORM - 1);
  } else {
    const first = math.starts[0]!;
    const last = math.starts.at(-1)! - 1;
    days.add(first).add(last);
    for (const d of math.eraDays) days.add(d);
    // Every month name, in the years around the probe day.
    math.shapes.forEach((shape, i) => {
      if (
        Math.abs(math.starts[i]! - PROBE_DAY) >
        DAYS_IN_YEAR * SAMPLE_MONTHS_WITHIN_YEARS
      )
        return;
      let start = math.starts[i]!;
      for (const [, length] of math.months[shape]!) {
        days.add(start + INTO_MONTH);
        start += length;
      }
    });
  }
  return [...days].sort((a, b) => a - b).slice(0, MOST_EDGE_DAYS);
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
    if (formatters.size > MOST_FORMATTERS) formatters.clear();
  }
  return f.format(seconds * MS_PER_SECOND);
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
      Math.floor((seconds + offset * SECONDS_PER_MINUTE) / SECONDS_PER_DAY),
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
  // Each date style alone, and the fullest and shortest dates with times.
  const [full, short] = [1, STYLES.length];
  const pairs: Pair[] = [
    ...STYLES.map((_, s): Pair => [s + 1, 0]),
    [full, full],
    [short, short],
  ];
  for (const tag of EDGE_LOCALES) {
    const calendar = locales.find(([t]) => t === tag)?.[1];
    if (!calendar) continue;
    for (const { id } of CALENDARS)
      for (const d of edgeDays(mathFor(id)))
        for (const pair of pairs)
          add(tag, id, id === calendar, pair, at(d, ...EDGE_TIME, 0));
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
  const next = random(FIELDS_SEED);
  const lines: string[] = [];
  CALENDARS.forEach(({ id }) => {
    const math = mathFor(id);
    const days = new Set(edgeDays(math));
    if (math.kind === "table") {
      const first = math.starts[0]!;
      const last = math.starts.at(-1)!;
      days
        .add(first - 1)
        .add(last)
        .add(last - 1);
      // The first day of a year, and the last, for some of the years.
      for (let i = 0; i < math.starts.length - 1; i += EVERY_NTH_YEAR)
        days.add(math.starts[i]!).add(math.starts[i + 1]! - 1);
      for (let n = 0; n < RANDOM_FIELD_DAYS; n++)
        days.add(first + Math.floor(next() * (last - first)));
    } else {
      for (const era of math.eras)
        if (Number.isFinite(era.start)) days.add(era.start - 1).add(era.start);
      for (let n = 0; n < RANDOM_FIELD_DAYS; n++)
        days.add(
          day(SCAN_FROM, 1, 1) +
            Math.floor(next() * (day(LAST_YEAR, 1, 1) - day(SCAN_FROM, 1, 1))),
        );
    }
    for (const d of [...days].sort((a, b) => a - b)) {
      const c = calendarDate(math, d);
      const fields = c
        ? [c.era, c.year, c.extended, c.related, c.cycle, c.month, c.day].join(
            ", ",
          )
        : "";
      lines.push(`    #("${id}", ${d}, [${fields}]),`);
    }
  });
  return `//// Calendar fields, from glintl's calendar maths after checking it against
//// \`Intl.DateTimeFormat\` on every day, in ${runtime}.
//// Generated by \`codegen/generate.ts\`. Do not edit.

/// ICU's name for the calendar, days since 1970-01-01, and the era,
/// year, extended year, related year, cycle year, month and day. Empty when
/// the calendar's table doesn't cover the day.
pub fn cases() -> List(#(String, Int, List(Int))) {
  [
${lines.join("\n")}
  ]
}
`;
}
