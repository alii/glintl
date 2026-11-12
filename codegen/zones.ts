// Reads ICU's time zones: the names Intl accepts, and when each zone's offset
// changes. Writes them as one Erlang module, so `glintl/time_zone` can look
// zones up on Erlang.
//
// On its own it writes just that module, which is quicker than the whole
// generator: `bun codegen/zones.ts`.

import { join } from "node:path";
import * as erlang from "./erlang.ts";
import { bundleName, bundlesIn, chain, lookup, type Resource } from "./icu.ts";
import { LOCALES } from "./locales.ts";
import { requirePinnedBun } from "./runtime.ts";

const ROOT = join(import.meta.dir, "..");
const MODULE = "glintl_generated_time_zones";
export const PATH = `src/glintl/internal/generated/erlang/${MODULE}.erl`;

const BITS_PER_BYTE = 8;
const BYTE = 0xff;

const get = (r: Resource | undefined, key: string) =>
  r?.t === "table" ? r.entries.find(([k]) => k === key)?.[1] : undefined;

const ints = (r: Resource | undefined): number[] =>
  r?.t === "ints" ? r.values : [];

const int = (r: Resource | undefined): number => (r?.t === "int" ? r.value : 0);

const text = (r: Resource | undefined): string =>
  r?.t === "string" ? r.value : "";

const items = (r: Resource | undefined): Resource[] =>
  r?.t === "array" ? r.items : [];

// Big-endian bytes of a signed number.
const signed = (value: number, bytes: number): number[] =>
  Array.from({ length: bytes }, (_, i) =>
    Number(
      (BigInt.asUintN(bytes * BITS_PER_BYTE, BigInt(value)) >>
        BigInt((bytes - 1 - i) * BITS_PER_BYTE)) &
        BigInt(BYTE),
    ),
  );

const TRANSITION_BYTES = 8;
const OFFSET_BYTES = 4;

// --- Rules ----------------------------------------------------------------------

type Rules = {
  // Seconds since 1970 when the offset changes, in order.
  transitions: number[];
  // Each offset as [standard, daylight saving] seconds; the first applies
  // before any transition.
  types: [number, number][];
  // The type after each transition.
  typeMap: number[];
  // The rule after the last transition, from ICU's `finalRule`.
  final: { raw: number; year: number; rule: number[] } | undefined;
};

// ICU splits a 64-bit time into two 32-bit halves.
const halves = (values: number[]): number[] =>
  Array.from({ length: values.length / 2 }, (_, i) =>
    Number(
      (BigInt(values[2 * i]!) << BigInt(32)) |
        BigInt.asUintN(32, BigInt(values[2 * i + 1]!)),
    ),
  );

function rules(zone: Resource, ruleTable: Resource | undefined): Rules {
  const typeOffsets = ints(get(zone, "typeOffsets"));
  const typeMap = get(zone, "typeMap");
  const finalRule = text(get(zone, "finalRule"));

  return {
    transitions: [
      ...halves(ints(get(zone, "transPre32"))),
      ...ints(get(zone, "trans")),
      ...halves(ints(get(zone, "transPost32"))),
    ],
    types: Array.from({ length: typeOffsets.length / 2 }, (_, i) => [
      typeOffsets[2 * i]!,
      typeOffsets[2 * i + 1]!,
    ]),
    typeMap: typeMap?.t === "binary" ? [...typeMap.bytes] : [],
    final:
      finalRule === ""
        ? undefined
        : {
            raw: int(get(zone, "finalRaw")),
            year: int(get(zone, "finalYear")),
            rule: ints(get(ruleTable, finalRule)),
          },
  };
}

// --- Zones -----------------------------------------------------------------------

export type ZoneData = {
  // Each name Intl accepts, with its zone's number and its key's number.
  names: [string, number, number][];
  zones: Rules[];
  // Keys in ICU's name data, like `Asia:Calcutta`. Zones that share rules,
  // like Accra and Abidjan, can still have their own names.
  keys: string[];
};

// ICU's own key for a zone in its name data. It keeps zones in `typeMap`, and
// follows `typeAlias` for others, so `Asia/Kolkata` is `Asia:Calcutta`.
function nameKey(name: string): string | undefined {
  const key = name.replaceAll("/", ":");

  if (get(lookup(["timezoneTypes"], ["typeMap", "timezone"]), key)) {
    return key;
  }

  const alias = get(lookup(["timezoneTypes"], ["typeAlias", "timezone"]), key);

  return alias?.t === "string" ? alias.value.replaceAll("/", ":") : undefined;
}

export function zoneData(): ZoneData {
  const names = items(lookup(["zoneinfo64"], ["Names"])).map(text);
  const zones = items(lookup(["zoneinfo64"], ["Zones"]));
  const ruleTable = lookup(["zoneinfo64"], ["Rules"]);

  // A link is an int: the index of the zone it points to.
  const target = (i: number): number => {
    const zone = zones[i]!;

    return zone.t === "int" ? target(zone.value) : i;
  };

  const real = zones.flatMap((zone, i) => (zone.t === "int" ? [] : [i]));
  const number = new Map(real.map((i, n) => [i, n]));

  const accepted = names.flatMap((name, i): [string, number][] => {
    try {
      new Intl.DateTimeFormat("en", { timeZone: name });

      return [[name, number.get(target(i))!]];
    } catch {
      return [];
    }
  });

  // A name ICU doesn't list leads to its zone's own name.
  const nameKeys = accepted.map(([name, n]) => {
    const key = nameKey(name) ?? nameKey(names[real[n]!]!);

    if (key === undefined) {
      throw new Error(`${name} has no key in ICU's name data`);
    }

    return key;
  });

  const keys = [...new Set(nameKeys)].sort();

  return {
    names: accepted.map(([name, n], i): [string, number, number] => [
      name,
      n,
      keys.indexOf(nameKeys[i]!),
    ]),
    zones: real.map((i) => rules(zones[i]!, ruleTable)),
    keys,
  };
}

// --- Names -----------------------------------------------------------------------

// The names ICU gives a zone: long and short, standard and daylight saving.
const NAME_TYPES = ["ls", "ld", "ss", "sd"] as const;

// A name that stops a locale from using its parent's.
const NO_INHERITANCE = "∅∅∅";

// Name numbers 0 and 1 mean no name here, and no name at all.
const NO_NAME = 0;
const BLOCKED = 1;
const FIRST_NAME = 2;

// A metazone period without a start or an end, like ICU's `gDefaultFrom` and
// `gDefaultTo`. So zones have no names before 1970.
const FIRST_INSTANT = 0;
const LAST_INSTANT = Date.UTC(9999, 11, 31, 23, 59) / 1000;

// ICU writes a metazone's dates like "1970-01-01 00:00", in UTC.
const instant = (s: string): number =>
  Date.parse(`${s.replace(" ", "T")}:00Z`) / 1000;

type Names = {
  // Each key's metazones, as [metazone, from, to] in seconds since 1970.
  periods: [number, number, number][][];
  // Each zone bundle's names: [key, ls, ld, ss, sd] as name numbers. Metazones
  // come after the keys.
  bundles: number[][][];
  // Each locale's zone bundles, most specific first.
  chains: [string, number[]][];
  // The names, as numbers of words, and the words.
  names: number[][];
  words: string[];
};

// Splits a name into words, each with the spaces after it, so they join back
// into the name.
const splitWords = (name: string): string[] => name.match(/\s+|\S+\s*/gu) ?? [];

function nameData(data: ZoneData): Names {
  const info = lookup(["metaZones"], ["metazoneInfo"]);

  const periodsByZone = data.keys.map((key) =>
    items(get(info, key)).map((period) => items(period).map(text)),
  );

  const metazones = [
    ...new Set(periodsByZone.flat().map(([mz]) => mz!)),
  ].sort();

  const keyNumbers = new Map<string, number>([
    ...data.keys.map((key, n): [string, number] => [key, n]),
    ...metazones.map((mz, i): [string, number] => [
      `meta:${mz}`,
      data.keys.length + i,
    ]),
  ]);

  const names: number[][] = [];
  const words: string[] = [];
  const nameNumbers = new Map<string, number>();
  const wordNumbers = new Map<string, number>();

  const word = (w: string): number => {
    if (!wordNumbers.has(w)) {
      wordNumbers.set(w, words.length);
      words.push(w);
    }

    return wordNumbers.get(w)!;
  };

  const nameNumber = (r: Resource | undefined): number => {
    if (r?.t !== "string") {
      return NO_NAME;
    }

    if (r.value === NO_INHERITANCE) {
      return BLOCKED;
    }

    if (!nameNumbers.has(r.value)) {
      nameNumbers.set(r.value, FIRST_NAME + names.length);
      names.push(splitWords(r.value).map(word));
    }

    return nameNumbers.get(r.value)!;
  };

  const bundleNames = bundlesIn("zone/");
  const bundleNumbers = new Map(bundleNames.map((name, i) => [name, i]));

  const bundles = bundleNames.map((name) => {
    const zoneStrings = get(lookup([name], []), "zoneStrings");

    return zoneStrings?.t === "table"
      ? zoneStrings.entries
          .flatMap(([key, value]) => {
            const n = keyNumbers.get(key);

            const found = NAME_TYPES.map((type) =>
              nameNumber(get(value, type)),
            );

            return n === undefined || found.every((f) => f === NO_NAME)
              ? []
              : [[n, ...found]];
          })
          .sort((a, b) => a[0]! - b[0]!)
      : [];
  });

  return {
    periods: periodsByZone.map((periods) =>
      periods.map(([mz, from, to]): [number, number, number] => [
        metazones.indexOf(mz!),
        from === undefined ? FIRST_INSTANT : instant(from),
        to === undefined ? LAST_INSTANT : instant(to),
      ]),
    ),
    bundles,
    chains: LOCALES.map(([, tag]): [string, number[]] => [
      tag,
      // Intl first picks a locale ICU has, then ICU looks for its names.
      chain(chain(bundleName(tag))[0]!, "zone/").map((b) =>
        bundleNumbers.get(b)!,
      ),
    ]),
    names,
    words,
  };
}

// --- Erlang ----------------------------------------------------------------------

// Written as Gleam's `Rules` and `Final` from `glintl/internal/zones`.
const rulesTerm = (r: Rules): string =>
  `{rules, ${[
    erlang.bytes(r.transitions.flatMap((t) => signed(t, TRANSITION_BYTES))),
    erlang.bytes(
      r.types.flatMap(([raw, dst]) => [
        ...signed(raw, OFFSET_BYTES),
        ...signed(dst, OFFSET_BYTES),
      ]),
    ),
    erlang.bytes(r.typeMap),
    r.final === undefined
      ? "no_final"
      : `{final, ${r.final.raw}, ${r.final.year}, {${r.final.rule.join(", ")}}}`,
  ].join(", ")}}`;

const NUMBER_BYTES = 2;
const START_BYTES = 3;
const TIME_BYTES = 8;
const LARGEST_NUMBER = 0xffff;

// Lengths are stored a byte each, with where every 16th item starts, so
// finding an item adds up at most 15 lengths.
const CHECKPOINT_EVERY = 16;
const LARGEST_LENGTH = 0xff;

// Where each item starts, then where the last one ends.
const starts = (lengths: number[]): number[] =>
  lengths.reduce(
    (acc, n) => {
      acc.push(acc.at(-1)! + n);

      return acc;
    },
    [0],
  );

// An index of items by their lengths: the lengths, and every 16th start.
function lengthIndex(name: string, lengths: number[]): string[][] {
  if (lengths.some((n) => n > LARGEST_LENGTH)) {
    throw new Error(`Some of ${name} are too long for a byte`);
  }

  return [
    [`${name}_lengths() ->\n    ${erlang.bytes(lengths)}`],
    [
      `${name}_checkpoints() ->\n    ${packed(
        starts(lengths).filter((_, i) => i % CHECKPOINT_EVERY === 0),
        START_BYTES,
      )}`,
    ],
  ];
}

// Each bundle's entries for one length of name: [key, standard, daylight].
const entries = (bundles: number[][][], columns: [number, number]) =>
  bundles.map((bundle) =>
    packed(
      bundle.flatMap((entry) => {
        const [standard, daylight] = columns.map((c) => entry[c]!);

        return standard === NO_NAME && daylight === NO_NAME
          ? []
          : [entry[0]!, standard!, daylight!];
      }),
      NUMBER_BYTES,
    ),
  );

// Columns of `Names.bundles` entries, after the key.
const LONG_COLUMNS: [number, number] = [1, 2];
const SHORT_COLUMNS: [number, number] = [3, 4];

const packed = (numbers: number[], bytes: number) =>
  erlang.bytes(numbers.flatMap((n) => signed(n, bytes)));

export function zonesModule(header: string): string {
  const data = zoneData();
  const names = nameData(data);
  const encoder = new TextEncoder();

  if (
    names.words.length > LARGEST_NUMBER ||
    FIRST_NAME + names.names.length > LARGEST_NUMBER ||
    data.keys.length + names.periods.flat().length > LARGEST_NUMBER
  ) {
    throw new Error("Too many zone names for 16-bit numbers");
  }

  return erlang.module(
    MODULE,
    header,
    [
      "zone/1",
      "rules/0",
      "name_chain/1",
      "metazones/0",
      "long_names/0",
      "short_names/0",
      "words/0",
      "word_lengths/0",
      "word_checkpoints/0",
      "name_words/0",
      "name_lengths/0",
      "name_checkpoints/0",
    ],
    [
      [
        ...data.names.map(
          ([name, n, key]) =>
            `zone(${erlang.string(name.toLowerCase())}) ->\n    {ok, {${erlang.string(name)}, ${n}, ${key}}}`,
        ),
        "zone(_) ->\n    {error, nil}",
      ],
      [`rules() ->\n    ${erlang.tuple(data.zones.map(rulesTerm))}`],
      [
        ...names.chains.map(
          ([tag, bundles]) =>
            `name_chain(${erlang.string(tag)}) ->\n    [${bundles.join(", ")}]`,
        ),
        "name_chain(_) ->\n    []",
      ],
      [
        `metazones() ->\n    ${erlang.tuple(
          names.periods.map((periods) =>
            erlang.bytes(
              periods.flatMap(([mz, from, to]) => [
                ...signed(mz, NUMBER_BYTES),
                ...signed(from, TIME_BYTES),
                ...signed(to, TIME_BYTES),
              ]),
            ),
          ),
        )}`,
      ],
      [
        `long_names() ->\n    ${erlang.tuple(entries(names.bundles, LONG_COLUMNS))}`,
      ],
      [
        `short_names() ->\n    ${erlang.tuple(entries(names.bundles, SHORT_COLUMNS))}`,
      ],
      [`words() ->\n    ${erlang.string(names.words.join(""))}`],
      ...lengthIndex(
        "word",
        names.words.map((w) => encoder.encode(w).length),
      ),
      [`name_words() ->\n    ${packed(names.names.flat(), NUMBER_BYTES)}`],
      ...lengthIndex(
        "name",
        names.names.map((n) => n.length),
      ),
    ],
  );
}

if (import.meta.main) {
  requirePinnedBun("codegen/zones.ts");
  await Bun.write(join(ROOT, PATH), zonesModule(erlang.header()));
  console.log(`Wrote ${PATH}.`);
}
