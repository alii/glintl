// Works out each locale's patterns from Bun's ICU with formatToParts.
//
//   bun install --cwd codegen
//   bun codegen/generate.ts
//
// Reading every locale in every calendar is slow, so the work is shared
// between one Bun process per CPU. Each writes its locales to
// `codegen/.cache/`, and the main process writes the files.

import { $ } from "bun";
import { mkdirSync, readFileSync, rmSync } from "node:fs";
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
for (const id of icuCalendars) {
  if (!CALENDARS.some((c) => c.id === id)) {
    throw new Error(`ICU has a new calendar: ${id}`);
  }
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
function mathFor(id: CalendarId): Math_ {
  let math = maths.get(id);
  if (!math) {
    math = JSON.parse(readFileSync(mathPath(id), "utf8"), (_, v) =>
      v === "-Infinity" ? -Infinity : v,
    ) as Math_;
    maths.set(id, math);
  }
  return math;
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
  const id = process.argv[mathArgument + 1] as CalendarId;
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
  const [index, count] = process.argv[shardArgument + 1]!.split("/").map(
    Number,
  ) as [number, number];
  const results = LOCALES.filter((_, n) => n % count === index).map(([, tag]) =>
    readLocale(tag),
  );
  await Bun.write(join(CACHE, `${index}.json`), JSON.stringify(results));
  process.exit(0);
}

rmSync(CACHE, { recursive: true, force: true });
mkdirSync(CACHE, { recursive: true });
const spawn = (args: string[]) =>
  Bun.spawn(["bun", import.meta.path, ...args], {
    stdout: "inherit",
    stderr: "inherit",
  }).exited;

console.log(`Working out ${CALENDARS.length} calendars...`);
const mathExits = await Promise.all(
  CALENDARS.map(({ id }) => spawn(["--math", id])),
);
if (mathExits.some((code) => code !== 0)) {
  throw new Error("A calendar failed");
}

// Gregorian's maths is written by hand in `data.gleam`, so Gregorian
// formatters load nothing extra. It must still match ICU.
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

const workers = availableParallelism();
console.log(`Reading ${LOCALES.length} locales in ${workers} processes...`);
const exits = await Promise.all(
  Array.from({ length: workers }, (_, i) =>
    spawn(["--shard", `${i}/${workers}`]),
  ),
);
if (exits.some((code) => code !== 0)) {
  throw new Error("A worker failed");
}
const byTag = new Map<string, LocaleData>();
for (let i = 0; i < workers; i++) {
  for (const data of (await Bun.file(
    join(CACHE, `${i}.json`),
  ).json()) as LocaleData[]) {
    byTag.set(data.tag, data);
  }
}
// --- Erlang -------------------------------------------------------------------

const ERLANG = "src/glintl/internal/generated/erlang";
const JAVASCRIPT = "src/glintl/internal/generated/javascript";

for (const dir of ["src/glintl/locale", "src/glintl/internal/generated"]) {
  rmSync(join(ROOT, dir), { recursive: true, force: true });
}

async function write(path: string, contents: string): Promise<void> {
  await Bun.write(join(ROOT, path), contents);
}

const header = (what: string) =>
  `%% Generated by codegen/generate.ts with ${RUNTIME}.\n%% Do not edit. ${what}`;

// Locales with the same data, like many regional variants and their
// language, share one module named after the first of them.
type Shared = { name: string; tags: string[] };
const bases = new Map<string, Shared>();
const calendarSets = new Map<string, Shared>();
const modules = new Map<string, { base: string; calendars: string }>();
for (const [name, tag] of LOCALES) {
  const data = byTag.get(tag)!;
  const base = new erlang.Writer();
  const baseBody = base.body(
    `{data, ${base.digits(data.digits)}, ${base.formats(data.formats[0]!)}}`,
  );
  const others = new erlang.Writer();
  const othersBody = others.body(
    // A record with a field for each calendar but Gregorian, in order.
    `{calendars,\n    ${data.formats
      .slice(1)
      .map((f) => others.formats(f))
      .join(",\n    ")}}`,
  );
  const baseShared = bases.get(baseBody) ?? { name, tags: [] };
  bases.set(baseBody, baseShared);
  baseShared.tags.push(tag);
  const calendarsShared = calendarSets.get(othersBody) ?? { name, tags: [] };
  calendarSets.set(othersBody, calendarsShared);
  calendarsShared.tags.push(tag);
  modules.set(tag, { base: baseShared.name, calendars: calendarsShared.name });
}

for (const [body, { name, tags }] of bases) {
  await write(
    `${ERLANG}/glintl_generated_${name}.erl`,
    erlang.module(
      `glintl_generated_${name}`,
      header(`Locales: ${tags.join(", ")}`),
      [["data", body]],
    ),
  );
  await write(`${JAVASCRIPT}/${name}.mjs`, jsModule(tags));
}
for (const [body, { name, tags }] of calendarSets) {
  await write(
    `${ERLANG}/glintl_generated_calendars_${name}.erl`,
    erlang.module(
      `glintl_generated_calendars_${name}`,
      header(`Every calendar but Gregorian. Locales: ${tags.join(", ")}`),
      [["data", body]],
    ),
  );
}
for (const { id } of CALENDARS.slice(1)) {
  const name = `glintl_generated_calendar_${id.replaceAll("-", "_")}`;
  await write(
    `${ERLANG}/${name}.erl`,
    erlang.module(name, header(`How the ${id} calendar maps days to dates.`), [
      ["math", erlang.math(mathFor(id))],
    ]),
  );
}

function jsModule(tags: string[]): string {
  return `// Generated by codegen/generate.ts. Do not edit. Locales: ${tags.join(", ")}
import { NoCalendars, NoData } from "../../data.mjs";

export function data() {
  return new NoData();
}

export function calendars() {
  return new NoCalendars();
}
`;
}

// --- Gleam --------------------------------------------------------------------

function displayName(tag: string): string | undefined {
  return new Intl.DisplayNames("en-GB", { type: "language" }).of(tag);
}

function gleamCalendar(id: string): string {
  return CALENDARS.find((c) => c.id === id)!.gleam;
}

function gleamLocaleModule(tag: string): string {
  const { base, calendars } = modules.get(tag)!;
  const calendar = gleamCalendar(byTag.get(tag)!.calendar);
  return `//// ${displayName(tag)}, \`${tag}\`.
////
//// Generated by \`codegen/generate.ts\`. Do not edit.

import glintl.{type Locale}
import glintl/internal/data.{type Calendars, type Data}

/// ${displayName(tag)}, \`${tag}\`.
pub fn locale() -> Locale {
  glintl.new_locale("${tag}", glintl.${calendar}, data(), calendars)
}

@external(erlang, "glintl_generated_${base}", "data")
@external(javascript, "../internal/generated/javascript/${base}.mjs", "data")
fn data() -> Data

@external(erlang, "glintl_generated_calendars_${calendars}", "data")
@external(javascript, "../internal/generated/javascript/${base}.mjs", "calendars")
fn calendars() -> Calendars
`;
}

// Language and region tags, like "zh-TW", for locales whose tag has a
// script instead, like "zh-Hant", so they aren't mistaken for their
// language's default.
function aliases(): Map<string, string> {
  const known = new Set(LOCALES.map(([, tag]) => tag.toLowerCase()));
  const found = new Map<string, string>();
  for (const [name, tag] of LOCALES) {
    const full = new Intl.Locale(tag).maximize();
    const short = `${full.language}-${full.region}`.toLowerCase();
    if (known.has(short) || found.has(short)) {
      continue;
    }
    if (new Intl.Locale(short).maximize().toString() === full.toString()) {
      found.set(short, name);
    }
  }
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
//// This module refers to every locale, which has a cost:
////
//// - On JavaScript, bundlers can't leave out the locales you don't use, so
////   your bundle grows by about 13 KB gzipped. It's not more because each
////   locale is just its tag: the formats come from the runtime's \`Intl\`.
//// - On Erlang, \`from_tag\` loads this module and the data for the locale it
////   finds, about 0.5 MB. \`all\` loads every locale's data, about 11 MB: see
////   its documentation before using it.
////
//// If you know which locales you need, import them from \`glintl/locale/\`
//// instead.
////
//// Generated by \`codegen/generate.ts\`. Do not edit.

import gleam/list
import gleam/string
import glintl.{type Locale}
${imports}

/// Every locale glintl has.
///
/// On JavaScript this is cheap, as each locale is just its tag.
///
/// On Erlang it's expensive:
///
/// - It loads every locale's data: about 350 modules and 11 MB of memory.
///   The BEAM doesn't unload modules by itself, so that memory stays in use
///   until the app stops.
/// - The first call takes about 0.3 seconds while the modules load. In a
///   request handler, that's one very slow request.
/// - Each call builds a new list of every locale, so searching it on every
///   request allocates every time.
///
/// To find one locale, use \`from_tag\`, which only loads that locale's data.
/// Use \`all\` when you really need every locale, such as in a test that
/// checks them all.
///
/// Other calendars' data is only loaded when a formatter uses it, so \`all\`
/// doesn't load it.
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
    Error(_) ->
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

for (const [name, tag] of LOCALES) {
  await write(`src/glintl/locale/${name}.gleam`, gleamLocaleModule(tag));
}
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
rmSync(CACHE, { recursive: true, force: true });
// Gleam isn't in the Bun Docker image, so formatting can be left for later.
if (Bun.which("gleam")) {
  await $`gleam format src test`.cwd(ROOT);
} else {
  console.log("Gleam isn't installed: run `gleam format src test` next.");
}
console.log(
  `Generated ${LOCALES.length} locales (${bases.size} Gregorian and ${calendarSets.size} calendar data modules) with ${RUNTIME}.`,
);
