// Works out a locale's patterns from ICU with formatToParts: what each part
// of a formatted date is, and every name it can show.

import {
  type CalendarId,
  type Math_,
  type Table,
  DAY_MS,
  FIRST_DAY,
  INTO_MONTH,
  LAST_DAY,
  LAST_YEAR,
  LONGEST_LUNAR_MONTH,
  MID_YEAR,
  MONTHS_PER_YEAR,
  SCAN_FROM,
  calendarDate,
  civil,
  civilDay,
  day,
  isoWeekday,
} from "./calendars.ts";
import { random } from "./random.ts";
import { type Moment, join, render } from "./render.ts";
import {
  DAYS_PER_WEEK,
  HOURS_PER_DAY,
  HOURS_PER_HALF_DAY,
  MINUTES_PER_HOUR,
  MS_PER_SECOND,
  ONE_DIGIT_BELOW,
  SECONDS_PER_DAY,
  SECONDS_PER_MINUTE,
  TWO_DIGIT_YEARS,
  offsetString,
} from "./time.ts";

// Mirrors `src/glintl/internal/data.gleam`.
export type Token =
  | { t: "literal"; value: string }
  // A part written with ASCII digits, whatever the locale's digits are.
  | { t: "ascii"; token: Token }
  | { t: "extended_year"; minus: string }
  | {
      t: "year";
      twoDigit: boolean;
      minus: string;
      first: string;
      minusFirst: string;
    }
  | {
      t: "week_year";
      minus: string;
      firstDay: number;
      minimalDays: number;
      exceptions: [number, number][];
    }
  | { t: "related_year" }
  | { t: "year_name"; names: string[] }
  | { t: "month_number" | "day" | "minute" | "second"; pad: boolean }
  | { t: "month_name" | "day_name" | "weekday" | "era"; names: string[] }
  | { t: "hour"; pad: boolean; cycle: "h11" | "h12" | "h23" | "h24" }
  | { t: "day_period"; byHour: string[]; midnight: string; noon: string }
  | {
      t: "zone";
      zero: string;
      positive: string;
      positiveSuffix: string;
      positiveWholeSuffix: string;
      negative: string;
      negativeSuffix: string;
      negativeWholeSuffix: string;
      padHours: boolean;
      separator: string;
      optionalMinutes: boolean;
    };

// How a date and a time are joined, like "{date} at {time}".
export type GluePiece =
  { t: "text"; value: string } | { t: "date" } | { t: "time" };

export const STYLES = ["full", "long", "medium", "short"] as const;

export type Style = (typeof STYLES)[number];

type Local = (n: number, pad: boolean) => string;

// 2026-03-05, a Thursday, at 09:07:04: every number is different, and the
// hour, minute and second are under ten, to show their padding.
const PROBE_DAY = day(2026, 3, 5);
const PROBE_TIME: [number, number, number] = [9, 7, 4];

const at = (
  epochDay: number,
  hour = PROBE_TIME[0],
  minute = PROBE_TIME[1],
  second = PROBE_TIME[2],
) =>
  new Date(
    epochDay * DAY_MS +
      ((hour * MINUTES_PER_HOUR + minute) * SECONDS_PER_MINUTE + second) *
        MS_PER_SECOND,
  );

// A day of the month under ten, to see whether days are padded.
const PADDED_DAY = 5;

// A day this far into each year, to sample it.
const INTO_YEAR = 10;

// The middle of a month, to sample its name.
const MID_MONTH_DAY = 15;

// Week-based years are checked around the start of each year from here.
const WEEK_YEARS_FROM = -100;

// Days from the start of a year to look for its week-based year on: a week
// either side.
const WEEK_YEAR_SEARCH = Array.from(
  { length: 2 * DAYS_PER_WEEK + 1 },
  (_, n) => n - DAYS_PER_WEEK,
);

// Every rule for week-based years has some days in a week that count as the
// year's first.
const MINIMAL_DAYS = Array.from({ length: DAYS_PER_WEEK }, (_, n) => n + 1);

// Years where ICU starts a week-based year away from the rule are kept as
// exceptions, but more than one in this many means the rule is wrong.
const EXCEPTIONS_AT_MOST_ONE_IN = 10;

// Years 2 to 9 show whether a year is padded to two digits. Year 1 is left
// out, as some patterns write it as a word.
const SMALLEST_PADDED_YEAR = 2;

// Time zones to probe with. 11:47 has distinct digits and minutes, to find
// both in the text, and 1:47 shows whether hours are padded.
const ZONE_HOURS = 11;
const ZONE_MINUTES = 47;
const ZONE_SHORT_HOURS = 1;

const zoneOffset = (sign: "+" | "-", hours: number, minutes: number) =>
  offsetString((sign === "-" ? -1 : 1) * (hours * MINUTES_PER_HOUR + minutes));

const PROBE = at(PROBE_DAY);

export function localDigits(tag: string): string[] {
  const { numberingSystem } = new Intl.DateTimeFormat(tag).resolvedOptions();

  const nf = new Intl.NumberFormat(tag, {
    numberingSystem,
    useGrouping: false,
  });

  return Array.from({ length: ONE_DIGIT_BELOW }, (_, i) => nf.format(i));
}

export function defaultCalendar(tag: string): string {
  return new Intl.DateTimeFormat(tag).resolvedOptions().calendar;
}

type Options = {
  dateStyle?: Style;
  timeStyle?: Style;
  timeZone?: string;
};

function formatter(tag: string, calendar: CalendarId, options: Options) {
  return new Intl.DateTimeFormat(tag, {
    timeZone: "UTC",
    ...options,
    calendar,
  });
}

// Every day that a calendar's maths covers, to look for years with odd
// numbers: negative ones, or the first year of an era.
function sampleDays(math: Math_): number[] {
  if (math.kind === "table") {
    return math.starts.slice(0, -1).map((start) => start + INTO_YEAR);
  }

  return [
    ...Array.from({ length: LAST_YEAR - SCAN_FROM + 1 }, (_, n) =>
      day(SCAN_FROM + n, ...MID_YEAR),
    ),
    ...math.eras.flatMap((era) =>
      Number.isFinite(era.start) ? [era.start, era.start + 1] : [],
    ),
  ];
}

export function derive(
  tag: string,
  calendar: CalendarId,
  math: Math_,
  options: Options,
  digits: string[],
  probeDay = PROBE_DAY,
): Token[] {
  const name = `${tag} ${calendar} ${JSON.stringify(options)} on day ${probeDay}`;
  const f = formatter(tag, calendar, options);
  const probe = f.formatToParts(at(probeDay));

  // A part is found by its position, or if the date has other parts, as
  // the same occurrence of the same type.
  const valueAt = (date: Date, i: number) => {
    const parts = f.formatToParts(date);
    const type = probe[i]!.type;

    if (parts.length === probe.length && parts[i]!.type === type) {
      return parts[i]!.value;
    }

    const n = probe.slice(0, i).filter((p) => p.type === type).length;
    const found = parts.filter((p) => p.type === type)[n];

    if (!found) {
      throw new Error(`${name}: no ${type} on ${date.toISOString()}`);
    }

    return found.value;
  };

  const date = calendarDate(math, probeDay)!;
  const near = (days: number[]) => nearest(days, probeDay);
  const days = () => sampleDays(math);

  // Reads a part with the digits it's written in: the locale's, or ASCII for
  // parts that ICU writes in ASCII anyway.
  const reader = (active: string[]) => {
    const toAscii = (s: string) =>
      [...s]
        .map((c) => (active.includes(c) ? String(active.indexOf(c)) : c))
        .join("");

    const local: Local = (n, pad) =>
      [...(pad && n < ONE_DIGIT_BELOW ? `0${n}` : String(n))]
        .map((c) => active[+c])
        .join("");

    const numeric = (s: string) => /^\d+$/.test(toAscii(s));

    const padded = (value: string, n: number) => {
      if (value === local(n, true) && n < ONE_DIGIT_BELOW) {
        return true;
      }

      if (value === local(n, false)) {
        return false;
      }

      throw new Error(`${name}: can't read number ${value}`);
    };

    // How a negative year is written: the text before its digits.
    const minus = (
      i: number,
      year: (d: number) => number | undefined,
      twoDigit = false,
    ) => {
      const negatives = days().filter((d) => (year(d) ?? 0) < 0);

      const negative =
        negatives.find((d) => calendarDate(math, d)?.era === date.era) ??
        negatives[0];

      if (negative === undefined) {
        return "-";
      }

      const value = valueAt(at(negative), i);

      const digitsPart = twoDigit
        ? local(-year(negative)! % TWO_DIGIT_YEARS, true)
        : local(-year(negative)!, false);

      if (!value.endsWith(digitsPart)) {
        throw new Error(
          `${name}: odd negative year ${value} for ${year(negative)} on day ${negative}`,
        );
      }

      return value.slice(0, -digitsPart.length);
    };

    return (part: Intl.DateTimeFormatPart, i: number): Token => {
      const { type, value } = part;

      // TypeScript doesn't know every part type.
      const partType: string = type;

      switch (partType) {
        case "literal":
          return { t: "literal", value };
        case "year": {
          const year = (d: number) => calendarDate(math, d)?.year;

          // Some patterns write ICU's extended year, which runs on through
          // eras, and call it a year. It shows where the two differ.
          const differs = days().find((d) => {
            const c = calendarDate(math, d);

            return c !== undefined && Math.abs(c.year) !== Math.abs(c.extended);
          });

          if (differs !== undefined) {
            const c = calendarDate(math, differs)!;
            const shown = valueAt(at(differs), i);

            if (
              shown.endsWith(local(Math.abs(c.extended), false)) &&
              !shown.endsWith(local(Math.abs(c.year), false))
            ) {
              const extended = (d: number) => calendarDate(math, d)?.extended;

              return { t: "extended_year", minus: minus(i, extended) };
            }
          }

          const sameEra = (d: number) =>
            calendarDate(math, d)?.era === date.era;

          const abs = Math.abs(date.year);

          const isTwoDigit = (): boolean => {
            if (
              abs >= TWO_DIGIT_YEARS &&
              value.endsWith(local(abs % TWO_DIGIT_YEARS, true)) &&
              !value.endsWith(local(abs, false))
            ) {
              return true;
            }

            if (!value.endsWith(local(abs, false))) {
              throw new Error(`${name}: odd year ${value}`);
            }

            // Years under 100 look the same either way, unless one under 10 is
            // padded.
            const small = days().find((d) => {
              const y = Math.abs(year(d) ?? 0);

              return (
                sameEra(d) && y >= SMALLEST_PADDED_YEAR && y < ONE_DIGIT_BELOW
              );
            });

            return (
              abs < TWO_DIGIT_YEARS &&
              small !== undefined &&
              valueAt(at(small), i).endsWith(
                local(Math.abs(year(small)!), true),
              )
            );
          };

          const twoDigit = isTwoDigit();

          // Some patterns write the first year of an era as a word, like 元.
          const one = days().find((d) => year(d) === 1 && sameEra(d));

          const firstValue =
            one === undefined || twoDigit ? "" : valueAt(at(one), i);

          const first = firstValue === local(1, false) ? "" : firstValue;
          const yearMinus = minus(i, year, twoDigit);
          // ICU 78.3's Japanese writes year -1 as 元 too. Year -1 may only be in
          // another era, like the Japanese era before Taika.
          const minusOnes = days().filter((d) => year(d) === -1);
          const minusOne = minusOnes.find(sameEra) ?? minusOnes[0];

          const minusFirstValue =
            minusOne === undefined || twoDigit ? "" : valueAt(at(minusOne), i);

          const minusFirst =
            minusFirstValue === yearMinus + local(1, false)
              ? ""
              : minusFirstValue;

          return { t: "year", twoDigit, minus: yearMinus, first, minusFirst };
        }

        case "unknown": {
          // ICU's week-based year, which only Galician's patterns use.
          const firstDay = new Intl.Locale(tag).getWeekInfo().firstDay;

          const yearStarts =
            math.kind === "table"
              ? math.starts.slice(0, -1)
              : Array.from({ length: LAST_YEAR - WEEK_YEARS_FROM }, (_, n) =>
                  civilDay(WEEK_YEARS_FROM + n, 1, 1, math.julianBefore),
                );

          // Where ICU starts each week-based year: the first day near the start
          // of the year that shows it.
          const observed = yearStarts.flatMap(
            (start): [number, number, number][] => {
              const extended = calendarDate(math, start)!.extended;
              const text = number(extended, "-", local);

              const shown = WEEK_YEAR_SEARCH.map(
                (offset) => start + offset,
              ).find(
                (d) => calendarDate(math, d) && valueAt(at(d), i) === text,
              );

              return shown === undefined ? [] : [[start, extended, shown]];
            },
          );

          const ruleStart = (start: number, m: number) => {
            const weekday = isoWeekday(start);

            const weekStart =
              start - ((weekday - firstDay + DAYS_PER_WEEK) % DAYS_PER_WEEK);

            return DAYS_PER_WEEK - (start - weekStart) >= m
              ? weekStart
              : weekStart + DAYS_PER_WEEK;
          };

          const misses = (m: number) =>
            observed.filter(([start, , d]) => ruleStart(start, m) !== d);

          const minimalDays = MINIMAL_DAYS.reduce((best, m) =>
            misses(m).length < misses(best).length ? m : best,
          );

          const exceptions = misses(minimalDays).map(
            ([, extended, d]): [number, number] => [extended, d],
          );

          if (exceptions.length > observed.length / EXCEPTIONS_AT_MOST_ONE_IN) {
            throw new Error(`${name}: odd week-based year`);
          }

          const extended = (d: number) => calendarDate(math, d)?.extended;

          return {
            t: "week_year",
            minus: minus(i, extended),
            firstDay,
            minimalDays,
            exceptions,
          };
        }

        case "relatedYear":
          if (value !== local(date.related, false)) {
            throw new Error(`${name}: odd related year`);
          }

          return { t: "related_year" };
        case "yearName":
          if (math.kind !== "table") {
            throw new Error(`${name}: year names without a table`);
          }

          return {
            t: "year_name",
            names: occurrences(math).cycles.map((days) =>
              valueAt(at(near(days)), i),
            ),
          };
        case "month":
          if (math.kind === "proleptic") {
            // The probe's own year, which can be Julian.
            const year = civil(probeDay, math.julianBefore)[0];

            const names = Array.from({ length: MONTHS_PER_YEAR }, (_, m) =>
              valueAt(
                at(civilDay(year, m + 1, MID_MONTH_DAY, math.julianBefore)),
                i,
              ),
            );

            // Some locales write some months in other digits, so numbers are
            // only numbers if every month follows the same rule.
            if (numeric(value)) {
              const pad = padded(value, date.month + 1);

              if (names.every((name, m) => name === local(m + 1, pad))) {
                return { t: "month_number", pad };
              }
            }

            return { t: "month_name", names };
          }

          return {
            t: "month_name",
            names: occurrences(math).months.map((days) =>
              valueAt(at(near(days)), i),
            ),
          };
        case "day": {
          if (numeric(value)) {
            // Padding only shows on days 1 to 9.
            const early = probeDay - date.day + PADDED_DAY;

            return { t: "day", pad: padded(valueAt(at(early), i), PADDED_DAY) };
          }

          if (math.kind !== "table") {
            throw new Error(`${name}: day names without a table`);
          }

          const longMonth = near(occurrences(math).longMonths);
          // Names for days 0 to 30. Day 0 only happens where ICU's
          // astronomy goes wrong, so it's taken from one of those days.
          const zero = math.dayZero[0];

          return {
            t: "day_name",
            names: [
              zero ? valueAt(at(zero[0]), i) : "",
              ...Array.from({ length: LONGEST_LUNAR_MONTH }, (_, n) =>
                valueAt(at(longMonth + n), i),
              ),
            ],
          };
        }

        case "weekday": {
          // The Sunday before the probe, as weekday names start on Sunday.
          const sunday = probeDay - (isoWeekday(probeDay) % DAYS_PER_WEEK);

          return {
            t: "weekday",
            names: Array.from({ length: DAYS_PER_WEEK }, (_, d) =>
              valueAt(at(sunday + d), i),
            ),
          };
        }

        case "era":
          return {
            t: "era",
            names: math.eraDays.map((d) => valueAt(at(d), i)),
          };
        case "hour": {
          const hourAt = (h: number) => +toAscii(valueAt(at(probeDay, h), i));

          const cycle =
            hourAt(0) === HOURS_PER_HALF_DAY
              ? "h12"
              : hourAt(0) === HOURS_PER_DAY
                ? "h24"
                : hourAt(HOURS_PER_HALF_DAY) === 0
                  ? "h11"
                  : "h23";

          return { t: "hour", pad: padded(value, PROBE_TIME[0]), cycle };
        }

        case "minute":
          return { t: "minute", pad: padded(value, PROBE_TIME[1]) };
        case "second":
          return { t: "second", pad: padded(value, PROBE_TIME[2]) };
        case "dayPeriod":
          return {
            t: "day_period",
            byHour: Array.from({ length: HOURS_PER_DAY }, (_, h) =>
              valueAt(at(probeDay, h), i),
            ),
            midnight: valueAt(at(probeDay, 0, 0, 0), i),
            noon: valueAt(at(probeDay, HOURS_PER_HALF_DAY, 0, 0), i),
          };
        case "timeZoneName":
          return deriveZone(tag, calendar, options, i, local, probeDay);
        default:
          throw new Error(`${name}: unsupported part ${type}`);
      }
    };
  };

  const readLocal = reader(digits);
  const readAscii = reader(ASCII_DIGITS);

  return probe.map((part, i): Token => {
    try {
      return readLocal(part, i);
    } catch (error) {
      if (digits === ASCII_DIGITS) {
        throw error;
      }

      try {
        return { t: "ascii", token: readAscii(part, i) };
      } catch {
        throw error;
      }
    }
  });
}

function number(n: number, minus: string, local: Local): string {
  return n < 0 ? minus + local(-n, false) : local(n, false);
}

function deriveZone(
  tag: string,
  calendar: CalendarId,
  options: Options,
  i: number,
  local: Local,
  probeDay: number,
): Token {
  const name = `${tag} ${calendar} ${JSON.stringify(options)}`;

  const zone = (timeZone: string) =>
    formatter(tag, calendar, { ...options, timeZone }).formatToParts(
      at(probeDay),
    )[i]!.value;

  const zero = zone(zoneOffset("+", 0, 0));
  const full = zone(zoneOffset("+", ZONE_HOURS, ZONE_MINUTES));
  const hourDigits = local(ZONE_HOURS, false);
  const minuteDigits = local(ZONE_MINUTES, true);
  const hAt = full.indexOf(hourDigits);
  const mAt = full.indexOf(minuteDigits, hAt + hourDigits.length);

  if (hAt < 0 || mAt < 0) {
    throw new Error(`${name}: odd zone ${full}`);
  }

  const positive = full.slice(0, hAt);
  const separator = full.slice(hAt + hourDigits.length, mAt);
  const suffix = full.slice(mAt + minuteDigits.length);

  const negativeFull = zone(zoneOffset("-", ZONE_HOURS, ZONE_MINUTES));
  const negative = negativeFull.slice(0, negativeFull.indexOf(hourDigits));

  const negativeSuffix = negativeFull.slice(
    negative.length +
      hourDigits.length +
      separator.length +
      minuteDigits.length,
  );

  if (
    negativeFull !==
    negative + hourDigits + separator + minuteDigits + negativeSuffix
  ) {
    throw new Error(`${name}: odd negative zone ${negativeFull}`);
  }

  // With minutes left out, some locales also change the suffix.
  const whole = zone(zoneOffset("+", ZONE_HOURS, 0));
  const negativeWhole = zone(zoneOffset("-", ZONE_HOURS, 0));
  const optionalMinutes = !whole.includes(separator + local(0, true));

  const wholeSuffix = (text: string, prefix: string) => {
    const wholeMinutes = optionalMinutes ? "" : separator + local(0, true);

    if (!text.startsWith(prefix + hourDigits + wholeMinutes)) {
      throw new Error(`${name}: odd whole hour zone ${text}`);
    }

    return text.slice((prefix + hourDigits + wholeMinutes).length);
  };

  return {
    t: "zone",
    zero,
    positive,
    positiveSuffix: suffix,
    positiveWholeSuffix: wholeSuffix(whole, positive),
    negative,
    negativeSuffix,
    negativeWholeSuffix: wholeSuffix(negativeWhole, negative),
    padHours: zone(zoneOffset("+", ZONE_SHORT_HOURS, ZONE_MINUTES)).startsWith(
      positive + local(ZONE_SHORT_HOURS, true),
    ),
    separator,
    optionalMinutes,
  };
}

// How a date style joins a date and a time. ICU picks it by the date style
// alone, which `glue` checks.
export function glue(
  tag: string,
  calendar: CalendarId,
  dateStyle: Style,
): GluePiece[] {
  const name = `${tag} ${calendar} ${dateStyle}`;

  const format = (options: Options) =>
    formatter(tag, calendar, options).format(PROBE);

  const date = format({ dateStyle });

  const pieces = (timeStyle: Style): GluePiece[] => {
    const both = format({ dateStyle, timeStyle });
    const time = format({ timeStyle });
    const d = both.indexOf(date);
    const t = both.indexOf(time, d < 0 ? 0 : d + date.length);
    const t2 = t >= 0 ? t : both.indexOf(time);

    if (d < 0 || t2 < 0) {
      throw new Error(`${name}: can't find the date and time in ${both}`);
    }

    const found: { at: number; length: number; piece: GluePiece }[] = [
      { at: d, length: date.length, piece: { t: "date" } },
      { at: t2, length: time.length, piece: { t: "time" } },
    ];

    const marks = found.sort((a, b) => a.at - b.at);

    // Where the text before each mark starts, and the text after the last.
    const froms = [0, ...marks.map((mark) => mark.at + mark.length)];
    const last = froms.at(-1)!;

    const pieces = marks.flatMap((mark, n): GluePiece[] =>
      mark.at > froms[n]!
        ? [{ t: "text", value: both.slice(froms[n], mark.at) }, mark.piece]
        : [mark.piece],
    );

    return last < both.length
      ? [...pieces, { t: "text", value: both.slice(last) }]
      : pieces;
  };

  const short = pieces("short");

  if (JSON.stringify(pieces("full")) !== JSON.stringify(short)) {
    throw new Error(`${name}: the glue depends on the time style`);
  }

  return short;
}

// Where each month, cycle year and 30 day month falls in a table calendar,
// to sample names near a given day.
const occurrenceCache = new WeakMap<
  Table,
  ReturnType<typeof findOccurrences>
>();

function occurrences(math: Table) {
  const cached = occurrenceCache.get(math);

  if (cached) {
    return cached;
  }

  const found = findOccurrences(math);
  occurrenceCache.set(math, found);

  return found;
}

function findOccurrences(math: Table) {
  const months: number[][] = math.monthDays.map(() => []);

  const cycles: number[][] = Array.from(
    { length: math.cycleDays.length },
    () => [],
  );

  const longMonths: number[] = [];
  math.layouts.forEach((layout, i) => {
    const yearStart = math.starts[i]!;
    cycles[calendarDate(math, yearStart)!.cycle]?.push(yearStart + INTO_YEAR);

    math.months[layout]!.reduce((start, [month, length]) => {
      months[month]!.push(start + INTO_MONTH);

      if (length === LONGEST_LUNAR_MONTH) {
        longMonths.push(start);
      }

      return start + length;
    }, yearStart);
  });

  return { months, cycles, longMonths };
}

// The day in a sorted list closest to `target`.
function nearest(days: number[], target: number): number {
  const search = (low: number, high: number): number => {
    if (low >= high) {
      return low;
    }

    const middle = Math.floor((low + high) / 2);

    return days[middle]! < target
      ? search(middle + 1, high)
      : search(low, middle);
  };

  const low = search(0, days.length - 1);
  const after = days[low]!;
  const before = days[low - 1];

  return before !== undefined && target - before < after - target
    ? before
    : after;
}

// Everything a locale needs for one calendar. `eras` holds date patterns
// for eras that ICU formats differently from the rest.
export type EraFormats = {
  era: number;
  dates: Token[][];
  // Dates with times, by date style then time style, for eras where ICU
  // doesn't just join the date and time.
  combined?: Token[][];
};

export type Formats = {
  dates: Token[][];
  times: Token[][];
  glues: GluePiece[][];
  eras: EraFormats[];
};

const ASCII_DIGITS = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"];

// How many days to check a calendar's patterns on, besides the odd ones:
// some at random, the first years of a few eras, and a few negative years.
const RANDOM_CHECK_DAYS = 40;
const FIRST_YEAR_CHECK_DAYS = 12;
const NEGATIVE_YEAR_CHECK_DAYS = 3;

// Days after the start of an era to check it on, so a check isn't just the
// day it starts.
const DAYS_INTO_ERA = [40, 100, 400];

const RANDOM_SEED = 7;

// Every date style with every time style, in that order.
const STYLE_PAIRS = STYLES.flatMap((dateStyle, ds) =>
  STYLES.map((timeStyle, ts) => ({ ds, dateStyle, ts, timeStyle })),
);

// Time zone offsets, in minutes, to check times with: +11:47, -3:30 and +1.
const CHECK_OFFSETS = [707, -210, 60];

// An offset to check dates with times, +5:30.
const DATE_AND_TIME_OFFSET = 330;

// A year to check times before 1970 in, as ICU only names the zero offset
// from 1970.
const BEFORE_1970 = 1960;

// Days to check a calendar's patterns on: each era, each month near today,
// odd years, the edges of the table, and some at random.
const checkDayCache = new WeakMap<Math_, number[]>();

function checkDays(math: Math_): number[] {
  const cached = checkDayCache.get(math);

  if (cached) {
    return cached;
  }

  const days = new Set<number>([PROBE_DAY]);
  const next = random(RANDOM_SEED);

  const [from, to] =
    math.kind === "table"
      ? [math.starts[0]!, math.starts.at(-1)! - 1]
      : [day(SCAN_FROM, 1, 1), LAST_DAY];

  Array.from(
    { length: RANDOM_CHECK_DAYS },
    () => from + Math.floor(next() * (to - from)),
  ).forEach((d) => days.add(d));

  days.add(from).add(to);

  if (math.kind === "proleptic") {
    math.eras.forEach((era) => {
      if (Number.isFinite(era.start)) {
        days
          .add(era.start)
          .add(era.start - 1)
          .add(era.start + DAYS_INTO_ERA[0]!);
      }
    });

    days
      .add(day(SCAN_FROM, ...MID_YEAR))
      .add(day(-1, ...MID_YEAR))
      .add(FIRST_DAY);
  } else {
    math.eraDays.forEach((d) =>
      [0, ...DAYS_INTO_ERA.slice(1)].forEach((into) => days.add(d + into)),
    );

    occurrences(math).months.forEach((list) =>
      days.add(nearest(list, PROBE_DAY)),
    );

    occurrences(math).cycles.forEach((list) => {
      if (list.length) {
        days.add(nearest(list, PROBE_DAY));
      }
    });
  }

  // A few first years of eras, and negative years.
  const sampled = sampleDays(math).map((d) => ({
    d,
    year: calendarDate(math, d)?.year,
  }));

  const picked = new Set([
    ...sampled.filter(({ year }) => year === 1).slice(0, FIRST_YEAR_CHECK_DAYS),
    ...sampled
      .filter(({ year }) => year !== undefined && year < 0)
      .slice(0, NEGATIVE_YEAR_CHECK_DAYS),
  ]);

  sampled.forEach((sample) => {
    if (picked.has(sample)) {
      days.add(sample.d);
    }
  });

  const result = [...days].filter(
    (d) => d >= day(SCAN_FROM, 1, 1) && calendarDate(math, d) !== undefined,
  );

  checkDayCache.set(math, result);

  return result;
}

function moment(
  math: Math_,
  epochDay: number,
  offsetMinutes: number,
  hour = PROBE_TIME[0],
  minute = PROBE_TIME[1],
  second = PROBE_TIME[2],
): Moment {
  return {
    epochDay,
    date: calendarDate(math, epochDay)!,
    hour,
    minute,
    second,
    offsetMinutes,
    unixSeconds:
      epochDay * SECONDS_PER_DAY +
      (hour * MINUTES_PER_HOUR + minute) * SECONDS_PER_MINUTE +
      second -
      offsetMinutes * SECONDS_PER_MINUTE,
  };
}

function icu(
  tag: string,
  calendar: CalendarId,
  options: Options,
  m: Moment,
): string {
  return formatter(tag, calendar, {
    ...options,
    timeZone: offsetString(m.offsetMinutes),
  }).format(m.unixSeconds * MS_PER_SECOND);
}

export function formats(
  tag: string,
  calendar: CalendarId,
  math: Math_,
  digits: string[],
): Formats {
  const result: Formats = {
    dates: STYLES.map((dateStyle) =>
      derive(tag, calendar, math, { dateStyle }, digits),
    ),
    times: STYLES.map((timeStyle) =>
      derive(tag, calendar, math, { timeStyle }, digits),
    ),
    glues: STYLES.map((dateStyle) => glue(tag, calendar, dateStyle)),
    eras: [],
  };

  const days = checkDays(math);

  const main: EraFormats = { era: -1, dates: result.dates };

  const formatsFor = (era: number) =>
    result.eras.find((e) => e.era === era) ?? main;

  const failing = (f: EraFormats, d: number) =>
    STYLES.some((dateStyle, s) => {
      const m = moment(math, d, 0);

      return (
        render(f.dates[s]!, digits, m) !== icu(tag, calendar, { dateStyle }, m)
      );
    });

  const tryDerive = (era: number, d: number): EraFormats | undefined => {
    try {
      const dates = STYLES.map((dateStyle) =>
        derive(tag, calendar, math, { dateStyle }, digits, d),
      );

      const f = { era, dates };

      return failing(f, d) ? undefined : f;
    } catch {
      return undefined;
    }
  };

  // Eras that ICU formats differently get their own date patterns.
  days.forEach((d) => {
    const era = calendarDate(math, d)!.era;

    if (!failing(formatsFor(era), d)) {
      return;
    }

    if (result.eras.some((e) => e.era === era)) {
      const m = moment(math, d, 0);

      const s = STYLES.findIndex(
        (dateStyle) =>
          render(
            formatsFor(era).dates[STYLES.indexOf(dateStyle)]!,
            digits,
            m,
          ) !== icu(tag, calendar, { dateStyle }, m),
      );

      throw new Error(
        `${tag} ${calendar} ${STYLES[s]}: day ${d} doesn't match, even for its era: ${render(formatsFor(era).dates[s]!, digits, m)} | ${icu(tag, calendar, { dateStyle: STYLES[s]! }, m)}`,
      );
    }

    const f = tryDerive(era, d);

    if (!f) {
      const m = moment(math, d, 0);

      const dateStyle = STYLES.find(
        (ds, s) =>
          render(formatsFor(era).dates[s]!, digits, m) !==
          icu(tag, calendar, { dateStyle: ds }, m),
      )!;

      const s = STYLES.indexOf(dateStyle);
      throw new Error(
        `${tag} ${calendar} ${dateStyle}: day ${d} doesn't match: ${render(formatsFor(era).dates[s]!, digits, m)} | ${icu(tag, calendar, { dateStyle }, m)}`,
      );
    }

    result.eras.push(f);
  });

  // Recheck every day, now that all the eras are known.
  days.forEach((d) => {
    const f = formatsFor(calendarDate(math, d)!.era);
    STYLES.forEach((dateStyle, s) => {
      const m = moment(math, d, 0);
      const ours = render(f.dates[s]!, digits, m);
      const theirs = icu(tag, calendar, { dateStyle }, m);

      if (ours !== theirs) {
        throw new Error(
          `${tag} ${calendar} ${dateStyle}: day ${d} doesn't match: ${ours} | ${theirs}`,
        );
      }
    });
  });

  // Times, with offsets, at midnight and noon, and before 1970.
  const [lastHour, lastMinute, lastSecond] = [
    HOURS_PER_DAY - 1,
    MINUTES_PER_HOUR - 1,
    SECONDS_PER_MINUTE - 1,
  ];

  const timeMoments = [
    moment(math, PROBE_DAY, 0),
    ...CHECK_OFFSETS.map((offset) => moment(math, PROBE_DAY, offset)),
    moment(math, PROBE_DAY, CHECK_OFFSETS[2]!, 0, 0, 0),
    moment(math, PROBE_DAY, CHECK_OFFSETS[2]!, HOURS_PER_HALF_DAY, 0, 0),
    moment(math, PROBE_DAY, 0, lastHour, lastMinute, lastSecond),
  ];

  const before1970 = day(BEFORE_1970, ...MID_YEAR);

  if (calendarDate(math, before1970)) {
    timeMoments.push(moment(math, before1970, 0));
  }

  STYLES.forEach((timeStyle, s) => {
    timeMoments.forEach((m) => {
      if (
        render(result.times[s]!, digits, m) !==
        icu(tag, calendar, { timeStyle }, m)
      ) {
        throw new Error(`${tag} ${calendar} ${timeStyle}: time doesn't match`);
      }
    });
  });

  // Dates and times together, on a day in each era.
  const combinedFor = (f: EraFormats, ds: number, ts: number) =>
    f.combined?.[ds * STYLES.length + ts] ??
    join(f.dates[ds]!, result.glues[ds]!, result.times[ts]!);

  const combinedMismatch = (f: EraFormats, d: number) => {
    const m = moment(math, d, DATE_AND_TIME_OFFSET);

    // Lazily, to stop at the first mismatch.
    const mismatch = STYLE_PAIRS.values()
      .map(({ ds, dateStyle, ts, timeStyle }) => ({
        dateStyle,
        timeStyle,
        ours: render(combinedFor(f, ds, ts), digits, m),
        theirs: icu(tag, calendar, { dateStyle, timeStyle }, m),
      }))
      .find(({ ours, theirs }) => ours !== theirs);

    return mismatch === undefined
      ? undefined
      : `${mismatch.dateStyle} ${mismatch.timeStyle} on day ${d}: ${mismatch.ours} | ${mismatch.theirs}`;
  };

  const eraDays = new Map<number, number>();

  [PROBE_DAY, ...days].forEach((d) => {
    const era = calendarDate(math, d)!.era;

    if (!eraDays.has(era)) {
      eraDays.set(era, d);
    }
  });

  eraDays.forEach((d, era) => {
    const current = formatsFor(era);

    if (!combinedMismatch(current, d)) {
      return;
    }

    const eraFormats: EraFormats =
      current === main ? { era, dates: result.dates } : current;

    if (current === main) {
      result.eras.push(eraFormats);
    }

    eraFormats.combined = STYLES.flatMap((dateStyle) =>
      STYLES.map((timeStyle) =>
        derive(tag, calendar, math, { dateStyle, timeStyle }, digits, d),
      ),
    );
    const mismatch = combinedMismatch(eraFormats, d);

    if (mismatch) {
      throw new Error(
        `${tag} ${calendar}: date and time don't match, ${mismatch}`,
      );
    }
  });

  [PROBE_DAY, days[1]!].forEach((d) => {
    const mismatch = combinedMismatch(
      formatsFor(calendarDate(math, d)!.era),
      d,
    );

    if (mismatch) {
      throw new Error(
        `${tag} ${calendar}: date and time don't match, ${mismatch}`,
      );
    }
  });

  return result;
}
