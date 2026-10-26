// Works out how each calendar maps days to its own eras, years, months and
// days, by asking ICU about every month from 0001 to 4000.

export const DAY_MS = 86_400_000;

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

// Table calendars cover whole years inside this range.
export const FIRST_DAY = day(1, 1, 1);
export const LAST_DAY = day(4000, 12, 31);

// Eras are looked for from here, and assumed not to change before.
const SCAN_FROM = -5000;

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
    const date = new Date(epochDay * DAY_MS + DAY_MS / 2);
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
    .formatToParts(new Date(epochDay * DAY_MS + DAY_MS / 2))
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
};

export function proleptic(calendar: CalendarId): Proleptic {
  const at = (d: number) => fields(calendar, d);
  // Find the first day of each era, checking every month. An era can change
  // more than once in a month.
  const starts: number[] = [];
  let previous = at(day(SCAN_FROM, 1, 1)).era;
  for (let year = SCAN_FROM; year <= 4000; year++)
    for (let month = 1; month <= 12; month++) {
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
    const ya = astronomicalYear(first);
    const yb = astronomicalYear(end);
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
        : day(SCAN_FROM, 6, 1);
    }),
  };

  // The rules must hold well outside the range we looked at.
  const checks = [day(-9000, 6, 1), day(-1, 1, 1), day(9999, 12, 31)];
  for (let d = FIRST_DAY; d <= LAST_DAY; d += 997) checks.push(d);
  for (const start of starts) checks.push(start - 1, start);
  for (const d of checks) {
    const expected = at(d);
    const got = prolepticDate(result, d);
    const week = weekYear(calendar, d);
    const midYear = day(astronomicalYear(d), 7, 1);
    if (
      week !== undefined &&
      weekYear(calendar, midYear) !== astronomicalYear(d)
    )
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
    year: segment.base + segment.sign * astronomicalYear(epochDay),
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
    // `start + 28` is either still in this month, or `x` days into the next.
    let next = start + 28;
    const x = at(next).day;
    if (x !== 29) next -= x - 1;
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
            4,
        );
      }
      if (length === 30 && longMonth < 0)
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
      eraDays.push(year.start + 4);
    }
    if (cycleDays[f.cycle] === undefined) cycleDays[f.cycle] = year.start + 4;
    const era = eraKeys.indexOf(eraKey);
    const last = result.years.at(-1);
    const step = result.cyclic ? 1 : 0;
    const fits =
      last &&
      last.era === era &&
      f.year === last.year + last.yearStep * (i - last.from) &&
      f.extended === last.extended + (i - last.from) &&
      f.related === last.related + step * (i - last.from) &&
      f.cycle === (last.cycle + step * (i - last.from)) % 60;
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
    for (const d of [first, first + 14]) {
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
    cycle: (segment.cycle + step) % 60,
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
    const date = new Date(epochDay * DAY_MS);
    const y = date.getUTCFullYear();
    return {
      ...prolepticDate(math, epochDay),
      extended: y,
      related: y,
      cycle: 0,
      month: date.getUTCMonth(),
      day: date.getUTCDate(),
      yearStart: day(y, 1, 1),
      nextYearStart: day(y + 1, 1, 1),
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
    // 1970-01-01 was a Thursday, day 4.
    const weekday = ((((yearStart + 3) % 7) + 7) % 7) + 1;
    const weekStart = yearStart - ((weekday - firstDay + 7) % 7);
    return 7 - (yearStart - weekStart) >= minimalDays
      ? weekStart
      : weekStart + 7;
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
      (math.kind === "proleptic" ||
        (math.monthNames[got.month] === expected.month &&
          got.day === expected.day &&
          got.related === expected.related &&
          got.cycle === expected.cycle));
    if (!ok)
      throw new Error(
        `${calendar}: day ${d} is wrong: expected ${JSON.stringify(expected)}, got ${JSON.stringify(got)}`,
      );
  }
  return to - from + 1;
}
