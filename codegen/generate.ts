// Works out each locale's patterns from Bun's ICU with formatToParts.
//
//   bun install --cwd codegen
//   bun codegen/generate.ts
//
// Reading every locale in every calendar is slow, so the work is shared
// between one Bun process per CPU. Each writes its locales to
// `codegen/.cache/`, and the main process writes the files.

import { $ } from "bun";
import { mkdirSync, readFileSync, readdirSync, rmSync } from "node:fs";
import { availableParallelism } from "node:os";
import { join } from "node:path";
import {
  CALENDARS,
  type CalendarId,
  FIRST_DAY,
  type Math_,
  calendarMath,
  checkEveryDay,
} from "./calendars.ts";
import * as erlang from "./erlang.ts";
import { packer } from "./pack.ts";
import { calendarFixtures, fixtures } from "./fixtures.ts";
import { LOCALES } from "./locales.ts";
import {
  type Formats,
  defaultCalendar,
  formats,
  localDigits,
} from "./patterns.ts";

const ROOT = join(import.meta.dir, "..");
const CACHE = join(import.meta.dir, ".cache");
const RUNTIME = `Bun ${Bun.version}, ICU ${process.versions.icu}`;

// Every calendar ICU has must be one glintl knows, or the Gleam `Calendar`
// type is out of date.
const icuCalendars = Intl.supportedValuesOf("calendar");

const newCalendar = icuCalendars.find(
  (id) => !CALENDARS.some((c) => c.id === id),
);

if (newCalendar) {
  throw new Error(`ICU has a new calendar: ${newCalendar}`);
}

type LocaleData = {
  tag: string;
  calendar: string;
  digits: string[];
  formats: Formats[];
};

// Each calendar's maths is worked out and checked once, by its own process,
// and shared through the cache. JSON has no -Infinity, so it's a string.
const mathPath = (id: CalendarId) => join(CACHE, `math-${id}.json`);
const maths = new Map<CalendarId, Math_>();

function readMath(id: CalendarId): Math_ {
  const math: Math_ = JSON.parse(readFileSync(mathPath(id), "utf8"), (_, v) =>
    v === "-Infinity" ? -Infinity : v,
  );

  maths.set(id, math);

  return math;
}

function mathFor(id: CalendarId): Math_ {
  return maths.get(id) ?? readMath(id);
}

function readLocale(tag: string): LocaleData {
  const digits = localDigits(tag);

  return {
    tag,
    calendar: defaultCalendar(tag),
    digits,
    formats: CALENDARS.map(({ id }) => formats(tag, id, mathFor(id), digits)),
  };
}

// --- Workers ------------------------------------------------------------------

const mathArgument = process.argv.indexOf("--math");

if (mathArgument >= 0) {
  const wanted = process.argv[mathArgument + 1];
  const calendar = CALENDARS.find((c) => c.id === wanted);

  if (calendar === undefined) {
    throw new Error(`Unknown calendar: ${wanted}`);
  }

  const { id } = calendar;
  const math = calendarMath(id);
  const days = checkEveryDay(id, math);
  await Bun.write(
    mathPath(id),
    JSON.stringify(math, (_, v) => (v === -Infinity ? "-Infinity" : v)),
  );
  console.log(`Checked ${id} against ICU on ${days} days.`);
  process.exit(0);
}

const shardArgument = process.argv.indexOf("--shard");

if (shardArgument >= 0) {
  const shard = process.argv[shardArgument + 1];
  const [index, count] = shard?.split("/").map(Number) ?? [];

  if (index === undefined || count === undefined) {
    throw new Error(`Bad shard: ${shard}`);
  }

  const results = LOCALES.filter((_, n) => n % count === index).map(([, tag]) =>
    readLocale(tag),
  );

  await Bun.write(join(CACHE, `${index}.json`), JSON.stringify(results));
  process.exit(0);
}

// Writes the files again from the last run's ICU data, which `--keep-cache`
// keeps, for working on the output.
const reuse = process.argv.includes("--reuse-cache");
const keep = reuse || process.argv.includes("--keep-cache");

if (!reuse) {
  rmSync(CACHE, { recursive: true, force: true });
  mkdirSync(CACHE, { recursive: true });
}

const spawn = (args: string[]) =>
  Bun.spawn(["bun", import.meta.path, ...args], {
    stdout: "inherit",
    stderr: "inherit",
  }).exited;

console.log(`Working out ${CALENDARS.length} calendars...`);

const mathExits = reuse
  ? []
  : await Promise.all(CALENDARS.map(({ id }) => spawn(["--math", id])));

if (mathExits.some((code) => code !== 0)) {
  throw new Error("A calendar failed");
}

// Gregorian's maths is written by hand in `data.gleam`, so check it.
const gregorianMath = mathFor("gregory");

const gregorian = JSON.stringify(
  gregorianMath.kind === "proleptic" && [
    gregorianMath.eras,
    gregorianMath.julianBefore,
  ],
);

const expected = JSON.stringify([
  [
    { start: FIRST_DAY, era: 0, base: 0, sign: 1 },
    { start: -Infinity, era: 1, base: 1, sign: -1 },
  ],
  -Infinity,
]);

if (gregorian !== expected) {
  throw new Error(
    `Update \`gregorian\` in data.gleam: ICU now says ${gregorian}`,
  );
}

const SHARD = /^\d+\.json$/;

const workers = reuse
  ? readdirSync(CACHE).filter((f) => SHARD.test(f)).length
  : availableParallelism();

console.log(`Reading ${LOCALES.length} locales in ${workers} processes...`);

const exits = reuse
  ? []
  : await Promise.all(
      Array.from({ length: workers }, (_, i) =>
        spawn(["--shard", `${i}/${workers}`]),
      ),
    );

if (exits.some((code) => code !== 0)) {
  throw new Error("A worker failed");
}

const shards = await Promise.all(
  Array.from({ length: workers }, (_, i): Promise<LocaleData[]> =>
    Bun.file(join(CACHE, `${i}.json`)).json(),
  ),
);

const byTag = new Map(shards.flat().map((data) => [data.tag, data]));

// --- Erlang -------------------------------------------------------------------

const ERLANG = "src/glintl/internal/generated/erlang";

["src/glintl/locale", "src/glintl/internal/generated"].forEach((dir) =>
  rmSync(join(ROOT, dir), { recursive: true, force: true }),
);

async function write(path: string, contents: string): Promise<void> {
  await Bun.write(join(ROOT, path), contents);
}

const header = (what: string) =>
  `%% Generated by codegen/generate.ts with ${RUNTIME}.\n%% Do not edit. ${what}`;

const packed = packer();

const localeNumbers = new Map(
  LOCALES.map(([, tag]) => {
    const data = byTag.get(tag)!;

    return [tag, packed.locale(data.digits, data.formats)];
  }),
);

const tables = packed.tables();

const DATA_TABLES = [
  "tokens",
  "patterns",
  "formats",
  "digits",
  "locales",
] as const;

await write(
  `${ERLANG}/glintl_generated_data.erl`,
  erlang.module(
    "glintl_generated_data",
    header("Every locale's data, packed by codegen/pack.ts."),
    DATA_TABLES.map((name) => `${name}/0`),
    DATA_TABLES.map((name) => [
      `${name}() ->\n    ${erlang.tuple(tables[name])}`,
    ]),
  ),
);

await Promise.all(
  CALENDARS.slice(1).map(({ id }) => {
    const name = `glintl_generated_calendar_${id.replaceAll("-", "_")}`;

    return write(
      `${ERLANG}/${name}.erl`,
      erlang.module(
        name,
        header(`How the ${id} calendar maps days to dates.`),
        ["math/0"],
        [[`math() ->\n${erlang.math(mathFor(id))}`]],
      ),
    );
  }),
);

// --- Gleam --------------------------------------------------------------------

function displayName(tag: string): string | undefined {
  return new Intl.DisplayNames("en-GB", { type: "language" }).of(tag);
}

function gleamCalendar(id: string): string {
  return CALENDARS.find((c) => c.id === id)!.gleam;
}

function gleamLocaleModule(tag: string): string {
  const calendar = gleamCalendar(byTag.get(tag)!.calendar);

  return `//// ${displayName(tag)}, \`${tag}\`.
////
//// Generated by \`codegen/generate.ts\`. Do not edit.

import glintl.{type Locale}

/// ${displayName(tag)}, \`${tag}\`.
pub fn locale() -> Locale {
  glintl.new_locale("${tag}", glintl.${calendar}, ${localeNumbers.get(tag)!})
}
`;
}

// Language and region tags, like "zh-TW", for locales whose tag has a
// script instead, like "zh-Hant", so they aren't mistaken for their
// language's default.
function aliases(): Map<string, string> {
  const known = new Set(LOCALES.map(([, tag]) => tag.toLowerCase()));
  const found = new Map<string, string>();

  LOCALES.forEach(([name, tag]) => {
    const full = new Intl.Locale(tag).maximize();
    const short = `${full.language}-${full.region}`.toLowerCase();

    if (known.has(short) || found.has(short)) {
      return;
    }

    if (new Intl.Locale(short).maximize().toString() === full.toString()) {
      found.set(short, name);
    }
  });

  return found;
}

function gleamLocalesModule(): string {
  const imports = LOCALES.map(([name]) => `import glintl/locale/${name}`).join(
    "\n",
  );

  const cases = [
    ...LOCALES.map(([name, tag]) => [tag.toLowerCase(), name]),
    ...aliases(),
  ]
    .map(([tag, name]) => `    "${tag}" -> Ok(${name}.locale())`)
    .join("\n");

  const list = LOCALES.map(([name]) => `${name}.locale()`).join(", ");

  return `//// Pick a locale from a tag such as \`"en-GB"\`, for example from an
//// \`Accept-Language\` header or the browser's language.
////
//// This module refers to every locale. If you know which you need, import
//// them from \`glintl/locale/\` instead.
////
//// Generated by \`codegen/generate.ts\`. Do not edit.

import gleam/list
import gleam/string
import glintl.{type Locale}
${imports}

pub fn all() -> List(Locale) {
  [${list}]
}

/// Find a locale by its BCP 47 tag. Case and \`_\` or \`-\` don't matter.
///
/// If there is no exact match, the last part of the tag is dropped and it
/// tries again, so \`"fr-CA-x-mine"\` gives Canadian French and \`"en-XX"\`
/// gives English.
///
/// \`\`\`gleam
/// from_tag("en_GB")  // -> Ok(en_gb.locale())
/// from_tag("zh-TW")  // -> Ok(zh_hant.locale())
/// from_tag("xx")     // -> Error(Nil)
/// \`\`\`
pub fn from_tag(tag: String) -> Result(Locale, Nil) {
  tag |> string.lowercase |> string.replace("_", "-") |> find
}

fn find(tag: String) -> Result(Locale, Nil) {
  case exact(tag) {
    Ok(locale) -> Ok(locale)
    Error(Nil) ->
      case string.split(tag, "-") |> list.reverse {
        [_, _, ..] as parts ->
          parts |> list.drop(1) |> list.reverse |> string.join("-") |> find
        _ -> Error(Nil)
      }
  }
}

fn exact(tag: String) -> Result(Locale, Nil) {
  case tag {
${cases}
    _ -> Error(Nil)
  }
}
`;
}

await Promise.all(
  LOCALES.map(([name, tag]) =>
    write(`src/glintl/locale/${name}.gleam`, gleamLocaleModule(tag)),
  ),
);

await write("src/glintl/locales.gleam", gleamLocalesModule());

await write(
  "test/glintl/fixtures.gleam",
  fixtures(
    LOCALES.map(([, tag]) => [tag, byTag.get(tag)!.calendar]),
    mathFor,
    RUNTIME,
  ),
);

await write(
  "test/glintl/calendar_fixtures.gleam",
  calendarFixtures(mathFor, RUNTIME),
);

if (!keep) {
  rmSync(CACHE, { recursive: true, force: true });
}

// Gleam isn't in the Bun Docker image, so formatting can be left for later.
if (Bun.which("gleam")) {
  await $`gleam format src test`.cwd(ROOT);
} else {
  console.log("Gleam isn't installed: run `gleam format src test` next.");
}

console.log(
  `Generated ${LOCALES.length} locales (${tables.locales.length} distinct, ${tables.patterns.length} patterns of ${tables.tokens.length} tokens) with ${RUNTIME}.`,
);
