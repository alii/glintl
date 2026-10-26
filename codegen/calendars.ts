// Works out how each calendar maps days to its own eras, years, months and
// days, by asking ICU about every month from 0001 to 4000.

import { DAYS_PER_WEEK, MS_PER_SECOND, SECONDS_PER_DAY } from "./time.ts";

export const DAY_MS = SECONDS_PER_DAY * MS_PER_SECOND;

// Noon, to read a day without being near either end of it.
export const NOON_MS = DAY_MS / 2;

export const MONTHS_PER_YEAR = 12;

// The Chinese and Dangi calendars name years in a cycle of this many.
export const YEARS_IN_CYCLE = 60;

// The longest month in the lunar calendars, so day names cover days 1 to
// this.
export const LONGEST_LUNAR_MONTH = 30;

// Table calendars cover whole years between these, and eras are looked for
// from `SCAN_FROM`, assumed not to change before it.
export const FIRST_YEAR = 1;
export const LAST_YEAR = 4000;
export const SCAN_FROM = -5000;

// Era rules are also checked this far outside the years scanned.
const CHECK_FROM_YEAR = -9000;
const CHECK_TO_YEAR = 9999;

// The era rules are checked on every this many days: a prime, so the days
// drift through months and weekdays.
const CHECK_EVERY = 997;

// 1 July, far from both ends of a year.
export const MID_YEAR: [number, number] = [7, 1];

// Every month is at least this long, apart from the five or six extra days
// at the end of the Coptic and Ethiopic years.
const SHORTEST_MONTH = 29;

// A few days into a month, to sample its name, still inside the shortest
// months.
export const INTO_MONTH = 4;

// Around the middle of a month, to check a second day in each.
const MID_MONTH = 14;

// ICU switches from the Julian calendar somewhere between these dates.
const JULIAN_SEARCH: [[number, number, number], [number, number, number]] = [
  [1000, 6, 15],
  [1800, 1, 1],
];

// The Julian day number of 1970-01-01, and Richards' algorithm's offset
// from it, in the Explanatory Supplement to the Astronomical Almanac. The
// algorithm's other numbers are part of it as published.
const JULIAN_DAY_OF_UNIX_EPOCH = 2_440_588;

export type CalendarId =
  | "gregory"
  | "iso8601"
  | "buddhist"
  | "japanese"
  | "roc"
  | "persian"
  | "indian"
  | "hebrew"
  | "chinese"
  | "dangi"
  | "coptic"
  | "ethiopic"
  | "ethioaa"
  | "islamic-civil"
  | "islamic-tbla"
  | "islamic-umalqura";

// In the order of the Gleam `Calendar` type. Calendars with Gregorian months
// only differ in their eras and years, so they are worked out with a few
// rules and have no date limits. The rest use a table of years.
export const CALENDARS: {
  id: CalendarId;
  gleam: string;
  kind: "proleptic" | "table";
}[] = [
  { id: "gregory", gleam: "Gregorian", kind: "proleptic" },
  { id: "iso8601", gleam: "Iso8601", kind: "proleptic" },
  { id: "buddhist", gleam: "Buddhist", kind: "proleptic" },
  { id: "japanese", gleam: "Japanese", kind: "proleptic" },
  { id: "roc", gleam: "RepublicOfChina", kind: "proleptic" },
  { id: "persian", gleam: "Persian", kind: "table" },
  { id: "indian", gleam: "Indian", kind: "table" },
  { id: "hebrew", gleam: "Hebrew", kind: "table" },
  { id: "chinese", gleam: "Chinese", kind: "table" },
  { id: "dangi", gleam: "Dangi", kind: "table" },
  { id: "coptic", gleam: "Coptic", kind: "table" },
  { id: "ethiopic", gleam: "Ethiopic", kind: "table" },
  { id: "ethioaa", gleam: "EthiopicAmeteAlem", kind: "table" },
  { id: "islamic-civil", gleam: "IslamicCivil", kind: "table" },
  { id: "islamic-tbla", gleam: "IslamicTabular", kind: "table" },
  { id: "islamic-umalqura", gleam: "IslamicUmmAlQura", kind: "table" },
];

export function day(year: number, month: number, dayOfMonth: number): number {
  const date = new Date(0);
  date.setUTCFullYear(year, month - 1, dayOfMonth);
  return Math.floor(date.getTime() / DAY_MS);
}

export function astronomicalYear(epochDay: number): number {
  return new Date(epochDay * DAY_MS).getUTCFullYear();
}

// A Julian date, as [astronomical year, month, day], for days since
// 1970-01-01. From Richards' algorithm, with floor division throughout.
export function julianFromDays(epochDay: number): [number, number, number] {
  const c = epochDay + JULIAN_DAY_OF_UNIX_EPOCH + 32082;
  const d = Math.floor((4 * c + 3) / 1461);
  const e = c - Math.floor((1461 * d) / 4);
  const m = Math.floor((5 * e + 2) / 153);
  return [
    d - 4800 + Math.floor(m / 10),
    m + 3 - 12 * Math.floor(m / 10),
    e - Math.floor((153 * m + 2) / 5) + 1,
  ];
}

export function daysFromJulian(
  year: number,
  month: number,
  dayOfMonth: number,
): number {
  const a = Math.floor((14 - month) / 12);
  const y = year + 4800 - a;
  const m = month + 12 * a - 3;
  return (
    dayOfMonth +
    Math.floor((153 * m + 2) / 5) +
    365 * y +
    Math.floor(y / 4) -
    32083 -
    JULIAN_DAY_OF_UNIX_EPOCH
  );
}

// A day's [year, month, day] in a calendar with Gregorian months, which is
// Julian before `julianBefore` in some of them, like ICU's default.
export function civil(
  epochDay: number,
  julianBefore: number,
): [number, number, number] {
  if (epochDay < julianBefore) return julianFromDays(epochDay);
  const date = new Date(epochDay * DAY_MS);
  return [date.getUTCFullYear(), date.getUTCMonth() + 1, date.getUTCDate()];
}

// The day a civil date falls on, the inverse of `civil`.
export function civilDay(
  year: number,
  month: number,
  dayOfMonth: number,
  julianBefore: number,
): number {
  const julian = daysFromJulian(year, month, dayOfMonth);
  return julian < julianBefore ? julian : day(year, month, dayOfMonth);
}

// Where ICU switches from the Julian calendar, or -Infinity if it doesn't.
function julianSwitch(calendar: CalendarId): number {
  const matches = (d: number) =>
    fields(calendar, d).day === new Date(d * DAY_MS).getUTCDate();
  let low = day(...JULIAN_SEARCH[0]);
  if (matches(low)) return -Infinity;
  let high = day(...JULIAN_SEARCH[1]);
  while (low < high) {
    const middle = Math.floor((low + high) / 2);
    if (matches(middle)) high = middle;
    else low = middle + 1;
  }
  return low;
}

export const FIRST_DAY = day(FIRST_YEAR, 1, 1);
export const LAST_DAY = day(LAST_YEAR, MONTHS_PER_YEAR, 31);

// One day in a calendar, as ICU sees it. Names are English, and only used
// to tell values apart.
export type Fields = {
  era: string;
  year: number;
  extended: number;
  related: number;
  cycle: number;
  month: string;
  day: number;
};

function parseNumber(text: string): number {
  return Number(text.replace("−", "-"));
}

const readers = new Map<CalendarId, (epochDay: number) => Fields>();

export function fields(calendar: CalendarId, epochDay: number): Fields {
  let read = readers.get(calendar);
  if (!read) {
    read = reader(calendar);
    readers.set(calendar, read);
  }
  return read(epochDay);
}

function reader(calendar: CalendarId): (epochDay: number) => Fields {
  const options = { calendar, timeZone: "UTC" } as const;
  // Months are told apart by name and number, as a Hebrew month's number
  // depends on whether the year is a leap year.
  const numericMonth = new Intl.DateTimeFormat("en", {
    ...options,
    month: "numeric",
  });
  // Eras are told apart by all their names, as some share a long name.
  const eraNames = (["short", "narrow"] as const).map(
    (era) =>
      new Intl.DateTimeFormat("en", { ...options, era, year: "numeric" }),
  );
  const english = new Intl.DateTimeFormat("en", {
    ...options,
    era: "long",
    year: "numeric",
    month: "long",
    day: "numeric",
  });
  // Korean writes the Chinese and Dangi year as its place in the 60 year
  // cycle.
  const korean = new Intl.DateTimeFormat("ko", {
    ...options,
    dateStyle: "short",
  });
  const cyclic = calendar === "chinese" || calendar === "dangi";
  return (epochDay) => {
    const date = new Date(epochDay * DAY_MS + NOON_MS);
    // Typed as strings, as TypeScript doesn't know "relatedYear" yet.
    const parts = new Map<string, string>(
      english.formatToParts(date).map((p) => [p.type, p.value]),
    );
    const year = cyclic
      ? parseNumber(
          korean.formatToParts(date).find((p) => p.type === "year")!.value,
        )
      : parseNumber(parts.get("year")!);
    const related = parts.has("relatedYear")
      ? parseNumber(parts.get("relatedYear")!)
      : 0;
    return {
      era: [
        parts.get("era") ?? "",
        ...eraNames.map(
          (f) =>
            f.formatToParts(date).find((p) => p.type === "era")?.value ?? "",
        ),
      ].join(" / "),
      year,
      // Filled in per year by `table`, as it can't be read for one day.
      extended: 0,
      related,
      cycle: cyclic ? year - 1 : 0,
      month: `${parts.get("month")!} ${numericMonth.format(date)}`,
      day: parseNumber(parts.get("day")!),
    };
  };
}

// Galician's patterns write ICU's week-based year, which is the extended
// year except near the start and end of a year. Returns undefined for
// calendars whose Galician patterns don't use it.
const galicians = new Map<CalendarId, Intl.DateTimeFormat>();

export function weekYear(
  calendar: CalendarId,
  epochDay: number,
): number | undefined {
  let galician = galicians.get(calendar);
  if (!galician) {
    galician = new Intl.DateTimeFormat("gl", {
      calendar,
      timeZone: "UTC",
      dateStyle: "full",
    });
    galicians.set(calendar, galician);
  }
  const unknown = galician
    .formatToParts(new Date(epochDay * DAY_MS + NOON_MS))
    .find((p) => p.type === "unknown");
  return unknown && parseNumber(unknown.value);
}

// --- Calendars with Gregorian months --------------------------------------

// From `start` until the next era, the year is `base + sign * y` where `y` is
// the astronomical Gregorian year (1 BC is 0).
export type EraSegment = {
  start: number;
  era: number;
  base: number;
  sign: number;
};

export type Proleptic = {
  kind: "proleptic";
  // Newest first. The oldest starts at `-Infinity`.
  eras: EraSegment[];
  // A day in each era, by era number, to sample names in each locale.
  eraDays: number[];
  // English era names, by era number, to check against ICU.
  eraNames: string[];
  // Days before this are in the Julian calendar, as ICU does by default for
  // calendars other than Gregorian. -Infinity if never.
  julianBefore: number;
};

export function proleptic(calendar: CalendarId): Proleptic {
  const at = (d: number) => fields(calendar, d);
  const julianBefore = julianSwitch(calendar);
  const yearOf = (d: number) => civil(d, julianBefore)[0];
  // Find the first day of each era, checking every month. An era can change
  // more than once in a month.
  const starts: number[] = [];
  let previous = at(day(SCAN_FROM, 1, 1)).era;
  // Some ICU data has no era names, so an era also starts where the year
  // stops counting the way it did, as it does going from 1 BC to AD 1.
  let direction = 0;
  for (let year = SCAN_FROM; year <= LAST_YEAR; year++)
    for (let month = 1; month <= MONTHS_PER_YEAR; month++) {
      if (month === 1 && year > SCAN_FROM) {
        const newYear = civilDay(year, 1, 1, julianBefore);
        const before = at(newYear - 1);
        const after = at(newYear);
        if (before.era === after.era) {
          const step = after.year - before.year;
          if (step === 0 || (direction !== 0 && step !== direction)) {
            starts.push(newYear);
            direction = 0;
          } else direction = step;
        } else direction = 0;
      }
      const end = day(year, month + 1, 1) - 1;
      let low = day(year, month, 1);
      while (at(end).era !== previous) {
        let high = end;
        while (low < high) {
          const middle = Math.floor((low + high) / 2);
          if (at(middle).era === previous) low = middle + 1;
          else high = middle;
        }
        starts.push(low);
        previous = at(low).era;
      }
    }

  const names: string[] = [];
  const keys: string[] = [];
  const segments: (EraSegment & { name: string })[] = [];
  const bounds = [-Infinity, ...starts];
  bounds.forEach((start, i) => {
    const end = i + 1 < bounds.length ? bounds[i + 1]! - 1 : LAST_DAY;
    const first = Number.isFinite(start) ? start : day(SCAN_FROM, 1, 1);
    const a = at(first);
    const other = at(end);
    const ya = yearOf(first);
    const yb = yearOf(end);
    const sign = yb === ya ? 1 : (other.year - a.year) / (yb - ya);
    if (sign !== 1 && sign !== -1)
      throw new Error(`${calendar}: odd years in ${a.era}`);
    segments.push({
      start,
      era: 0,
      base: a.year - sign * ya,
      sign,
      name: a.era,
    });
  });
  // Newest era first, so modern dates are found quickly.
  segments.reverse();
  for (const segment of segments) {
    // Some eras share an English name but count the other way, like the two
    // Coptic eras, so the direction is part of what makes an era.
    const key = `${segment.name} ${segment.sign}`;
    if (!keys.includes(key)) {
      keys.push(key);
      names.push(segment.name);
    }
    segment.era = keys.indexOf(key);
  }

  const result: Proleptic = {
    kind: "proleptic",
    eraNames: names,
    julianBefore,
    eras: segments.map(({ start, era, base, sign }) => ({
      start,
      era,
      base,
      sign,
    })),
    eraDays: names.map((_, era) => {
      const segment = segments.find((s) => s.era === era)!;
      return Number.isFinite(segment.start)
        ? segment.start
        : day(SCAN_FROM, ...MID_YEAR);
    }),
  };

  // The rules must hold well outside the range we looked at.
  const checks = [
    day(CHECK_FROM_YEAR, ...MID_YEAR),
    day(-1, 1, 1),
    day(CHECK_TO_YEAR, MONTHS_PER_YEAR, 31),
  ];
  for (let d = FIRST_DAY; d <= LAST_DAY; d += CHECK_EVERY) checks.push(d);
  for (const start of starts) checks.push(start - 1, start);
  for (const d of checks) {
    const expected = at(d);
    const got = prolepticDate(result, d);
    const week = weekYear(calendar, d);
    const midYear = civilDay(yearOf(d), ...MID_YEAR, julianBefore);
    if (week !== undefined && weekYear(calendar, midYear) !== yearOf(d))
      throw new Error(
        `${calendar}: the extended year isn't the Gregorian year`,
      );
    if (names[got.era] !== expected.era || got.year !== expected.year)
      throw new Error(
        `${calendar}: era rules are wrong on day ${d}: expected ${expected.era} ${expected.year}, got ${names[got.era]} ${got.year}`,
      );
  }
  return result;
}

export function prolepticDate(calendar: Proleptic, epochDay: number) {
  const segment = calendar.eras.find((s) => s.start <= epochDay)!;
  return {
    era: segment.era,
    year:
      segment.base + segment.sign * civil(epochDay, calendar.julianBefore)[0],
  };
}

// --- Calendars with their own months --------------------------------------

// From year `from` until the next segment, each year adds `yearStep` to the
// year and 1 to the extended year. In cyclic calendars it also adds 1 to the
// related year and the cycle.
export type YearSegment = {
  from: number;
  era: number;
  year: number;
  yearStep: number;
  extended: number;
  related: number;
  cycle: number;
};

export type Table = {
  kind: "table";
  // Chinese and Dangi, which have related years and a 60 year cycle.
  cyclic: boolean;
  // The first day of each year, then the day after the last year.
  starts: number[];
  // Which month shape each year has.
  shapes: number[];
  // Each shape is a list of [month number, length in days].
  months: [number, number][][];
  years: YearSegment[];
  // English names, by number, and a day in each, to sample names in each
  // locale.
  monthDays: number[];
  eraDays: number[];
  cycleDays: number[];
  // A month with 30 days, to sample day names.
  longMonth: number;
  // English names, by number, to check against ICU.
  monthNames: string[];
  eraNames: string[];
  // Days that ICU calls day 0 of a month, as [day, month number]. ICU's
  // Chinese calendar makes a few of these, where its astronomy goes wrong.
  dayZero: [number, number][];
};

export function table(calendar: CalendarId): Table {
  const at = (d: number) => fields(calendar, d);
  // Months, as [first day, fields].
  const months: [number, Fields][] = [];
  let start = FIRST_DAY;
  while (at(start).day !== 1) start++;
  while (start <= LAST_DAY + 1) {
    const f = at(start);
    months.push([start, f]);
    // The day before the shortest month ends is either still in this month,
    // or `x` days into the next.
    let next = start + SHORTEST_MONTH - 1;
    const x = at(next).day;
    if (x !== SHORTEST_MONTH) next -= x - 1;
    else {
      while (at(next).day !== 1) next++;
    }
    start = next;
  }

  const sameYear = (a: Fields, b: Fields) =>
    a.era === b.era && a.year === b.year && a.related === b.related;
  type Year = { start: number; fields: Fields; months: [string, number][] };
  const years: Year[] = [];
  for (let i = 0; i + 1 < months.length; i++) {
    const [first, f] = months[i]!;
    const length = months[i + 1]![0] - first;
    const last = years.at(-1);
    if (last && sameYear(last.fields, f)) last.months.push([f.month, length]);
    else years.push({ start: first, fields: f, months: [[f.month, length]] });
  }
  // Only whole years: the first may have started before FIRST_DAY, and the
  // last may run past the months we read.
  years.shift();
  const end = years.at(-1)!;
  while (
    years.length &&
    years.at(-1)!.start + years.at(-1)!.months.reduce((a, [, l]) => a + l, 0) >
      LAST_DAY + 1
  )
    years.pop();
  if (years.at(-1) === end) years.pop();
  // The week-based year is the extended year in the middle of a year.
  for (const year of years) {
    const middle =
      year.start + Math.floor(year.months.reduce((a, [, l]) => a + l, 0) / 2);
    year.fields.extended = weekYear(calendar, middle) ?? year.fields.related;
  }

  const monthNames: string[] = [];
  const monthDays: number[] = [];
  const eraNames: string[] = [];
  const eraKeys: string[] = [];
  const eraDays: number[] = [];
  const cycleDays: number[] = [];
  let longMonth = -1;
  const shapeKeys = new Map<string, number>();
  const shapes: [number, number][][] = [];
  const result: Table = {
    kind: "table",
    cyclic: calendar === "chinese" || calendar === "dangi",
    starts: [],
    shapes: [],
    months: shapes,
    years: [],
    monthDays,
    eraDays,
    cycleDays,
    longMonth: 0,
    monthNames,
    eraNames,
    dayZero: [],
  };
  for (const [i, year] of years.entries()) {
    const shape = year.months.map(([name, length], m): [number, number] => {
      if (!monthNames.includes(name)) {
        monthNames.push(name);
        monthDays.push(
          year.start +
            year.months.slice(0, m).reduce((a, [, l]) => a + l, 0) +
            INTO_MONTH,
        );
      }
      if (length === LONGEST_LUNAR_MONTH && longMonth < 0)
        longMonth =
          year.start + year.months.slice(0, m).reduce((a, [, l]) => a + l, 0);
      return [monthNames.indexOf(name), length];
    });
    const key = JSON.stringify(shape);
    if (!shapeKeys.has(key)) {
      shapeKeys.set(key, shapes.length);
      shapes.push(shape);
    }
    result.starts.push(year.start);
    result.shapes.push(shapeKeys.get(key)!);
    const f = year.fields;
    // As with eras in `proleptic`, the direction is part of what makes an era.
    // Where two eras meet, both years can be 1, so use whichever neighbour
    // shows a step.
    const steps = [
      years[i + 1] && years[i + 1]!.fields.era === f.era
        ? years[i + 1]!.fields.year - f.year
        : 0,
      years[i - 1] && years[i - 1]!.fields.era === f.era
        ? f.year - years[i - 1]!.fields.year
        : 0,
    ];
    const direction = result.cyclic
      ? 1
      : Math.sign(steps.find((step) => step !== 0) ?? 1);
    const eraKey = `${f.era} ${direction}`;
    if (!eraKeys.includes(eraKey)) {
      eraKeys.push(eraKey);
      eraNames.push(f.era);
      eraDays.push(year.start + INTO_MONTH);
    }
    if (cycleDays[f.cycle] === undefined)
      cycleDays[f.cycle] = year.start + INTO_MONTH;
    const era = eraKeys.indexOf(eraKey);
    const last = result.years.at(-1);
    const step = result.cyclic ? 1 : 0;
    const fits =
      last &&
      last.era === era &&
      f.year === last.year + last.yearStep * (i - last.from) &&
      f.extended === last.extended + (i - last.from) &&
      f.related === last.related + step * (i - last.from) &&
      f.cycle === (last.cycle + step * (i - last.from)) % YEARS_IN_CYCLE;
    if (!fits) {
      const nextYear = years[i + 1]?.fields;
      const step =
        nextYear && nextYear.era === f.era && nextYear.year === f.year - 1
          ? -1
          : 1;
      result.years.push({
        from: i,
        era,
        year: f.year,
        yearStep: step,
        extended: f.extended,
        related: f.related,
        cycle: f.cycle,
      });
    }
  }
  const lastYear = years.at(-1)!;
  result.starts.push(
    lastYear.start + lastYear.months.reduce((a, [, l]) => a + l, 0),
  );
  result.longMonth = longMonth;
  // A day 0 is read as the last day of the month before, so look at the
  // last day of every month.
  for (let i = 0; i + 1 < months.length; i++) {
    const last = months[i + 1]![0] - 1;
    const f = at(last);
    if (f.day === 0) result.dayZero.push([last, monthNames.indexOf(f.month)]);
  }

  // Check every month we read, and a day in the middle of each, against ICU.
  for (const [first] of months) {
    for (const d of [first, first + MID_MONTH]) {
      if (d < result.starts[0]! || d >= result.starts.at(-1)!) continue;
      const expected = at(d);
      const got = tableDate(result, d)!;
      if (
        monthNames[got.month] !== expected.month ||
        got.day !== expected.day ||
        got.year !== expected.year ||
        eraNames[got.era] !== expected.era ||
        got.related !== expected.related ||
        got.cycle !== expected.cycle
      )
        throw new Error(
          `${calendar}: table is wrong on day ${d}: expected ${JSON.stringify(expected)}, got ${JSON.stringify({ ...got, month: monthNames[got.month], era: eraNames[got.era] })}`,
        );
    }
  }
  return result;
}

export function tableDate(calendar: Table, epochDay: number) {
  const { starts } = calendar;
  if (epochDay < starts[0]! || epochDay >= starts.at(-1)!) return undefined;
  let i = Math.floor(
    ((epochDay - starts[0]!) * (starts.length - 1)) /
      (starts.at(-1)! - starts[0]!),
  );
  while (starts[i]! > epochDay) i--;
  while (starts[i + 1]! <= epochDay) i++;
  let rest = epochDay - starts[i]!;
  let month = 0;
  for (const [number, length] of calendar.months[calendar.shapes[i]!]!) {
    if (rest < length) {
      month = number;
      break;
    }
    rest -= length;
  }
  const zero = calendar.dayZero.find(([d]) => d === epochDay);
  if (zero) {
    month = zero[1];
    rest = -1;
  }
  const segment = calendar.years.findLast((s) => s.from <= i)!;
  const n = i - segment.from;
  const step = calendar.cyclic ? n : 0;
  return {
    era: segment.era,
    year: segment.year + segment.yearStep * n,
    extended: segment.extended + n,
    related: segment.related + step,
    cycle: (segment.cycle + step) % YEARS_IN_CYCLE,
    month,
    day: rest + 1,
  };
}

export type Math_ = Proleptic | Table;

export function calendarMath(calendar: CalendarId): Math_ {
  const kind = CALENDARS.find((c) => c.id === calendar)!.kind;
  return kind === "proleptic" ? proleptic(calendar) : table(calendar);
}

// Everything about a day that a pattern can show, with month and era as
// numbers. Undefined outside a table's years.
export type CalendarDate = {
  era: number;
  year: number;
  extended: number;
  related: number;
  cycle: number;
  // Index into the calendar's month names. For Gregorian months, 0 to 11.
  month: number;
  day: number;
  // The first day of this year and of the next, for week-based years.
  yearStart: number;
  nextYearStart: number;
};

export function calendarDate(
  math: Math_,
  epochDay: number,
): CalendarDate | undefined {
  if (math.kind === "proleptic") {
    const [y, m, d] = civil(epochDay, math.julianBefore);
    return {
      ...prolepticDate(math, epochDay),
      extended: y,
      related: y,
      cycle: 0,
      month: m - 1,
      day: d,
      yearStart: civilDay(y, 1, 1, math.julianBefore),
      nextYearStart: civilDay(y + 1, 1, 1, math.julianBefore),
    };
  }
  const date = tableDate(math, epochDay);
  if (!date) return undefined;
  const { starts } = math;
  let i = 0;
  while (starts[i + 1]! <= epochDay) i++;
  return { ...date, yearStart: starts[i]!, nextYearStart: starts[i + 1]! };
}

// ICU's week-based year, in extended years. Weeks start on `firstDay`
// (1 is Monday, 7 is Sunday), and a year's first week is the first with at
// least `minimalDays` days in that year. `exceptions` gives the first day of
// years where ICU starts them somewhere else, as [extended year, day].
export function weekBasedYear(
  date: CalendarDate,
  epochDay: number,
  firstDay: number,
  minimalDays: number,
  exceptions: [number, number][] = [],
): number {
  const firstWeek = (yearStart: number, extended: number) => {
    const exception = exceptions.find(([year]) => year === extended);
    if (exception) return exception[1];
    const weekStart =
      yearStart -
      ((isoWeekday(yearStart) - firstDay + DAYS_PER_WEEK) % DAYS_PER_WEEK);
    return DAYS_PER_WEEK - (yearStart - weekStart) >= minimalDays
      ? weekStart
      : weekStart + DAYS_PER_WEEK;
  };
  if (epochDay >= firstWeek(date.nextYearStart, date.extended + 1))
    return date.extended + 1;
  if (epochDay < firstWeek(date.yearStart, date.extended))
    return date.extended - 1;
  return date.extended;
}

// Checks a calendar's maths against ICU on every day it covers: years 1 to
// 4000 for tables, and 5000 BC to AD 4000 for the others.
export function checkEveryDay(calendar: CalendarId, math: Math_): number {
  const [from, to] =
    math.kind === "table"
      ? [math.starts[0]!, math.starts.at(-1)! - 1]
      : [day(SCAN_FROM, 1, 1), LAST_DAY];
  for (let d = from; d <= to; d++) {
    const expected = fields(calendar, d);
    const got = calendarDate(math, d);
    const ok =
      got !== undefined &&
      math.eraNames[got.era] === expected.era &&
      got.year === expected.year &&
      (math.kind === "proleptic"
        ? Number(expected.month.split(" ").at(-1)) === got.month + 1 &&
          got.day === expected.day
        : math.monthNames[got.month] === expected.month &&
          got.day === expected.day &&
          got.related === expected.related &&
          got.cycle === expected.cycle);
    if (!ok)
      throw new Error(
        `${calendar}: day ${d} is wrong: expected ${JSON.stringify(expected)}, got ${JSON.stringify(got)}`,
      );
  }
  return to - from + 1;
}

// Weekdays numbered from Monday, as ICU's week data does. 1970-01-01 was a
// Thursday.
const THURSDAY_FROM_MONDAY = 4;

// A day's weekday, from 1 for Monday to 7 for Sunday.
export function isoWeekday(epochDay: number): number {
  return (
    ((((epochDay + THURSDAY_FROM_MONDAY - 1) % DAYS_PER_WEEK) + DAYS_PER_WEEK) %
      DAYS_PER_WEEK) +
    1
  );
}
