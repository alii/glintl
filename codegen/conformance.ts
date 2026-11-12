// Checks glintl on Erlang against Intl.DateTimeFormat on random cases, each
// with its own locale, calendar, styles or fields, moment and offset.
//
//   bun codegen/conformance.ts [cases] [seed]
//
// Intl's answers depend on the Bun that runs this. If the pinned Bun is only
// in Docker and Erlang is elsewhere, save the cases with one and check them
// with the other:
//
//   bun codegen/conformance.ts --save cases.tsv [cases] [seed]
//   bun codegen/conformance.ts --check cases.tsv
//
// To check every mix of fields in every hour cycle for one locale and calendar,
// at fixed moments, run this. A part, like 3/16, checks every 16th request
// from the 3rd, so several runs can share the work.
//
//   bun codegen/conformance.ts --every ja@japanese [part/parts]
//
// Cases come in groups that share a formatter, because making an
// Intl.DateTimeFormat is slow. Moments lean towards midnight, noon and
// whole hours, where day periods change.

import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import {
  CALENDARS,
  FIRST_YEAR,
  LAST_YEAR,
  NOON_MS,
  SCAN_FROM,
  day,
} from "./calendars.ts";
import {
  FIELD_CHOICES,
  type Field,
  fieldsText,
  randomFields,
} from "./fixtures.ts";
import { LOCALES } from "./locales.ts";
import { HOUR_CYCLES } from "./patterns.ts";
import { random } from "./random.ts";
import { requirePinnedBun } from "./runtime.ts";
import { zoneData } from "./zones.ts";
import {
  HOURS_PER_DAY,
  HOURS_PER_HALF_DAY,
  MS_PER_SECOND,
  SECONDS_PER_DAY,
  SECONDS_PER_HOUR,
  SECONDS_PER_MINUTE,
  offsetString,
} from "./time.ts";

const ROOT = join(import.meta.dir, "..");

const MODES = ["--save", "--check", "--every", "--zones"];

const [mode, argument] = MODES.includes(process.argv[2]!)
  ? [process.argv[2]!, process.argv[3]!]
  : ["--live", ""];

// Checking saved cases doesn't ask Intl anything.
if (mode !== "--check") {
  requirePinnedBun("codegen/conformance.ts");
}

const counts =
  mode === "--live" ? process.argv.slice(2) : process.argv.slice(4);

const CASES = Number(counts[0] ?? 1_000_000);
const SEED = Number(counts[1] ?? 1);

// How many cases share a formatter, and how many go to Erlang at once.
const GROUP = 100;
const BATCH = 20_000;

// Style names by number, where 0 means none.
const STYLES = [undefined, "full", "long", "medium", "short"] as const;

// How often a group picks fields instead of styles.
const FIELDS_SHARE = 0.5;

// How often a moment falls exactly on midnight, noon or the hour, where day
// periods change. The rest are random.
const MIDNIGHT_SHARE = 0.1;
const NOON_SHARE = 0.1;
const WHOLE_HOUR_SHARE = 0.1;

// Show at most this many failures, and this many failing locale and calendar
// pairs.
const MOST_SHOWN = 20;
const OFFSETS = [0, 60, -480, 330, 345, -210, 840, -600, 525, -720, 765];

// Table calendars cover these days on Erlang. We stay a year in from each end
// because a table's first and last years may not reach 1 January. Other
// calendars have no limit, so they also get days far in the past.
const TABLE_DAYS: [number, number] = [
  day(FIRST_YEAR + 1, 1, 1),
  day(LAST_YEAR - 1, 1, 1),
];

const ALL_DAYS: [number, number] = [day(SCAN_FROM, 1, 1), TABLE_DAYS[1]];

const next = random(SEED);

const pick = <T>(items: readonly T[]): T =>
  items[Math.floor(next() * items.length)]!;

const kindOf = (calendar: string) =>
  CALENDARS.find((c) => c.id === calendar)!.kind;

const between = ([from, to]: [number, number]) =>
  from + Math.floor(next() * (to - from));

type Case = { line: string; expected: string };

// ICU mixes up the era and year in table calendars when the local and UTC
// dates fall in different eras, so we leave those moments out. glintl's
// README explains this.
const eraFormatters = new Map<string, Intl.DateTimeFormat>();

function eraFormatter(calendar: string): Intl.DateTimeFormat {
  const f = new Intl.DateTimeFormat("en", {
    calendar,
    // Use short names because both Coptic eras have the same long name in English.
    era: "short",
    timeZone: "UTC",
  });

  eraFormatters.set(calendar, f);

  return f;
}

function eraOf(calendar: string, epochDay: number): string {
  const f = eraFormatters.get(calendar) ?? eraFormatter(calendar);

  return f.format(epochDay * SECONDS_PER_DAY * MS_PER_SECOND + NOON_MS);
}

function eraSplit(
  calendar: string,
  localDay: number,
  utcSeconds: number,
): boolean {
  const utcDay = Math.floor(utcSeconds / SECONDS_PER_DAY);

  return (
    utcDay !== localDay && eraOf(calendar, utcDay) !== eraOf(calendar, localDay)
  );
}

// Calls `more` until at least `count` items have been gathered.
function gather<T>(count: number, more: () => T[], gathered: T[] = []): T[] {
  if (gathered.length >= count) {
    return gathered;
  }

  gathered.push(...more());

  return gather(count, more, gathered);
}

function group(): Case[] {
  const tag = pick(LOCALES)[1];
  const calendar = next() < 0.5 ? "" : pick(CALENDARS).id;

  const resolved =
    calendar || new Intl.DateTimeFormat(tag).resolvedOptions().calendar;

  const kind = kindOf(resolved);
  // 0 means no date style. A case without a date must have a time.
  const drawn = Math.floor(next() * STYLES.length);

  const time =
    drawn === 0
      ? 1 + Math.floor(next() * (STYLES.length - 1))
      : Math.floor(next() * STYLES.length);

  const date = drawn === 0 && time === 0 ? 1 : drawn;

  const offset = pick(OFFSETS);

  // Empty means the locale's own hour cycle.
  const hourCycle = next() < 0.5 ? "" : pick(HOUR_CYCLES);
  const fields = next() < FIELDS_SHARE ? randomFields(next) : [];

  const formatter = new Intl.DateTimeFormat(tag, {
    calendar: resolved,
    ...(fields.length > 0
      ? Object.fromEntries(fields)
      : { dateStyle: STYLES[date], timeStyle: STYLES[time] }),
    timeZone: offsetString(offset),
    hourCycle: hourCycle === "" ? undefined : hourCycle,
  });

  const fieldsLine = fieldsText(fields);

  const [dateShown, timeShown] = fields.length > 0 ? [0, 0] : [date, time];

  return gather(GROUP, (): Case[] => {
    const epochDay = between(kind === "table" ? TABLE_DAYS : ALL_DAYS);
    const r = next();

    const secondOfDay =
      r < MIDNIGHT_SHARE
        ? 0
        : r < MIDNIGHT_SHARE + NOON_SHARE
          ? HOURS_PER_HALF_DAY * SECONDS_PER_HOUR
          : r < MIDNIGHT_SHARE + NOON_SHARE + WHOLE_HOUR_SHARE
            ? Math.floor(next() * HOURS_PER_DAY) * SECONDS_PER_HOUR
            : Math.floor(next() * SECONDS_PER_DAY);

    const seconds =
      epochDay * SECONDS_PER_DAY + secondOfDay - offset * SECONDS_PER_MINUTE;

    if (kind === "table" && eraSplit(resolved, epochDay, seconds)) {
      return [];
    }

    const milliseconds =
      fields.length > 0 ? Math.floor(next() * MS_PER_SECOND) : 0;

    return [
      {
        line: [
          tag,
          calendar,
          dateShown,
          timeShown,
          hourCycle,
          fieldsLine,
          seconds,
          milliseconds,
          offset,
        ].join("\t"),
        expected: formatter.format(seconds * MS_PER_SECOND + milliseconds),
      },
    ];
  });
}

// --- Every mix of fields ------------------------------------------------------

// Local times where day periods change, and fractions that test cutting off.
const EVERY_TIMES: [number, number, number, number][] = [
  [0, 0, 0, 0],
  [0, 1, 0, 7],
  [11, 59, 59, 999],
  [12, 0, 0, 0],
  [12, 30, 45, 123],
  [18, 0, 0, 0],
  [23, 59, 59, 987],
];

// A normal day, then days where years or eras are written in a special way:
// the first year of Reiwa, the last day of Shōwa, and days before the Islamic
// and Coptic eras.
const EVERY_DAYS = [
  day(2026, 3, 5),
  day(2019, 5, 1),
  day(1989, 1, 7),
  day(500, 6, 15),
  day(200, 6, 15),
];

// The first day gets every time. The others get these ones.
const OTHER_DAY_TIMES = [EVERY_TIMES[0]!, EVERY_TIMES[4]!];

const EVERY_OFFSETS = [0, 60, 330, -600];

const EVERY_HOUR_CYCLE = ["", ...HOUR_CYCLES] as const;

// Each field can be left out, or shown with any of its values.
const EVERY_REQUEST =
  FIELD_CHOICES.reduce((n, [, values]) => n * (values.length + 1), 1) *
  EVERY_HOUR_CYCLE.length;

// Reads a request number as a choice for each field, then an hour cycle.
function requestAt(
  index: number,
): [Field[], (typeof EVERY_HOUR_CYCLE)[number]] {
  const fields: Field[] = [];

  const rest = FIELD_CHOICES.reduce((rest, [name, values]) => {
    const choice = rest % (values.length + 1);

    if (choice > 0) {
      fields.push([name, values[choice - 1]!]);
    }

    return Math.floor(rest / (values.length + 1));
  }, index);

  return [fields, EVERY_HOUR_CYCLE[rest]!];
}

const everyMoments = [
  ...EVERY_TIMES.map((time): [number, (typeof EVERY_TIMES)[number]] => [
    EVERY_DAYS[0]!,
    time,
  ]),
  ...EVERY_DAYS.slice(1).flatMap((d) =>
    OTHER_DAY_TIMES.map((time): [number, (typeof EVERY_TIMES)[number]] => [
      d,
      time,
    ]),
  ),
].map(([epochDay, [hours, minutes, seconds, milliseconds]], n) => {
  const offset = EVERY_OFFSETS[n % EVERY_OFFSETS.length]!;

  return {
    epochDay,
    offset,
    milliseconds,
    seconds:
      epochDay * SECONDS_PER_DAY +
      hours * SECONDS_PER_HOUR +
      minutes * SECONDS_PER_MINUTE +
      seconds -
      offset * SECONDS_PER_MINUTE,
  };
});

function everyCases(tag: string, calendar: string, index: number): Case[] {
  const [fields, hourCycle] = requestAt(index);

  const resolved =
    calendar || new Intl.DateTimeFormat(tag).resolvedOptions().calendar;

  const kind = kindOf(resolved);
  const fieldsLine = fieldsText(fields);

  const formatters = EVERY_OFFSETS.map(
    (offset) =>
      new Intl.DateTimeFormat(tag, {
        calendar: resolved,
        ...Object.fromEntries(fields),
        timeZone: offsetString(offset),
        hourCycle: hourCycle === "" ? undefined : hourCycle,
      }),
  );

  return everyMoments.flatMap(({ epochDay, offset, seconds, milliseconds }) => {
    if (kind === "table" && eraSplit(resolved, epochDay, seconds)) {
      return [];
    }

    const formatter = formatters[EVERY_OFFSETS.indexOf(offset)]!;

    return [
      {
        line: [
          tag,
          calendar,
          0,
          0,
          hourCycle,
          fieldsLine,
          seconds,
          milliseconds,
          offset,
        ].join("\t"),
        expected: formatter.format(seconds * MS_PER_SECOND + milliseconds),
      },
    ];
  });
}

function every(): IteratorObject<Case[]> {
  const [tag = "", calendar = ""] = argument.split("@");
  const [part = 1, parts = 1] = (counts[0] ?? "1/1").split("/").map(Number);

  // Gathers cases from every `parts`th request until there are enough for a
  // batch. Returns them and the next request.
  const batchFrom = (
    index: number,
    gathered: Case[] = [],
  ): [Case[], number] => {
    if (gathered.length >= BATCH || index >= EVERY_REQUEST) {
      return [gathered, index];
    }

    gathered.push(...everyCases(tag, calendar, index));

    return batchFrom(index + parts, gathered);
  };

  function* from(index: number): Generator<Case[]> {
    if (index >= EVERY_REQUEST) {
      return;
    }

    const [batch, next] = batchFrom(index);
    yield batch;
    yield* from(next);
  }

  return from(part - 1);
}

// --- Time zones ------------------------------------------------------------------

// Formats that show a time and an offset, never a zone's name.
const ZONE_FORMATS: [number, number, string][] = [
  [STYLES.indexOf("short"), STYLES.indexOf("medium"), ""],
  [0, 0, "hour=2-digit,minute=2-digit,second=2-digit,timeZoneName=longOffset"],
  [0, 0, "day=numeric,month=short,hour=numeric,timeZoneName=shortOffset"],
];

// Formats that show a zone's name where the locale has one: the full time
// style's long name, the long one's short name, and the same as fields.
const NAME_FORMATS: [number, number, string][] = [
  [0, STYLES.indexOf("full"), ""],
  [STYLES.indexOf("short"), STYLES.indexOf("long"), ""],
  [0, 0, "hour=numeric,minute=2-digit,timeZoneName=short"],
  [0, 0, "day=numeric,month=short,hour=numeric,timeZoneName=long"],
];

// Locales with names in different shapes, for every zone.
const NAME_LOCALES = [
  "en-GB",
  "en",
  "en-AU",
  "fr",
  "de",
  "es-MX",
  "pt-BR",
  "ru",
  "ja",
  "zh",
  "zh-Hant",
  "ko",
  "ar",
  "he",
  "hi",
  "sw",
  "fil",
];

// Zones to check in every locale.
const COMMON_ZONES = [
  "Europe/London",
  "America/New_York",
  "America/Los_Angeles",
  "Asia/Tokyo",
  "Asia/Kolkata",
  "Europe/Paris",
  "Australia/Sydney",
  "America/Sao_Paulo",
  "UTC",
  "Africa/Accra",
  "Asia/Shanghai",
  "Pacific/Auckland",
];

const NAME_MOMENTS = [
  Date.UTC(1950, 5, 1),
  Date.UTC(1975, 0, 15),
  Date.UTC(1999, 6, 15),
  Date.UTC(2026, 0, 15),
  Date.UTC(2026, 6, 15),
  Date.UTC(2040, 6, 15),
].map((ms) => ms / MS_PER_SECOND);

// Years after the data's last change where zones follow a yearly rule.
const RULE_YEARS = [2030, 2037, 2038, 2050, 2099, 2100, 2400, 3999];

const DAYS_PER_YEAR = 366;

const intlOffsets = new Map<string, Intl.DateTimeFormat>();

// The zone's offset at a moment as Intl writes it, like "GMT+01:00".
function intlOffset(zone: string, seconds: number): string {
  const f =
    intlOffsets.get(zone) ??
    new Intl.DateTimeFormat("en", {
      timeZone: zone,
      timeZoneName: "longOffset",
    });

  intlOffsets.set(zone, f);

  return f
    .formatToParts(seconds * MS_PER_SECOND)
    .find((p) => p.type === "timeZoneName")!.value;
}

// The second the offset changes between `from`, which has one offset, and
// `to`, which has another.
function change(zone: string, from: number, to: number): number {
  if (to - from <= 1) {
    return to;
  }

  const middle = Math.floor((from + to) / 2);

  return intlOffset(zone, middle) === intlOffset(zone, from)
    ? change(zone, middle, to)
    : change(zone, from, middle);
}

// Moments where a zone's offset changes in a year, found by asking Intl.
function changesIn(zone: string, year: number): number[] {
  const start = Date.UTC(year, 0, 1) / MS_PER_SECOND;

  return Array.from(
    { length: DAYS_PER_YEAR },
    (_, d) => start + d * SECONDS_PER_DAY,
  ).flatMap((day, d, days) => {
    const next = days[d + 1];

    return next !== undefined &&
      intlOffset(zone, day) !== intlOffset(zone, next)
      ? [change(zone, day, next)]
      : [];
  });
}

function zoneCases(
  zone: string,
  moments: number[],
  tag = "en-GB",
  formats = ZONE_FORMATS,
): Case[] {
  return formats.flatMap(([date, time, fields]) => {
    const formatter = new Intl.DateTimeFormat(tag, {
      ...(fields === ""
        ? { dateStyle: STYLES[date], timeStyle: STYLES[time] }
        : Object.fromEntries(fields.split(",").map((f) => f.split("=")))),
      timeZone: zone,
    });

    return moments.map((seconds) => ({
      line: [tag, "", date, time, "", fields, seconds, 0, zone].join("\t"),
      expected: formatter.format(seconds * MS_PER_SECOND),
    }));
  });
}

// Every zone Intl accepts, a second before and at each change in glintl's
// data, and at each yearly change in some later years.
function zoneBatches(): IteratorObject<Case[]> {
  const data = zoneData();
  const seen = new Set<number>();

  const samples = [
    Date.UTC(1800, 5, 1),
    Date.UTC(1950, 5, 1),
    Date.UTC(2026, 0, 15),
    Date.UTC(2026, 6, 15),
  ].map((ms) => ms / MS_PER_SECOND);

  return data.names.values().map(([name, zone]) => {
    // A zone's other names only get the sample moments.
    const first = !seen.has(zone);
    seen.add(zone);

    const rules = data.zones[zone]!;

    const ruled =
      first && rules.final !== undefined
        ? RULE_YEARS.flatMap((year) => changesIn(name, year))
        : [];

    const moments = [...(first ? rules.transitions : []), ...ruled].flatMap(
      (t) => [t - 1, t],
    );

    // Names change with summer time, so also check the changes near now.
    const recent = rules.transitions.filter(
      (t) => t > NAME_MOMENTS[1]! && t < NAME_MOMENTS.at(-1)!,
    );

    return [
      ...zoneCases(name, [...moments, ...samples]),
      ...NAME_LOCALES.flatMap((tag) =>
        zoneCases(
          name,
          [...NAME_MOMENTS, ...recent.flatMap((t) => [t - 1, t])],
          tag,
          NAME_FORMATS,
        ),
      ),
    ];
  });
}

function* allZoneBatches(): Generator<Case[]> {
  yield* zoneBatches();
  yield* everyLocaleZones();
}

// Common zones in every locale, with names where the locale has them.
const everyLocaleZones = (): IteratorObject<Case[]> =>
  LOCALES.values().map(([, tag]) =>
    COMMON_ZONES.flatMap((zone) =>
      zoneCases(zone, NAME_MOMENTS, tag, NAME_FORMATS),
    ),
  );

// --- Checking -----------------------------------------------------------------

// Cases are made here, or read from a saved file whose first line names the
// Intl that made them.
const [header, ...saved] =
  mode === "--check"
    ? readFileSync(argument, "utf8").trimEnd().split("\n")
    : [];

const intl = header ?? `Bun ${Bun.version}, ICU ${process.versions.icu}`;

function parse(line: string): Case {
  const at = line.lastIndexOf("\t");

  return {
    line: line.slice(0, at),
    expected: JSON.parse(line.slice(at + 1)),
  };
}

function* made(count: number): Generator<Case[]> {
  if (count >= CASES) {
    return;
  }

  const batch = gather(Math.min(BATCH, CASES - count), group);
  yield batch;
  yield* made(count + batch.length);
}

function batches(): IteratorObject<Case[]> {
  if (mode === "--check") {
    return Array.from(
      { length: Math.ceil(saved.length / BATCH) },
      (_, n) => n * BATCH,
    )
      .values()
      .map((n) => saved.slice(n, n + BATCH).map(parse));
  }

  return mode === "--every"
    ? every()
    : mode === "--zones"
      ? allZoneBatches()
      : made(0);
}

if (mode === "--save") {
  const lines = [
    intl,
    ...batches()
      .flatMap((batch) => batch)
      .map((c) => `${c.line}\t${JSON.stringify(c.expected)}`),
  ];

  writeFileSync(argument, lines.join("\n") + "\n");
  console.log(
    `Saved ${lines.length - 1} cases from ${intl}, seed ${SEED}, to ${argument}.`,
  );
  process.exit(0);
}

await Bun.$`gleam build --target erlang`.cwd(ROOT).quiet();

const erlang = Bun.spawn(
  [
    "sh",
    "-c",
    "erl -noshell -pa build/dev/erlang/*/ebin -eval 'glintl_conformance:main(), halt().'",
  ],
  { cwd: ROOT, stdin: "pipe", stdout: "pipe", stderr: "inherit" },
);

// Reads Erlang's answers a line at a time.
const reader = erlang.stdout.getReader();
const decoder = new TextDecoder();
const buffered = { text: "" };

async function readLine(): Promise<string> {
  const newline = buffered.text.indexOf("\n");

  if (newline >= 0) {
    const line = buffered.text.slice(0, newline);
    buffered.text = buffered.text.slice(newline + 1);

    return line;
  }

  const { value, done } = await reader.read();

  if (done) {
    throw new Error("Erlang stopped early");
  }

  buffered.text += decoder.decode(value, { stream: true });

  return readLine();
}

const started = performance.now();
const failures: string[] = [];
const failingCalendars = new Map<string, number>();

// Send one batch at a time and read its answers in order.
const sizes = await Array.fromAsync(batches(), async (batch) => {
  erlang.stdin.write(batch.map((c) => c.line).join("\n") + "\n");
  erlang.stdin.flush();

  const answers = await Array.fromAsync({ length: batch.length }, () =>
    readLine(),
  );

  batch.forEach((c, n) => {
    const actual = answers[n];

    if (actual !== c.expected) {
      const [tag, calendar] = c.line.split("\t");
      const key = `${tag} ${calendar || "(default)"}`;
      failingCalendars.set(key, (failingCalendars.get(key) ?? 0) + 1);

      if (failures.length < MOST_SHOWN) {
        failures.push(
          `${c.line.replaceAll("\t", " ")}: expected ${JSON.stringify(c.expected)}, got ${JSON.stringify(actual)}`,
        );
      }
    }
  });

  return batch.length;
});

const checked = sizes.reduce((a, b) => a + b, 0);

erlang.stdin.end();

await erlang.exited;

const seconds = ((performance.now() - started) / MS_PER_SECOND).toFixed(0);
const failed = [...failingCalendars.values()].reduce((a, b) => a + b, 0);

console.log(
  `Checked ${checked} cases against Intl.DateTimeFormat in ${intl}, in ${seconds}s: ${failed} differ.`,
);

failures.forEach((failure) => console.log("  " + failure));

[...failingCalendars]
  .slice(0, MOST_SHOWN)
  .forEach(([key, count]) => console.log(`  ${count} in ${key}`));

if (failed > 0) {
  process.exit(1);
}
