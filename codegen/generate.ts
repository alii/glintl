// Works out each locale's patterns from Bun's ICU with formatToParts.
//
//   bun install --cwd codegen
//   bun codegen/generate.ts

import { $ } from "bun";
import { rmSync } from "node:fs";
import { join } from "node:path";
import cldr from "cldr-core/availableLocales.json" with { type: "json" };

const ROOT = join(import.meta.dir, "..");
const RUNTIME = `Bun ${Bun.version}, ICU ${process.versions.icu}`;

// Mirrors `src/glintl/internal/data.gleam`.
type Token =
  | { t: "literal"; value: string }
  | { t: "year"; twoDigit: boolean }
  | { t: "month_number" | "day" | "minute" | "second"; pad: boolean }
  | { t: "month_name" | "weekday"; names: string[] }
  | { t: "hour"; pad: boolean; cycle: "h11" | "h12" | "h23" | "h24" }
  | { t: "day_period"; byHour: string[]; midnight: string; noon: string }
  | { t: "era"; bc: string; ad: string }
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

// Date style and time style, each 0 for none or an index into STYLES.
type Pair = [number, number];
type Pattern = [Pair, Token[]];
type Local = (n: number, pad: boolean) => string;

const RESERVED = new Set(
  "as assert auto case const delegate derive echo else fn if implement import let macro opaque panic pub test todo type use".split(
    " ",
  ),
);

function moduleName(tag: string): string {
  const name = tag.toLowerCase().replaceAll("-", "_");
  return RESERVED.has(name) ? name + "_" : name;
}

// JavaScript can't list the locales it has, so we ask it about each of
// CLDR's. Those it has no data for fall back to another language, which we
// can't tell apart from a real locale, so they are left out.
const LOCALES = cldr.availableLocales.full
  .filter((tag) => tag !== "und")
  .filter((tag) => {
    const resolved = new Intl.DateTimeFormat(tag).resolvedOptions().locale;
    return resolved.split("-")[0] === tag.split("-")[0];
  })
  .map((tag): [string, string] => [moduleName(tag), tag]);

const STYLES = [undefined, "full", "long", "medium", "short"] as const;

// Every date and time style pair, in the order the Gleam code expects.
const PAIRS: Pair[] = [];
for (let d = 0; d < 5; d++)
  for (let t = 0; t < 5; t++) if (d || t) PAIRS.push([d, t]);

function formatter(tag: string, [d, t]: Pair, timeZone = "+00:00") {
  const options: Intl.DateTimeFormatOptions = { calendar: "gregory", timeZone };
  if (d) options.dateStyle = STYLES[d];
  if (t) options.timeStyle = STYLES[t];
  return new Intl.DateTimeFormat(tag, options);
}

function utc(
  year: number,
  month: number,
  day: number,
  hour = 9,
  minute = 7,
  second = 4,
): Date {
  const date = new Date(0);
  date.setUTCFullYear(year, month - 1, day);
  date.setUTCHours(hour, minute, second, 0);
  return date;
}

const PROBE = utc(2026, 3, 5);

function localDigits(tag: string): string[] {
  const { numberingSystem } = new Intl.DateTimeFormat(tag, {
    calendar: "gregory",
  }).resolvedOptions();
  const nf = new Intl.NumberFormat(tag, {
    numberingSystem,
    useGrouping: false,
  });
  return Array.from({ length: 10 }, (_, i) => nf.format(i));
}

function derivePattern(tag: string, pair: Pair, digits: string[]): Token[] {
  const f = formatter(tag, pair);
  const probe = f.formatToParts(PROBE);
  const shape = (parts: Intl.DateTimeFormatPart[]) =>
    parts.map((p) => p.type).join(",");
  const valueAt = (date: Date, i: number, fmt = f) => {
    const parts = fmt.formatToParts(date);
    if (shape(parts) !== shape(probe))
      throw new Error(`${tag} ${pair}: parts change with the date`);
    return parts[i]!.value;
  };
  const toAscii = (s: string) =>
    [...s]
      .map((c) => (digits.includes(c) ? String(digits.indexOf(c)) : c))
      .join("");
  const local: Local = (n, pad) =>
    [...String(n).padStart(pad ? 2 : 1, "0")].map((c) => digits[+c]).join("");
  const numeric = (s: string) => /^\d+$/.test(toAscii(s));
  const padded = (value: string, n: number) => {
    if (value === local(n, true) && n < 10) return true;
    if (value === local(n, false)) return false;
    throw new Error(`${tag} ${pair}: can't read number ${value}`);
  };

  return probe.map((part, i): Token => {
    const { type, value } = part;
    switch (type) {
      case "literal":
        return { t: "literal", value };
      case "year":
        if (value === local(26, true)) return { t: "year", twoDigit: true };
        if (value === local(2026, false)) return { t: "year", twoDigit: false };
        throw new Error(`${tag} ${pair}: odd year ${value}`);
      case "month":
        if (numeric(value)) return { t: "month_number", pad: padded(value, 3) };
        return {
          t: "month_name",
          names: Array.from({ length: 12 }, (_, m) =>
            valueAt(utc(2026, m + 1, 5), i),
          ),
        };
      case "day":
        return { t: "day", pad: padded(value, 5) };
      case "weekday":
        // 2026-03-01 was a Sunday.
        return {
          t: "weekday",
          names: Array.from({ length: 7 }, (_, d) =>
            valueAt(utc(2026, 3, 1 + d), i),
          ),
        };
      case "hour": {
        const at = (h: number) => +toAscii(valueAt(utc(2026, 3, 5, h), i));
        const cycle: "h11" | "h12" | "h23" | "h24" =
          at(0) === 12
            ? "h12"
            : at(0) === 24
              ? "h24"
              : at(12) === 0
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
            valueAt(utc(2026, 3, 5, h), i),
          ),
          midnight: valueAt(utc(2026, 3, 5, 0, 0, 0), i),
          noon: valueAt(utc(2026, 3, 5, 12, 0, 0), i),
        };
      case "era":
        return { t: "era", bc: valueAt(utc(-100, 3, 5), i), ad: value };
      case "timeZoneName":
        return deriveZone(tag, pair, i, local);
      default:
        throw new Error(`${tag} ${pair}: unsupported part ${type}`);
    }
  });
}

function deriveZone(tag: string, pair: Pair, i: number, local: Local): Token {
  const zone = (tz: string) =>
    formatter(tag, pair, tz).formatToParts(PROBE)[i]!.value;
  const zero = zone("+00:00");
  const full = zone("+11:47");
  const h11 = local(11, false);
  const m47 = local(47, true);
  const hAt = full.indexOf(h11);
  const mAt = full.indexOf(m47, hAt + h11.length);
  if (hAt < 0 || mAt < 0) throw new Error(`${tag} ${pair}: odd zone ${full}`);
  const positive = full.slice(0, hAt);
  const separator = full.slice(hAt + h11.length, mAt);
  const suffix = full.slice(mAt + m47.length);

  const negativeFull = zone("-11:47");
  const negative = negativeFull.slice(0, negativeFull.indexOf(h11));
  const negativeSuffix = negativeFull.slice(
    negative.length + h11.length + separator.length + m47.length,
  );
  if (negativeFull !== negative + h11 + separator + m47 + negativeSuffix)
    throw new Error(`${tag} ${pair}: odd negative zone ${negativeFull}`);

  // With minutes left out, some locales also change the suffix.
  const whole = zone("+11:00");
  const negativeWhole = zone("-11:00");
  const optionalMinutes = !whole.includes(separator + local(0, true));
  const wholeSuffix = (text: string, prefix: string) => {
    const minutes = optionalMinutes ? "" : separator + local(0, true);
    if (!text.startsWith(prefix + h11 + minutes))
      throw new Error(`${tag} ${pair}: odd whole hour zone ${text}`);
    return text.slice((prefix + h11 + minutes).length);
  };
  const positiveWholeSuffix = wholeSuffix(whole, positive);
  const negativeWholeSuffix = wholeSuffix(negativeWhole, negative);

  const one = zone("+01:47");
  const padHours = one.startsWith(positive + local(1, true));

  return {
    t: "zone",
    zero,
    positive,
    positiveSuffix: suffix,
    positiveWholeSuffix,
    negative,
    negativeSuffix,
    negativeWholeSuffix,
    padHours,
    separator,
    optionalMinutes,
  };
}

const INVISIBLE = /[\p{Cc}\p{Cf}\p{Z}]/u;

function escape(s: string, hex: (code: string) => string): string {
  return [...s]
    .map((c) => {
      if (c === "\\") return "\\\\";
      if (c === '"') return '\\"';
      if (c === " ") return c;
      if (INVISIBLE.test(c))
        return hex(c.codePointAt(0)!.toString(16).toUpperCase());
      return c;
    })
    .join("");
}

const erlString = (s: string) => `<<"${escape(s, (h) => `\\x{${h}}`)}"/utf8>>`;
const erlBool = (b: boolean) => (b ? "true" : "false");
const erlList = (items: string[], f: (item: string) => string) =>
  `[${items.map(f).join(", ")}]`;

function erlToken(token: Token, names: Map<string, string>): string {
  const list = (items: string[]) =>
    names.get(items.join("\0")) ?? erlList(items, erlString);
  switch (token.t) {
    case "literal":
      return `{literal, ${erlString(token.value)}}`;
    case "year":
      return `{year, ${erlBool(token.twoDigit)}}`;
    case "month_number":
    case "day":
    case "minute":
    case "second":
      return `{${token.t}, ${erlBool(token.pad)}}`;
    case "month_name":
    case "weekday":
      return `{${token.t}, ${list(token.names)}}`;
    case "hour":
      return `{hour, ${erlBool(token.pad)}, ${token.cycle}}`;
    case "day_period":
      return `{day_period, ${list(token.byHour)}, ${erlString(
        token.midnight,
      )}, ${erlString(token.noon)}}`;
    case "era":
      return `{era, ${erlString(token.bc)}, ${erlString(token.ad)}}`;
    case "zone":
      return `{zone, ${[
        erlString(token.zero),
        erlString(token.positive),
        erlString(token.positiveSuffix),
        erlString(token.positiveWholeSuffix),
        erlString(token.negative),
        erlString(token.negativeSuffix),
        erlString(token.negativeWholeSuffix),
        erlBool(token.padHours),
        erlString(token.separator),
        erlBool(token.optionalMinutes),
      ].join(", ")}}`;
  }
}

// The body of a data module. Lists of names used more than once are bound
// to a variable, to keep the files small. The compiler folds it all back
// into one literal.
function erlBody(digits: string[], patterns: Pattern[]): string {
  const counts = new Map<string, number>();
  for (const [, tokens] of patterns)
    for (const token of tokens)
      for (const items of [
        "names" in token ? token.names : undefined,
        "byHour" in token ? token.byHour : undefined,
      ])
        if (items) {
          const key = items.join("\0");
          counts.set(key, (counts.get(key) ?? 0) + 1);
        }
  const names = new Map<string, string>();
  const bindings: string[] = [];
  for (const [key, count] of counts)
    if (count > 1) {
      const variable = `Names${names.size + 1}`;
      names.set(key, variable);
      bindings.push(
        `    ${variable} = ${erlList(key.split("\0"), erlString)},\n`,
      );
    }
  const digitsTerm =
    digits.join("") === "0123456789"
      ? "ascii"
      : `{digits, ${erlList(digits, erlString)}}`;
  const patternLines = patterns.map(
    ([[d, t], tokens], i) =>
      `        %% date: ${STYLES[d] ?? "none"}, time: ${STYLES[t] ?? "none"}\n` +
      `        [${tokens.map((token) => erlToken(token, names)).join(",\n         ")}]` +
      (i === patterns.length - 1 ? "" : ","),
  );
  return `data() ->
${bindings.join("")}    {data,
     ${digitsTerm},
     [
${patternLines.join("\n")}
     ]}.
`;
}

function erlModule(name: string, tags: string[], body: string): string {
  return `%% Generated by codegen/generate.ts with ${RUNTIME}.
%% Do not edit. Locales: ${tags.join(", ")}
-module(${name}).
-export([data/0]).

${body}`;
}

function jsModule(tags: string[]): string {
  return `// Generated by codegen/generate.ts. Do not edit. Locales: ${tags.join(", ")}
import { NoData } from "../../data.mjs";

export function data() {
  return new NoData();
}
`;
}

const gleamString = (s: string) => `"${escape(s, (h) => `\\u{${h}}`)}"`;

function displayName(tag: string): string | undefined {
  return new Intl.DisplayNames("en-GB", { type: "language" }).of(tag);
}

function gleamLocaleModule(tag: string, dataName: string): string {
  return `//// ${displayName(tag)}, \`${tag}\`.
////
//// Generated by \`codegen/generate.ts\`. Do not edit.

import glintl.{type Locale}
import glintl/internal/data.{type Data}

/// ${displayName(tag)}, \`${tag}\`.
pub fn locale() -> Locale {
  glintl.new_locale("${tag}", data())
}

@external(erlang, "glintl_generated_${dataName}", "data")
@external(javascript, "../internal/generated/javascript/${dataName}.mjs", "data")
fn data() -> Data
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
    if (known.has(short) || found.has(short)) continue;
    if (new Intl.Locale(short).maximize().toString() === full.toString())
      found.set(short, name);
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
//// - On Erlang, \`from_tag\` loads this module, about 0.4 MB, and the data
////   for the one locale it finds. \`all\` loads every locale's data, about
////   2.3 MB more.
////
//// If you know which locales you need, import them from \`glintl/locale/\`
//// instead.
////
//// Generated by \`codegen/generate.ts\`. Do not edit.

import gleam/list
import gleam/string
import glintl.{type Locale}
${imports}

/// Every locale glintl has. On Erlang this loads all their data.
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

// Seeded, so the fixtures only change when ICU does.
function random(seed: number): () => number {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const OFFSETS = [0, 60, -480, 330, 345, -210, 840, -600, 525];

function fixtureMoments() {
  const next = random(42);
  const moments: [Date, number][] = [
    [utc(2026, 3, 5, 0, 0, 0), 0],
    [utc(2026, 3, 5, 12, 0, 0), 0],
    [utc(2026, 3, 5, 12, 30, 0), 0],
    [utc(2026, 12, 31, 23, 59, 59), 60],
    [utc(5, 7, 1, 8, 0, 0), -480],
    [utc(-100, 3, 5, 15, 0, 0), 330],
    [utc(1999, 12, 31, 23, 0, 0), 60],
  ];
  for (let i = 0; i < 8; i++) {
    const year = 1 + Math.floor(next() * 2400);
    const date = utc(year, 1, 1, 0, 0, 0);
    date.setTime(date.getTime() + Math.floor(next() * 366 * 86400) * 1000);
    moments.push([date, OFFSETS[Math.floor(next() * OFFSETS.length)]!]);
  }
  return moments;
}

function offsetString(minutes: number): string {
  const sign = minutes < 0 ? "-" : "+";
  const abs = Math.abs(minutes);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${sign}${pad(Math.floor(abs / 60))}:${pad(abs % 60)}`;
}

function fixtures(): string {
  const moments = fixtureMoments();
  const lines: string[] = [];
  // Two moments for each locale and style pair, taking turns, so every
  // moment is checked often without the file getting huge.
  let turn = 0;
  for (const [, tag] of LOCALES)
    for (const pair of PAIRS)
      for (const [date, offset] of [0, 1].map(
        () => moments[turn++ % moments.length]!,
      )) {
        const expected = formatter(tag, pair, offsetString(offset)).format(
          date,
        );
        const seconds = date.getTime() / 1000;
        lines.push(
          `    #("${tag}", ${pair[0]}, ${pair[1]}, ${seconds}, ${offset}, ${gleamString(
            expected,
          )}),`,
        );
      }
  return `//// Expected output, made with \`Intl.DateTimeFormat\` in ${RUNTIME}.
//// Generated by \`codegen/generate.ts\`. Do not edit.

/// Locale tag, date style, time style, Unix seconds, offset minutes, output.
/// Styles are 0 for none, then full, long, medium, short.
pub fn cases() -> List(#(String, Int, Int, Int, Int, String)) {
  [
${lines.join("\n")}
  ]
}
`;
}

async function write(path: string, contents: string): Promise<void> {
  await Bun.write(join(ROOT, path), contents);
}

for (const dir of ["src/glintl/locale", "src/glintl/internal/generated"])
  rmSync(join(ROOT, dir), { recursive: true, force: true });

// Locales with the same data, like many regional variants and their
// language, share one data module named after the first of them.
const byBody = new Map<string, { name: string; tags: string[] }>();
for (const [name, tag] of LOCALES) {
  const digits = localDigits(tag);
  const body = erlBody(
    digits,
    PAIRS.map((pair) => [pair, derivePattern(tag, pair, digits)]),
  );
  const shared = byBody.get(body) ?? { name, tags: [] };
  byBody.set(body, shared);
  shared.tags.push(tag);
  await write(
    `src/glintl/locale/${name}.gleam`,
    gleamLocaleModule(tag, shared.name),
  );
}
for (const [body, { name, tags }] of byBody) {
  await write(
    `src/glintl/internal/generated/erlang/glintl_generated_${name}.erl`,
    erlModule(`glintl_generated_${name}`, tags, body),
  );
  await write(
    `src/glintl/internal/generated/javascript/${name}.mjs`,
    jsModule(tags),
  );
}
await write("src/glintl/locales.gleam", gleamLocalesModule());
await write("test/glintl/fixtures.gleam", fixtures());
await $`gleam format src test`.cwd(ROOT);
console.log(
  `Generated ${LOCALES.length} locales (${byBody.size} data modules) with ${RUNTIME}.`,
);
