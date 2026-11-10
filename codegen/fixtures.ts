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

// A date style and a time style. Each is 0 for none, or 1 to 4 for full to
// short.
type Pair = [number, number];

// The numbers from `from` up to but not including `to`.
const range = (from: number, to: number) =>
  Array.from({ length: Math.max(to - from, 0) }, (_, i) => from + i);

const STYLE_OR_NONE = range(0, STYLES.length + 1);

const PAIRS: Pair[] = STYLE_OR_NONE.flatMap((d) =>
  STYLE_OR_NONE.flatMap((t): Pair[] => (d || t ? [[d, t]] : [])),
);

// Locales with something odd in at least one calendar.
const EDGE_LOCALES = ["en-GB", "ja", "zh", "ko", "ar-SA", "fa", "gl", "ak"];

// These offsets in minutes cover half and quarter hours and both ends of the
// world: +1, -8, +5:30, +5:45, -3:30, +14, -10 and +8:45.
const OFFSETS = [0, 60, -480, 330, 345, -210, 840, -600, 525];

const MOMENT_SEED = 42;
const FIELDS_SEED = 7;

// Add this many random moments to the fixed ones, drawn from this many
// years.
const RANDOM_MOMENTS = 8;
const RANDOM_MOMENT_YEARS = 2400;
const DAYS_IN_LONGEST_YEAR = 366;

// Sample every month in table calendars within this many years of the probe
// day.
const SAMPLE_MONTHS_WITHIN_YEARS = 40;
const DAYS_IN_YEAR = 365;

// Check this many days into each month, which even the shortest month has.
const INTO_MONTH = 3;

// Check at most this many edge days per calendar, and at most this many era
// starts in calendars with Gregorian months.
const MOST_EDGE_DAYS = 60;
const MOST_ERA_STARTS = 4;

// Check calendar fields on this many random days. In table calendars, also
// check the first and last day of one year in this many.
const RANDOM_FIELD_DAYS = 300;
const EVERY_NTH_YEAR = 40;

// Intl formatters are slow to make, so we keep up to this many.
const MOST_FORMATTERS = 5000;

const PROBE_DAY = day(2026, 3, 5);

// Check edge days at this time of day, whose hour, minute and second all
// differ.
const EDGE_TIME: [number, number, number] = [9, 7, 4];

// A moment is its Unix seconds and its offset in minutes.
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

// Check every locale on midnight, noon, half past noon, the last second of a
// year, a year with one digit, a year BC and the turn of a millennium, then
// on some random moments.
function moments(): Moment[] {
  const next = random(MOMENT_SEED);

  const [plusOne, minusEight, plusFiveThirty] = [
    OFFSETS[1]!,
    OFFSETS[2]!,
    OFFSETS[3]!,
  ];

  return [
    at(PROBE_DAY, 0, 0, 0, 0),
    at(PROBE_DAY, HOURS_PER_HALF_DAY, 0, 0, 0),
    at(PROBE_DAY, HOURS_PER_HALF_DAY, MINUTES_PER_HOUR / 2, 0, 0),
    at(day(2026, MONTHS_PER_YEAR, 31), 23, 59, 59, plusOne),
    at(day(5, ...MID_YEAR), 8, 0, 0, minusEight),
    at(day(-100, 3, 5), 15, 0, 0, plusFiveThirty),
    at(day(1999, MONTHS_PER_YEAR, 31), 23, 0, 0, plusOne),
    ...range(0, RANDOM_MOMENTS).map(() => {
      const d =
        day(1 + Math.floor(next() * RANDOM_MOMENT_YEARS), 1, 1) +
        Math.floor(next() * DAYS_IN_LONGEST_YEAR);

      return at(d, 0, 0, 0, OFFSETS[Math.floor(next() * OFFSETS.length)]!);
    }),
  ];
}

// ICU's calendars switch from Julian dates on this day, so check it and the
// day before.
const GREGORIAN_REFORM = day(1582, 10, 15);

// Picks the days worth checking in a calendar: era changes, leap months, the
// edges of its table and odd years.
function edgeDays(math: Math_): number[] {
  const days = new Set<number>([PROBE_DAY]);

  if (math.kind === "proleptic") {
    const starts = math.eras.map((e) => e.start).filter(Number.isFinite);

    starts.slice(0, MOST_ERA_STARTS).forEach((start) => {
      days.add(start - 1).add(start);
    });

    days
      .add(day(-1000, ...MID_YEAR))
      .add(day(1, 1, 1))
      .add(GREGORIAN_REFORM)
      .add(GREGORIAN_REFORM - 1);
    // Some locales write years -1, 0 and 1 of the oldest era in odd ways.
    const oldest = math.eras.at(-1)!.era;

    range(SCAN_FROM, LAST_YEAR + 1).forEach((year) => {
      const d = day(year, ...MID_YEAR);
      const date = calendarDate(math, d)!;

      if (date.era === oldest && Math.abs(date.year) <= 1) {
        days.add(d);
      }
    });
  } else {
    const first = math.starts[0]!;
    const last = math.starts.at(-1)! - 1;
    days.add(first).add(last);

    math.eraDays.forEach((d) => days.add(d));

    // Check every month name in the years around the probe day.
    math.layouts.forEach((layout, i) => {
      if (
        Math.abs(math.starts[i]! - PROBE_DAY) >
        DAYS_IN_YEAR * SAMPLE_MONTHS_WITHIN_YEARS
      ) {
        return;
      }

      math.months[layout]!.reduce((start, [, length]) => {
        days.add(start + INTO_MONTH);

        return start + length;
      }, math.starts[i]!);
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
  const kept = formatters.get(key);

  const f =
    kept ??
    new Intl.DateTimeFormat(tag, {
      calendar,
      timeZone: offsetString(offset),
      dateStyle: d ? STYLES[d - 1] : undefined,
      timeStyle: t ? STYLES[t - 1] : undefined,
    });

  if (!kept) {
    formatters.set(key, f);

    if (formatters.size > MOST_FORMATTERS) {
      formatters.clear();
    }
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

  const mathByName = new Map<string, Math_>(
    CALENDARS.map(({ id }) => [id, mathFor(id)]),
  );

  // Table calendars only cover years 1 to 4000 on Erlang.
  const covered = (calendar: string, [seconds, offset]: Moment) =>
    calendarDate(
      mathByName.get(calendar)!,
      Math.floor((seconds + offset * SECONDS_PER_MINUTE) / SECONDS_PER_DAY),
    ) !== undefined;

  // Writes the case's line, or nothing if its calendar doesn't cover the moment.
  const line = (
    tag: string,
    calendar: string,
    isDefault: boolean,
    pair: Pair,
    moment: Moment,
  ): string[] =>
    covered(calendar, moment)
      ? [
          `    #("${tag}", "${isDefault ? "" : calendar}", ${pair[0]}, ${pair[1]}, ${moment[0]}, ${moment[1]}, ${gleamString(
            expected(tag, calendar, pair, moment),
          )}),`,
        ]
      : [];

  // Check every locale with every style pair in its own calendar.
  const own = locales.flatMap(([tag, calendar]) =>
    PAIRS.map((pair): [string, string, Pair] => [tag, calendar, pair]),
  );

  const ownLines = own.flatMap(([tag, calendar, pair], turn) =>
    line(tag, calendar, true, pair, all[turn % all.length]!),
  );

  // Check every locale in every other calendar, taking turns through the styles
  // and moments.
  const others = locales.flatMap(([tag, calendar]) =>
    CALENDARS.flatMap(({ id }): [string, string][] =>
      id === calendar ? [] : [[tag, id]],
    ),
  );

  const otherLines = others.flatMap(([tag, id], i) => {
    const turn = own.length + i;

    return line(
      tag,
      id,
      false,
      PAIRS[turn % PAIRS.length]!,
      all[turn % all.length]!,
    );
  });

  // Check each calendar's odd days in the locales with odd formats. Use each
  // date style alone, then the fullest and shortest dates with times.
  const [full, short] = [1, STYLES.length];

  const pairs: Pair[] = [
    ...STYLES.map((_, s): Pair => [s + 1, 0]),
    [full, full],
    [short, short],
  ];

  const edgeLines = EDGE_LOCALES.flatMap((tag) => {
    const calendar = locales.find(([t]) => t === tag)?.[1];

    if (!calendar) {
      return [];
    }

    return CALENDARS.flatMap(({ id }) =>
      edgeDays(mathFor(id)).flatMap((d) =>
        pairs.flatMap((pair) =>
          line(tag, id, id === calendar, pair, at(d, ...EDGE_TIME, 0)),
        ),
      ),
    );
  });

  const lines = [...ownLines, ...otherLines, ...edgeLines];

  return `//// Expected output, made with \`Intl.DateTimeFormat\` in ${runtime}.
//// Generated by \`codegen/generate.ts\`. Do not edit.

/// Each case is a locale tag, a calendar (empty for the locale's own), a date
/// style, a time style, Unix seconds, an offset in minutes and the output.
/// Styles are 0 for none, then 1 to 4 for full, long, medium and short.
pub fn cases() -> List(#(String, String, Int, Int, Int, Int, String)) {
  [
${lines.join("\n")}
  ]
}
`;
}

// Writes raw calendar fields for days in every calendar. They test the Erlang
// calendar maths directly, without going through formatted text.
export function calendarFixtures(
  mathFor: (id: CalendarId) => Math_,
  runtime: string,
): string {
  const next = random(FIELDS_SEED);

  const lines = CALENDARS.flatMap(({ id }) => {
    const math = mathFor(id);
    const days = new Set(edgeDays(math));

    if (math.kind === "table") {
      const first = math.starts[0]!;
      const last = math.starts.at(-1)!;
      days
        .add(first - 1)
        .add(last)
        .add(last - 1);

      // Check the first and last day of some of the years.
      range(0, math.starts.length - 1)
        .filter((i) => i % EVERY_NTH_YEAR === 0)
        .forEach((i) => {
          days.add(math.starts[i]!).add(math.starts[i + 1]! - 1);
        });

      range(0, RANDOM_FIELD_DAYS).forEach(() => {
        days.add(first + Math.floor(next() * (last - first)));
      });
    } else {
      math.eras
        .filter((era) => Number.isFinite(era.start))
        .forEach((era) => {
          days.add(era.start - 1).add(era.start);
        });

      range(0, RANDOM_FIELD_DAYS).forEach(() => {
        days.add(
          day(SCAN_FROM, 1, 1) +
            Math.floor(next() * (day(LAST_YEAR, 1, 1) - day(SCAN_FROM, 1, 1))),
        );
      });
    }

    return [...days]
      .sort((a, b) => a - b)
      .map((d) => {
        const c = calendarDate(math, d);

        const fields = c
          ? [
              c.era,
              c.year,
              c.extended,
              c.related,
              c.cycle,
              c.month,
              c.day,
            ].join(", ")
          : "";

        return `    #("${id}", ${d}, [${fields}]),`;
      });
  });

  return `//// Calendar fields from glintl's calendar maths, which was checked against
//// \`Intl.DateTimeFormat\` on every day in ${runtime}.
//// Generated by \`codegen/generate.ts\`. Do not edit.

/// Each case is ICU's name for the calendar, the days since 1970-01-01, then
/// the era, year, extended year, related year, cycle year, month and day. The
/// list is empty when the calendar's table doesn't cover the day.
pub fn cases() -> List(#(String, Int, List(Int))) {
  [
${lines.join("\n")}
  ]
}
`;
}

// --- Fields --------------------------------------------------------------------

// Intl's options for fields. glintl only shows time zones as offsets, where
// the generic names are the same as the others.
export const FIELD_CHOICES = [
  ["weekday", ["narrow", "short", "long"]],
  ["era", ["narrow", "short", "long"]],
  ["year", ["numeric", "2-digit"]],
  ["month", ["numeric", "2-digit", "narrow", "short", "long"]],
  ["day", ["numeric", "2-digit"]],
  ["dayPeriod", ["narrow", "short", "long"]],
  ["hour", ["numeric", "2-digit"]],
  ["minute", ["numeric", "2-digit"]],
  ["second", ["numeric", "2-digit"]],
  ["fractionalSecondDigits", [1, 2, 3]],
  ["timeZoneName", ["short", "long", "shortOffset", "longOffset"]],
] as const;

// How often each field is shown in a random request.
const FIELD_SHARE = 0.4;

// An era or a time zone isn't enough on its own.
const NOT_ENOUGH = ["era", "timeZoneName"];

export type Field = [string, string | number];

// Some random fields, with at least one that's enough on its own.
export function randomFields(next: () => number): Field[] {
  const picked = FIELD_CHOICES.flatMap(([name, values]): Field[] =>
    next() < FIELD_SHARE
      ? [[name, values[Math.floor(next() * values.length)]!]]
      : [],
  );

  return picked.some(([name]) => !NOT_ENOUGH.includes(name))
    ? picked
    : [...picked, ["day", "numeric"]];
}

export const fieldsText = (fields: Field[]) =>
  fields.map(([name, value]) => `${name}=${value}`).join(",");

const HOUR_CYCLES = [undefined, "h11", "h12", "h23", "h24"] as const;

// Requests per locale in its own calendar.
const OWN_REQUESTS = 4;

export function fieldFixtures(
  locales: [string, string][],
  mathFor: (id: CalendarId) => Math_,
  runtime: string,
): string {
  const next = random(FIELDS_SEED);
  const all = moments();

  type Case = [string, string, boolean, Moment];

  const own = locales.flatMap(([tag, calendar]) =>
    range(0, OWN_REQUESTS).map((): [string, string, boolean] => [
      tag,
      calendar,
      true,
    ]),
  );

  const others = locales.flatMap(([tag, calendar]) =>
    CALENDARS.flatMap(({ id }): [string, string, boolean][] =>
      id === calendar ? [] : [[tag, id, false]],
    ),
  );

  const turns: Case[] = [...own, ...others].map(
    ([tag, id, isDefault], turn) => [
      tag,
      id,
      isDefault,
      all[turn % all.length]!,
    ],
  );

  const edges: Case[] = EDGE_LOCALES.flatMap((tag) => {
    const calendar = locales.find(([t]) => t === tag)?.[1];

    return calendar === undefined
      ? []
      : CALENDARS.flatMap(({ id }) =>
          edgeDays(mathFor(id)).map((d): Case => [
            tag,
            id,
            id === calendar,
            at(d, ...EDGE_TIME, 0),
          ]),
        );
  });

  const lines = [...turns, ...edges].flatMap(
    ([tag, calendar, isDefault, [seconds, offset]]) => {
      const local = Math.floor(
        (seconds + offset * SECONDS_PER_MINUTE) / SECONDS_PER_DAY,
      );

      // Draw the same numbers whether the case is kept or not.
      const fields = randomFields(next);
      const hourCycle = HOUR_CYCLES[Math.floor(next() * HOUR_CYCLES.length)];
      const milliseconds = Math.floor(next() * MS_PER_SECOND);

      const math = CALENDARS.find(({ id }) => id === calendar);

      if (
        math === undefined ||
        calendarDate(mathFor(math.id), local) === undefined
      ) {
        return [];
      }

      const expected = new Intl.DateTimeFormat(tag, {
        ...Object.fromEntries(fields),
        calendar,
        timeZone: offsetString(offset),
        hourCycle,
      }).format(seconds * MS_PER_SECOND + milliseconds);

      return [
        `    #("${tag}", "${isDefault ? "" : calendar}", "${hourCycle ?? ""}", "${fieldsText(fields)}", ${seconds}, ${milliseconds}, ${offset}, ${gleamString(expected)}),`,
      ];
    },
  );

  return `//// Expected output for fields, made with \`Intl.DateTimeFormat\` in ${runtime}.
//// Generated by \`codegen/generate.ts\`. Do not edit.

/// Each case is a locale tag, a calendar (empty for the locale's own), an
/// hour cycle (empty for the locale's own), fields as Intl options like
/// \`day=numeric,month=short\`, Unix seconds, milliseconds, an offset in
/// minutes and the output.
pub fn cases() -> List(#(String, String, String, String, Int, Int, Int, String)) {
  [
${lines.join("\n")}
  ]
}
`;
}
