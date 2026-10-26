// Works out a locale's patterns from ICU with formatToParts: what each part
// of a formatted date is, and every name it can show.

import {
  type CalendarId,
  type Math_,
  type Table,
  DAY_MS,
  FIRST_DAY,
  LAST_DAY,
  calendarDate,
  day,
} from "./calendars.ts";
import { type Moment, join, render } from "./render.ts";

// Mirrors `src/glintl/internal/data.gleam`.
export type Token =
  | { t: "literal"; value: string }
  // A part written with ASCII digits, whatever the locale's digits are.
  | { t: "ascii"; token: Token }
  | { t: "extended_year"; minus: string }
  | { t: "year"; twoDigit: boolean; minus: string; first: string }
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

// 2026-03-05, a Thursday, at 09:07:04: every number is different.
const PROBE_DAY = day(2026, 3, 5);
const at = (epochDay: number, hour = 9, minute = 7, second = 4) =>
  new Date(epochDay * DAY_MS + ((hour * 60 + minute) * 60 + second) * 1000);
const PROBE = at(PROBE_DAY);

export function localDigits(tag: string): string[] {
  const { numberingSystem } = new Intl.DateTimeFormat(tag).resolvedOptions();
  const nf = new Intl.NumberFormat(tag, {
    numberingSystem,
    useGrouping: false,
  });
  return Array.from({ length: 10 }, (_, i) => nf.format(i));
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
  if (math.kind === "table")
    return math.starts.slice(0, -1).map((start) => start + 10);
  const days: number[] = [];
  for (let year = -5000; year <= 4000; year++) days.push(day(year, 7, 1));
  for (const era of math.eras)
    if (Number.isFinite(era.start)) days.push(era.start, era.start + 1);
  return days;
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
    if (parts.length === probe.length && parts[i]!.type === type)
      return parts[i]!.value;
    const n = probe.slice(0, i).filter((p) => p.type === type).length;
    const found = parts.filter((p) => p.type === type)[n];
    if (!found) throw new Error(`${name}: no ${type} on ${date.toISOString()}`);
    return found.value;
  };
  // The digits of the part being read: the locale's, or ASCII for parts
  // that ICU writes in ASCII anyway.
  let active = digits;
  const toAscii = (s: string) =>
    [...s]
      .map((c) => (active.includes(c) ? String(active.indexOf(c)) : c))
      .join("");
  const local: Local = (n, pad) =>
    [...String(n).padStart(pad ? 2 : 1, "0")].map((c) => active[+c]).join("");
  const numeric = (s: string) => /^\d+$/.test(toAscii(s));
  const padded = (value: string, n: number) => {
    if (value === local(n, true) && n < 10) return true;
    if (value === local(n, false)) return false;
    throw new Error(`${name}: can't read number ${value}`);
  };
  const date = calendarDate(math, probeDay)!;
  const near = (days: number[]) => nearest(days, probeDay);
  const days = () => sampleDays(math);

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
    if (negative === undefined) return "-";
    const value = valueAt(at(negative), i);
    const digitsPart = twoDigit
      ? local(-year(negative)! % 100, true)
      : local(-year(negative)!, false);
    if (!value.endsWith(digitsPart))
      throw new Error(
        `${name}: odd negative year ${value} for ${year(negative)} on day ${negative}`,
      );
    return value.slice(0, -digitsPart.length);
  };

  const read = (part: Intl.DateTimeFormatPart, i: number): Token => {
    const { type, value } = part;
    // TypeScript doesn't know every part type.
    switch (type as string) {
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
        const sameEra = (d: number) => calendarDate(math, d)?.era === date.era;
        const abs = Math.abs(date.year);
        let twoDigit: boolean;
        if (
          abs >= 100 &&
          value.endsWith(local(abs % 100, true)) &&
          !value.endsWith(local(abs, false))
        )
          twoDigit = true;
        else if (value.endsWith(local(abs, false))) {
          // Years under 100 look the same either way, unless one under 10 is
          // padded. Year 1 is left out, as some patterns write it as a word.
          const small = days().find((d) => {
            const y = Math.abs(year(d) ?? 0);
            return sameEra(d) && y >= 2 && y < 10;
          });
          twoDigit =
            abs < 100 &&
            small !== undefined &&
            valueAt(at(small), i).endsWith(local(Math.abs(year(small)!), true));
        } else throw new Error(`${name}: odd year ${value}`);
        // Some patterns write the first year of an era as a word, like 元.
        const one = days().find((d) => year(d) === 1 && sameEra(d));
        const firstValue =
          one === undefined || twoDigit ? "" : valueAt(at(one), i);
        const first = firstValue === local(1, false) ? "" : firstValue;
        return { t: "year", twoDigit, minus: minus(i, year, twoDigit), first };
      }
      case "unknown": {
        // ICU's week-based year, which only Galician's patterns use.
        const firstDay = new Intl.Locale(tag).getWeekInfo().firstDay;
        const yearStarts =
          math.kind === "table"
            ? math.starts.slice(0, -1)
            : Array.from({ length: 4100 }, (_, n) => day(n - 100, 1, 1));
        // Where ICU starts each week-based year: the first day near the start
        // of the year that shows it.
        const observed = yearStarts.flatMap(
          (start): [number, number, number][] => {
            const extended = calendarDate(math, start)!.extended;
            const text = number(extended, "-", local);
            for (let d = start - 7; d <= start + 7; d++)
              if (calendarDate(math, d) && valueAt(at(d), i) === text)
                return [[start, extended, d]];
            return [];
          },
        );
        const ruleStart = (start: number, m: number) => {
          const weekday = ((((start + 3) % 7) + 7) % 7) + 1;
          const weekStart = start - ((weekday - firstDay + 7) % 7);
          return 7 - (start - weekStart) >= m ? weekStart : weekStart + 7;
        };
        const misses = (m: number) =>
          observed.filter(([start, , d]) => ruleStart(start, m) !== d);
        const minimalDays = [1, 2, 3, 4, 5, 6, 7].reduce((best, m) =>
          misses(m).length < misses(best).length ? m : best,
        );
        const exceptions = misses(minimalDays).map(
          ([, extended, d]): [number, number] => [extended, d],
        );
        if (exceptions.length > observed.length / 10)
          throw new Error(`${name}: odd week-based year`);
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
        if (value !== local(date.related, false))
          throw new Error(`${name}: odd related year`);
        return { t: "related_year" };
      case "yearName":
        if (math.kind !== "table")
          throw new Error(`${name}: year names without a table`);
        return {
          t: "year_name",
          names: occurrences(math).cycles.map((days) =>
            valueAt(at(near(days)), i),
          ),
        };
      case "month":
        if (math.kind === "proleptic") {
          const year = new Date(probeDay * DAY_MS).getUTCFullYear();
          const names = Array.from({ length: 12 }, (_, m) =>
            valueAt(at(day(year, m + 1, 5)), i),
          );
          // Some locales write some months in other digits, so numbers are
          // only numbers if every month follows the same rule.
          if (numeric(value)) {
            const pad = padded(value, date.month + 1);
            if (names.every((name, m) => name === local(m + 1, pad)))
              return { t: "month_number", pad };
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
          const early = probeDay - date.day + 5;
          return { t: "day", pad: padded(valueAt(at(early), i), 5) };
        }
        if (math.kind !== "table")
          throw new Error(`${name}: day names without a table`);
        const longMonth = near(occurrences(math).longMonths);
        // Names for days 0 to 30. Day 0 only happens where ICU's
        // astronomy goes wrong, so it's taken from one of those days.
        const zero = math.dayZero[0];
        return {
          t: "day_name",
          names: [
            zero ? valueAt(at(zero[0]), i) : "",
            ...Array.from({ length: 30 }, (_, n) =>
              valueAt(at(longMonth + n), i),
            ),
          ],
        };
      }
      case "weekday": {
        // The Sunday before the probe. 1970-01-01 was a Thursday.
        const sunday = probeDay - ((((probeDay + 4) % 7) + 7) % 7);
        return {
          t: "weekday",
          names: Array.from({ length: 7 }, (_, d) =>
            valueAt(at(sunday + d), i),
          ),
        };
      }
      case "era":
        return { t: "era", names: math.eraDays.map((d) => valueAt(at(d), i)) };
      case "hour": {
        const hourAt = (h: number) => +toAscii(valueAt(at(probeDay, h), i));
        const cycle =
          hourAt(0) === 12
            ? "h12"
            : hourAt(0) === 24
              ? "h24"
              : hourAt(12) === 0
                ? "h11"
                : "h23";
        return { t: "hour", pad: padded(value, 9), cycle };
      }
      case "minute":
        return { t: "minute", pad: padded(value, 7) };
      case "second":
        return { t: "second", pad: padded(value, 4) };
      case "dayPeriod":
        return {
          t: "day_period",
          byHour: Array.from({ length: 24 }, (_, h) =>
            valueAt(at(probeDay, h), i),
          ),
          midnight: valueAt(at(probeDay, 0, 0, 0), i),
          noon: valueAt(at(probeDay, 12, 0, 0), i),
        };
      case "timeZoneName":
        return deriveZone(tag, calendar, options, i, local, probeDay);
      default:
        throw new Error(`${name}: unsupported part ${type}`);
    }
  };

  return probe.map((part, i): Token => {
    active = digits;
    try {
      return read(part, i);
    } catch (error) {
      if (digits === ASCII_DIGITS) throw error;
      active = ASCII_DIGITS;
      try {
        return { t: "ascii", token: read(part, i) };
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
  const zero = zone("+00:00");
  const full = zone("+11:47");
  const h11 = local(11, false);
  const m47 = local(47, true);
  const hAt = full.indexOf(h11);
  const mAt = full.indexOf(m47, hAt + h11.length);
  if (hAt < 0 || mAt < 0) throw new Error(`${name}: odd zone ${full}`);
  const positive = full.slice(0, hAt);
  const separator = full.slice(hAt + h11.length, mAt);
  const suffix = full.slice(mAt + m47.length);

  const negativeFull = zone("-11:47");
  const negative = negativeFull.slice(0, negativeFull.indexOf(h11));
  const negativeSuffix = negativeFull.slice(
    negative.length + h11.length + separator.length + m47.length,
  );
  if (negativeFull !== negative + h11 + separator + m47 + negativeSuffix)
    throw new Error(`${name}: odd negative zone ${negativeFull}`);

  // With minutes left out, some locales also change the suffix.
  const whole = zone("+11:00");
  const negativeWhole = zone("-11:00");
  const optionalMinutes = !whole.includes(separator + local(0, true));
  const wholeSuffix = (text: string, prefix: string) => {
    const minutes = optionalMinutes ? "" : separator + local(0, true);
    if (!text.startsWith(prefix + h11 + minutes))
      throw new Error(`${name}: odd whole hour zone ${text}`);
    return text.slice((prefix + h11 + minutes).length);
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
    padHours: zone("+01:47").startsWith(positive + local(1, true)),
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
    if (d < 0 || t2 < 0)
      throw new Error(`${name}: can't find the date and time in ${both}`);
    const marks = [
      { at: d, length: date.length, piece: { t: "date" } as GluePiece },
      { at: t2, length: time.length, piece: { t: "time" } as GluePiece },
    ].sort((a, b) => a.at - b.at);
    const result: GluePiece[] = [];
    let from = 0;
    for (const mark of marks) {
      if (mark.at > from)
        result.push({ t: "text", value: both.slice(from, mark.at) });
      result.push(mark.piece);
      from = mark.at + mark.length;
    }
    if (from < both.length) result.push({ t: "text", value: both.slice(from) });
    return result;
  };
  const short = pieces("short");
  if (JSON.stringify(pieces("full")) !== JSON.stringify(short))
    throw new Error(`${name}: the glue depends on the time style`);
  return short;
}

// Where each month, cycle year and 30 day month falls in a table calendar,
// to sample names near a given day.
const occurrenceCache = new WeakMap<
  Table,
  ReturnType<typeof findOccurrences>
>();

function occurrences(math: Table) {
  let found = occurrenceCache.get(math);
  if (!found) {
    found = findOccurrences(math);
    occurrenceCache.set(math, found);
  }
  return found;
}

function findOccurrences(math: Table) {
  const months: number[][] = math.monthDays.map(() => []);
  const cycles: number[][] = Array.from(
    { length: math.cycleDays.length },
    () => [],
  );
  const longMonths: number[] = [];
  math.shapes.forEach((shape, i) => {
    let start = math.starts[i]!;
    cycles[calendarDate(math, start)!.cycle]?.push(start + 10);
    for (const [month, length] of math.months[shape]!) {
      months[month]!.push(start + 4);
      if (length === 30) longMonths.push(start);
      start += length;
    }
  });
  return { months, cycles, longMonths };
}

// The day in a sorted list closest to `target`.
function nearest(days: number[], target: number): number {
  let low = 0;
  let high = days.length - 1;
  while (low < high) {
    const middle = Math.floor((low + high) / 2);
    if (days[middle]! < target) low = middle + 1;
    else high = middle;
  }
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

// Seeded, so the generated files only change when ICU does.
function random(seed: number): () => number {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Days to check a calendar's patterns on: each era, each month near today,
// odd years, the edges of the table, and some at random.
const checkDayCache = new WeakMap<Math_, number[]>();

function checkDays(math: Math_): number[] {
  const cached = checkDayCache.get(math);
  if (cached) return cached;
  const days = new Set<number>([PROBE_DAY]);
  const next = random(7);
  const [from, to] =
    math.kind === "table"
      ? [math.starts[0]!, math.starts.at(-1)! - 1]
      : [day(-5000, 1, 1), LAST_DAY];
  for (let n = 0; n < 40; n++)
    days.add(from + Math.floor(next() * (to - from)));
  days.add(from).add(to);
  if (math.kind === "proleptic") {
    for (const era of math.eras)
      if (Number.isFinite(era.start))
        days
          .add(era.start)
          .add(era.start - 1)
          .add(era.start + 40);
    days
      .add(day(-5000, 6, 1))
      .add(day(-1, 6, 1))
      .add(FIRST_DAY);
  } else {
    for (const d of math.eraDays)
      days
        .add(d)
        .add(d + 100)
        .add(d + 400);
    for (const list of occurrences(math).months)
      days.add(nearest(list, PROBE_DAY));
    for (const list of occurrences(math).cycles)
      if (list.length) days.add(nearest(list, PROBE_DAY));
  }
  // A few first years of eras, and negative years.
  let firsts = 0;
  let negatives = 0;
  for (const d of sampleDays(math)) {
    const year = calendarDate(math, d)?.year;
    if (year === 1 && firsts++ < 12) days.add(d);
    if (year !== undefined && year < 0 && negatives++ < 3) days.add(d);
  }
  const result = [...days].filter(
    (d) => d >= day(-5000, 1, 1) && calendarDate(math, d) !== undefined,
  );
  checkDayCache.set(math, result);
  return result;
}

function moment(
  math: Math_,
  epochDay: number,
  offsetMinutes: number,
  hour = 9,
  minute = 7,
  second = 4,
): Moment {
  return {
    epochDay,
    date: calendarDate(math, epochDay)!,
    hour,
    minute,
    second,
    offsetMinutes,
    unixSeconds:
      epochDay * 86400 +
      (hour * 60 + minute) * 60 +
      second -
      offsetMinutes * 60,
  };
}

function offsetString(minutes: number): string {
  const sign = minutes < 0 ? "-" : "+";
  const abs = Math.abs(minutes);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${sign}${pad(Math.floor(abs / 60))}:${pad(abs % 60)}`;
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
  }).format(m.unixSeconds * 1000);
}

export function formats(
  tag: string,
  calendar: CalendarId,
  math: Math_,
  digits: string[],
): Formats {
  const result: Formats = { dates: [], times: [], glues: [], eras: [] };
  const days = checkDays(math);
  for (const dateStyle of STYLES) {
    result.dates.push(derive(tag, calendar, math, { dateStyle }, digits));
    result.glues.push(glue(tag, calendar, dateStyle));
  }
  for (const timeStyle of STYLES)
    result.times.push(derive(tag, calendar, math, { timeStyle }, digits));

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
  for (const d of days) {
    const era = calendarDate(math, d)!.era;
    if (!failing(formatsFor(era), d)) continue;
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
  }
  // Recheck every day, now that all the eras are known.
  for (const d of days) {
    const f = formatsFor(calendarDate(math, d)!.era);
    STYLES.forEach((dateStyle, s) => {
      const m = moment(math, d, 0);
      const ours = render(f.dates[s]!, digits, m);
      const theirs = icu(tag, calendar, { dateStyle }, m);
      if (ours !== theirs)
        throw new Error(
          `${tag} ${calendar} ${dateStyle}: day ${d} doesn't match: ${ours} | ${theirs}`,
        );
    });
  }

  // Times, with offsets, at midnight and noon, and before 1970.
  const timeMoments = [
    moment(math, PROBE_DAY, 0),
    moment(math, PROBE_DAY, 707),
    moment(math, PROBE_DAY, -210),
    moment(math, PROBE_DAY, 60, 0, 0, 0),
    moment(math, PROBE_DAY, 60, 12, 0, 0),
    moment(math, PROBE_DAY, 0, 23, 59, 59),
  ];
  const before1970 = day(1960, 6, 1);
  if (calendarDate(math, before1970))
    timeMoments.push(moment(math, before1970, 0));
  STYLES.forEach((timeStyle, s) => {
    for (const m of timeMoments)
      if (
        render(result.times[s]!, digits, m) !==
        icu(tag, calendar, { timeStyle }, m)
      )
        throw new Error(`${tag} ${calendar} ${timeStyle}: time doesn't match`);
  });
  // Dates and times together, on a day in each era.
  const combinedFor = (f: EraFormats, ds: number, ts: number) =>
    f.combined?.[ds * STYLES.length + ts] ??
    join(f.dates[ds]!, result.glues[ds]!, result.times[ts]!);
  const combinedMismatch = (f: EraFormats, d: number) => {
    const m = moment(math, d, 330);
    for (const [ds, dateStyle] of STYLES.entries())
      for (const [ts, timeStyle] of STYLES.entries()) {
        const ours = render(combinedFor(f, ds, ts), digits, m);
        const theirs = icu(tag, calendar, { dateStyle, timeStyle }, m);
        if (ours !== theirs)
          return `${dateStyle} ${timeStyle} on day ${d}: ${ours} | ${theirs}`;
      }
    return undefined;
  };
  const eraDays = new Map<number, number>();
  for (const d of [PROBE_DAY, ...days]) {
    const era = calendarDate(math, d)!.era;
    if (!eraDays.has(era)) eraDays.set(era, d);
  }
  for (const [era, d] of eraDays) {
    let f = formatsFor(era);
    if (!combinedMismatch(f, d)) continue;
    if (f === main) {
      f = { era, dates: result.dates };
      result.eras.push(f);
    }
    const eraFormats = f;
    eraFormats.combined = STYLES.flatMap((dateStyle) =>
      STYLES.map((timeStyle) =>
        derive(tag, calendar, math, { dateStyle, timeStyle }, digits, d),
      ),
    );
    const mismatch = combinedMismatch(eraFormats, d);
    if (mismatch)
      throw new Error(
        `${tag} ${calendar}: date and time don't match, ${mismatch}`,
      );
  }
  for (const d of [PROBE_DAY, days[1]!]) {
    const mismatch = combinedMismatch(
      formatsFor(calendarDate(math, d)!.era),
      d,
    );
    if (mismatch)
      throw new Error(
        `${tag} ${calendar}: date and time don't match, ${mismatch}`,
      );
  }
  return result;
}
