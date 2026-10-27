// Checks glintl on Erlang against Intl.DateTimeFormat on lots of random
// cases: locale, calendar, styles, moment and offset.
//
//   bun codegen/conformance.ts [cases] [seed]
//
// Intl's answers depend on the Bun that runs this. To use one Bun for Intl
// and Erlang from elsewhere, as when the pinned Bun is only in Docker, save
// the cases with one and check them with the other:
//
//   bun codegen/conformance.ts --save cases.tsv [cases] [seed]
//   bun codegen/conformance.ts --check cases.tsv
//
// Cases come in groups that share a formatter, as making an
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
import { HOUR_CYCLES } from "./patterns.ts";
import { LOCALES } from "./locales.ts";
import { random } from "./random.ts";
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

const [mode, file] =
  process.argv[2] === "--save" || process.argv[2] === "--check"
    ? [process.argv[2], process.argv[3]!]
    : ["--live", ""];

const counts =
  mode === "--live" ? process.argv.slice(2) : process.argv.slice(4);

const CASES = Number(counts[0] ?? 1_000_000);
const SEED = Number(counts[1] ?? 1);

// Cases per formatter, and cases sent to Erlang at a time.
const GROUP = 100;
const BATCH = 20_000;

// Styles, after "none".
const STYLES = [undefined, "full", "long", "medium", "short"] as const;

// How often moments are exactly midnight, exactly noon, or on the hour,
// where day periods change. The rest are at random.
const MIDNIGHT_SHARE = 0.1;
const NOON_SHARE = 0.1;
const WHOLE_HOUR_SHARE = 0.1;

// How many failures, and failing locales, to show.
const MOST_SHOWN = 20;
const OFFSETS = [0, 60, -480, 330, 345, -210, 840, -600, 525, -720, 765];

// Calendars with their own months cover these days on Erlang: a year in
// from each end, as a table's first and last years may not quite reach
// 1 January. Others have no limit, so they also get days far in the past.
const TABLE_DAYS: [number, number] = [
  day(FIRST_YEAR + 1, 1, 1),
  day(LAST_YEAR - 1, 1, 1),
];

const ALL_DAYS: [number, number] = [day(SCAN_FROM, 1, 1), TABLE_DAYS[1]];

const next = random(SEED);

const pick = <T>(items: readonly T[]): T =>
  items[Math.floor(next() * items.length)]!;

const between = ([from, to]: [number, number]) =>
  from + Math.floor(next() * (to - from));

type Case = { line: string; expected: string };

// ICU mixes up the era and year in table calendars when the local and UTC
// dates are in different eras, as glintl's README explains, so those
// moments are left out.
const eraFormatters = new Map<string, Intl.DateTimeFormat>();

function eraFormatter(calendar: string): Intl.DateTimeFormat {
  const f = new Intl.DateTimeFormat("en", {
    calendar,
    // Short names, as the Coptic eras share a long one in English.
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

  const kind = CALENDARS.find((c) => c.id === resolved)!.kind;
  // 0 for none, or a style. Something must be shown.
  const drawn = Math.floor(next() * STYLES.length);

  const time =
    drawn === 0
      ? 1 + Math.floor(next() * (STYLES.length - 1))
      : Math.floor(next() * STYLES.length);

  const date = drawn === 0 && time === 0 ? 1 : drawn;

  const offset = pick(OFFSETS);

  // Empty for the locale's own.
  const hourCycle = next() < 0.5 ? "" : pick(HOUR_CYCLES);

  const formatter = new Intl.DateTimeFormat(tag, {
    calendar: resolved,
    dateStyle: STYLES[date],
    timeStyle: STYLES[time],
    timeZone: offsetString(offset),
    hourCycle: hourCycle === "" ? undefined : hourCycle,
  });

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

    return [
      {
        line: [tag, calendar, date, time, hourCycle, seconds, offset].join(
          "\t",
        ),
        expected: formatter.format(seconds * MS_PER_SECOND),
      },
    ];
  });
}

// Batches of cases: made here, or read from a saved file with the Intl it
// was made with.
const [header, ...saved] =
  mode === "--check" ? readFileSync(file, "utf8").trimEnd().split("\n") : [];

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

  return made(0);
}

if (mode === "--save") {
  const lines = [
    intl,
    ...batches()
      .flatMap((batch) => batch)
      .map((c) => `${c.line}\t${JSON.stringify(c.expected)}`),
  ];

  writeFileSync(file, lines.join("\n") + "\n");
  console.log(
    `Saved ${lines.length - 1} cases from ${intl}, seed ${SEED}, to ${file}.`,
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

// One batch at a time, each answer read in order.
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
