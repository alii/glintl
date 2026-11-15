// Reads ICU's time zones: the names Intl accepts, and when each zone's offset
// changes. Writes them as one Erlang module, so `glintl/time_zone` can look
// zones up on Erlang.
//
// Run `bun codegen/zones.ts` to write only that module, which is faster than
// running the whole generator.

import { join } from "node:path";
import * as erlang from "./erlang.ts";
import { bundleName, chain, lookup, type Resource } from "./icu.ts";
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

const tableEntries = (r: Resource | undefined): [string, Resource][] =>
  r?.t === "table" ? r.entries : [];

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

// tz 2026d made these names zones again, but Intl keeps them as links to the
// zones below. See https://github.com/tc39/ecma402/issues/1103.
const POSIX_STYLE = new Map([
  ["EST5EDT", "America/New_York"],
  ["CST6CDT", "America/Chicago"],
  ["MST7MDT", "America/Denver"],
  ["PST8PDT", "America/Los_Angeles"],
]);

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

      const primary = POSIX_STYLE.get(name);
      const zone = primary === undefined ? i : names.indexOf(primary);

      return [[name, number.get(target(zone))!]];
    } catch {
      return [];
    }
  });

  // A name missing from ICU's name data uses the key of its zone's own name.
  const nameKeys = accepted.map(([name, n]) => {
    const key =
      nameKey(POSIX_STYLE.get(name) ?? name) ?? nameKey(names[real[n]!]!);

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

// The names ICU gives a zone: long and short, standard and daylight saving,
// then generic, then its city.
const NAME_TYPES = ["ls", "ld", "ss", "sd", "lg", "sg", "ec"] as const;

// A name that stops a locale from using its parent's.
const NO_INHERITANCE = "∅∅∅";

const WORLD = "001";
const ROOT_BUNDLE = "zone/root";

// Where a zone's city is in a `Names.bundles` entry.
const CITY_COLUMN = 7;

// ICU's `gDefRegionPattern` and `gDefFallbackPattern`.
const DEFAULT_REGION_FORMAT = "{0}";
const DEFAULT_FALLBACK_FORMAT = "{1} ({0})";

// Name number 0 means the bundle has no name of its own, and 1 means the zone
// has no name at all.
const NO_NAME = 0;
const BLOCKED = 1;
const FIRST_NAME = 2;

// A city the generator fills in once it knows which zones need one.
const PENDING = -1;

// The start and end ICU gives a metazone period that has none, like ICU's
// `gDefaultFrom` and `gDefaultTo`. So zones have no names before 1970.
const FIRST_INSTANT = 0;
const LAST_INSTANT = Date.UTC(9999, 11, 31, 23, 59) / 1000;

// ICU writes a metazone's dates like "1970-01-01 00:00", in UTC.
const instant = (s: string): number =>
  Date.parse(`${s.replace(" ", "T")}:00Z`) / 1000;

type Names = {
  // Each key's metazones, as [metazone, from, to] in seconds since 1970.
  periods: [number, number, number][][];
  // Each zone bundle's names: [key, ls, ld, ss, sd, lg, sg, ec] as name
  // numbers. Metazones come after the keys.
  bundles: number[][][];
  // Regions that location names need, like "US", and "001" for the world.
  regions: string[];
  // Each region bundle's country names: [region, name].
  regionBundles: number[][][];
  // Each key's country, as a region number plus 1 or 0 for none, then 1 if
  // it's the country's main zone.
  countries: [number, number][];
  // Each metazone's zone in each region, as [region, key], sorted.
  golden: [number, number][][];
  // Each locale's region bundles, most specific first, its region format and
  // fallback format, and its region.
  locations: [string, number[], string, string, number][];
  // Each locale's zone bundles, most specific first.
  chains: [string, number[]][];
  // The names, as numbers of words, and the words.
  names: number[][];
  words: string[];
  // Place names, numbered from `FIRST_NAME` like names.
  labels: string[];
};

// The bundles in a folder that glintl's locales look in, like "zone/en_GB",
// in the order they're first found.
const usedBundles = (folder: string): string[] => [
  ...new Set(
    LOCALES.flatMap(([, tag]) => chain(chain(bundleName(tag))[0]!, folder)),
  ),
];

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

  // Place names, like cities and countries, rarely share words, so they're
  // stored whole.
  const labels: string[] = [];
  const labelNumbers = new Map<string, number>();

  const labelNumber = (value: string): number => {
    if (value === NO_INHERITANCE) {
      return BLOCKED;
    }

    if (!labelNumbers.has(value)) {
      labelNumbers.set(value, FIRST_NAME + labels.length);
      labels.push(value);
    }

    return labelNumbers.get(value)!;
  };

  // Cities by bundle and key, until we know which zones need them.
  const cityTexts = new Map<string, string>();

  // Only the bundles some locale looks in.
  const bundleNames = usedBundles("zone/");
  const bundleNumbers = new Map(bundleNames.map((name, i) => [name, i]));

  const bundles = bundleNames.map((name) => {
    const zoneStrings = get(lookup([name], []), "zoneStrings");

    return zoneStrings?.t === "table"
      ? zoneStrings.entries
          .flatMap(([key, value]) => {
            const n = keyNumbers.get(key);

            const found = NAME_TYPES.map((type) => {
              if (type !== "ec") {
                return nameNumber(get(value, type));
              }

              const city = text(get(value, type));

              if (city !== "" && n !== undefined) {
                cityTexts.set(`${name} ${n}`, city);
              }

              return city === "" ? NO_NAME : PENDING;
            });

            return n === undefined || found.every((f) => f === NO_NAME)
              ? []
              : [[n, ...found]];
          })
          .sort((a, b) => a[0]! - b[0]!)
      : [];
  });

  // --- Location names, for generic names ---

  const zoneNames = items(lookup(["zoneinfo64"], ["Names"])).map(text);
  const zoneRegions = items(lookup(["zoneinfo64"], ["Regions"])).map(text);

  const regionOf = (key: string): string =>
    zoneRegions[zoneNames.indexOf(key.replaceAll(":", "/"))] ?? WORLD;

  const keyOf = (id: string): number => {
    const direct = data.keys.indexOf(id.replaceAll("/", ":"));

    return direct >= 0 ? direct : data.keys.indexOf(nameKey(id) ?? "");
  };

  const mapTimezones = lookup(["metaZones"], ["mapTimezones"]);
  const primaryZones = lookup(["metaZones"], ["primaryZones"]);

  const targetRegion = (tag: string) =>
    new Intl.Locale(tag).maximize().region ?? WORLD;

  const regions = [
    ...new Set([
      WORLD,
      ...data.keys.map(regionOf),
      ...metazones.flatMap((mz) =>
        tableEntries(get(mapTimezones, mz)).map(([region]) => region),
      ),
      ...LOCALES.map(([, tag]) => targetRegion(tag)),
    ]),
  ].sort();

  const regionNumber = (region: string) => regions.indexOf(region);

  // ICU's `ZoneMeta::getCanonicalCountry`: a zone is its country's main zone
  // if it's the only one there, or CLDR says it's the primary one.
  const zonesIn = new Map<string, number>();

  data.keys.forEach((key) => {
    const region = regionOf(key);
    zonesIn.set(region, (zonesIn.get(region) ?? 0) + 1);
  });

  const countries = data.keys.map((key): [number, number] => {
    const region = regionOf(key);

    if (region === WORLD) {
      return [0, 0];
    }

    const primary = text(get(primaryZones, region)).replaceAll("/", ":");

    return [
      regionNumber(region) + 1,
      +(zonesIn.get(region) === 1 || primary === key),
    ];
  });

  const golden = metazones.map((mz) => {
    return tableEntries(get(mapTimezones, mz))
      .map(([region, id]): [number, number] => [
        regionNumber(region),
        keyOf(text(id)),
      ])
      .filter(([, key]) => key >= 0)
      .sort((a, b) => a[0] - b[0]);
  });

  // A zone's generic location name is its country's name if it's the
  // country's main zone, and otherwise its city's.
  // ICU's `getReferenceZoneID`: a metazone's zone in a region, or else its
  // zone for the world.
  const world = regionNumber(WORLD);

  const goldenFor = (mz: number, region: number) =>
    (golden[mz]!.find(([r]) => r === region) ??
      golden[mz]!.find(([r]) => r === world))?.[1];

  const targets = [
    ...new Set(LOCALES.map(([, tag]) => regionNumber(targetRegion(tag)))),
  ];

  // Metazones where a zone can get a partial location name, like "Pacific
  // Time (Canada)": its offset can differ from the metazone's zone in some
  // locale's region.
  const partialIn = (n: number) =>
    [
      ...new Set(periodsByZone[n]!.map(([mz]) => metazones.indexOf(mz!))),
    ].filter((mz) => targets.some((r) => goldenFor(mz, r) !== n));

  // A partial location name uses the country if the zone is the metazone's
  // zone there, and otherwise the city.
  const country = (n: number) => countries[n]![0] - 1;

  const needsCity = (n: number) =>
    countries[n]![1] === 0 ||
    partialIn(n).some((mz) => goldenFor(mz, country(n)) !== n);

  bundleNames.forEach((name, b) => {
    bundles[b]!.forEach((entry) => {
      const city = cityTexts.get(`${name} ${entry[0]}`);

      entry[CITY_COLUMN] =
        city !== undefined && needsCity(entry[0]!)
          ? labelNumber(city)
          : NO_NAME;
    });
  });

  // ICU's `getDefaultExemplarLocationName`: a zone in a country without a
  // city name uses the last part of its ID, like "Los Angeles".
  const root = bundleNumbers.get(ROOT_BUNDLE)!;

  data.keys.forEach((key, n) => {
    const last = key.split(":").at(-1)!;

    if (regionOf(key) === WORLD || !key.includes(":") || !needsCity(n)) {
      return;
    }

    const city = labelNumber(last.replaceAll("_", " "));
    const entry = bundles[root]!.find((e) => e[0] === n);

    if (entry === undefined) {
      bundles[root]!.push([n, ...NAME_TYPES.map(() => NO_NAME)]);
      bundles[root]!.at(-1)![CITY_COLUMN] = city;
    } else if (entry[CITY_COLUMN] === NO_NAME) {
      entry[CITY_COLUMN] = city;
    }
  });

  bundles[root]!.sort((a, b) => a[0]! - b[0]!);

  // Only countries with a main zone need their names.
  const mainCountries = new Set(
    data.keys.flatMap((_, n) =>
      countries[n]![1] === 1 ||
      partialIn(n).some((mz) => goldenFor(mz, country(n)) === n)
        ? [country(n)]
        : [],
    ),
  );

  const regionBundleNames = usedBundles("region/");
  const regionBundleNumbers = new Map(regionBundleNames.map((b, i) => [b, i]));

  const regionBundles = regionBundleNames.map((name) => {
    return tableEntries(get(lookup([name], []), "Countries"))
      .flatMap(([region, value]) => {
        const r = regionNumber(region);
        const country = text(value);

        return r < 0 || country === "" || !mainCountries.has(r)
          ? []
          : [[r, labelNumber(country)]];
      })
      .sort((a, b) => a[0]! - b[0]!);
  });

  // The region and fallback formats, like "{0} Time" and "{1} ({0})", from
  // the first zone bundle that has them.
  const zoneFormat = (bundleChain: string[], key: string, otherwise: string) =>
    bundleChain
      .map((b) => text(get(get(lookup([b], []), "zoneStrings"), key)))
      .find((s) => s !== "") ?? otherwise;

  const locations = LOCALES.map(
    ([, tag]): [string, number[], string, string, number] => {
      const icu = chain(bundleName(tag))[0]!;
      const zoneChain = chain(icu, "zone/");

      return [
        tag,
        chain(icu, "region/").map((b) => regionBundleNumbers.get(b)!),
        zoneFormat(zoneChain, "regionFormat", DEFAULT_REGION_FORMAT),
        zoneFormat(zoneChain, "fallbackFormat", DEFAULT_FALLBACK_FORMAT),
        regionNumber(targetRegion(tag)),
      ];
    },
  );

  return {
    regions,
    regionBundles,
    countries,
    golden,
    locations,
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
    labels,
  };
}

// --- Erlang ----------------------------------------------------------------------

// Writes rules as Gleam's `Rules` and `Final` from `glintl/internal/zones`.
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

// Name and word numbers.
const NAME_BYTES = 2;
const LARGEST_NAME = 0xffff;

const LARGEST_START = 0xffffff;

// Where each item starts, then where the last one ends, so item `i` runs from
// start `i` to start `i + 1`.
function startIndex(name: string, lengths: number[]): string[] {
  const starts = lengths.reduce(
    (acc, n) => {
      acc.push(acc.at(-1)! + n);

      return acc;
    },
    [0],
  );

  if (starts.at(-1)! > LARGEST_START) {
    throw new Error(`${name} are too long for ${START_BYTES} byte starts`);
  }

  return [`${name}_starts() ->\n    ${packed(starts, START_BYTES)}`];
}

// Each bundle's entries for one length of name: a 16-bit key, then 24-bit
// name numbers for standard and daylight saving time.
const entries = (bundles: number[][][], columns: [number, number]) =>
  bundles.map((bundle) =>
    erlang.bytes(
      bundle.flatMap((entry) => {
        const [standard, daylight] = columns.map((c) => entry[c]!);

        return standard === NO_NAME && daylight === NO_NAME
          ? []
          : [
              ...signed(entry[0]!, NUMBER_BYTES),
              ...signed(standard!, NAME_BYTES),
              ...signed(daylight!, NAME_BYTES),
            ];
      }),
    ),
  );

// Like `entries`, for tables with one name: a 16-bit key and a 24-bit name
// number.
const singles = (bundles: number[][][], column: number) =>
  bundles.map((bundle) =>
    erlang.bytes(
      bundle.flatMap((entry) =>
        entry[column] === NO_NAME
          ? []
          : [
              ...signed(entry[0]!, NUMBER_BYTES),
              ...signed(entry[column]!, NAME_BYTES),
            ],
      ),
    ),
  );

// One byte for each zone key: 1 if any bundle has the zone's own names in
// these columns. Zones without any skip straight to their metazone.
const ownNames = (names: Names, keys: number, columns: [number, number]) => {
  const own = new Set(
    names.bundles.flatMap((bundle) =>
      bundle
        .filter((entry) => columns.some((c) => entry[c] !== NO_NAME))
        .map((entry) => entry[0]!),
    ),
  );

  return erlang.bytes(Array.from({ length: keys }, (_, k) => +own.has(k)));
};

// Columns of `Names.bundles` entries, after the key.
const LONG_COLUMNS: [number, number] = [1, 2];
const SHORT_COLUMNS: [number, number] = [3, 4];
const LONG_GENERIC_COLUMN = 5;
const SHORT_GENERIC_COLUMN = 6;

const packed = (numbers: number[], bytes: number) =>
  erlang.bytes(numbers.flatMap((n) => signed(n, bytes)));

export function zonesModule(header: string): string {
  const data = zoneData();
  const names = nameData(data);
  const encoder = new TextEncoder();

  if (
    names.words.length > LARGEST_NAME ||
    FIRST_NAME + names.names.length > LARGEST_NAME ||
    FIRST_NAME + names.labels.length > LARGEST_NAME ||
    data.keys.length + names.periods.flat().length > LARGEST_NUMBER
  ) {
    throw new Error("Too many zone names for their numbers");
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
      "own_long_names/0",
      "own_short_names/0",
      "long_generic_names/0",
      "short_generic_names/0",
      "own_long_generic_names/0",
      "own_short_generic_names/0",
      "cities/0",
      "region_names/0",
      "countries/0",
      "golden_zones/0",
      "key_zones/0",
      "location/1",
      "labels/0",
      "label_starts/0",
      "region_codes/0",
      "world_region/0",
      "words/0",
      "word_starts/0",
      "name_words/0",
      "name_starts/0",
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
      [
        `own_long_names() ->\n    ${ownNames(names, data.keys.length, LONG_COLUMNS)}`,
      ],
      [
        `own_short_names() ->\n    ${ownNames(names, data.keys.length, SHORT_COLUMNS)}`,
      ],
      [
        `long_generic_names() ->\n    ${erlang.tuple(singles(names.bundles, LONG_GENERIC_COLUMN))}`,
      ],
      [
        `short_generic_names() ->\n    ${erlang.tuple(singles(names.bundles, SHORT_GENERIC_COLUMN))}`,
      ],
      [
        `own_long_generic_names() ->\n    ${ownNames(names, data.keys.length, [LONG_GENERIC_COLUMN, LONG_GENERIC_COLUMN])}`,
      ],
      [
        `own_short_generic_names() ->\n    ${ownNames(names, data.keys.length, [SHORT_GENERIC_COLUMN, SHORT_GENERIC_COLUMN])}`,
      ],
      [`cities() ->\n    ${erlang.tuple(singles(names.bundles, CITY_COLUMN))}`],
      [
        `region_names() ->\n    ${erlang.tuple(
          singles(names.regionBundles, 1),
        )}`,
      ],
      [
        `countries() ->\n    ${erlang.bytes(
          names.countries.flatMap(([region, primary]) => [
            ...signed(region, NUMBER_BYTES),
            primary,
          ]),
        )}`,
      ],
      [
        `golden_zones() ->\n    ${erlang.tuple(
          names.golden.map((zones) => packed(zones.flat(), NUMBER_BYTES)),
        )}`,
      ],
      [
        `key_zones() ->\n    ${packed(
          data.keys.map(
            (_, k) => data.names.find(([, , key]) => key === k)![1],
          ),
          NUMBER_BYTES,
        )}`,
      ],
      [
        ...names.locations.map(
          ([tag, regionChain, regionFormat, fallbackFormat, region]) =>
            `location(${erlang.string(tag)}) ->\n    {location, [${regionChain.join(", ")}], ${erlang.string(regionFormat)}, ${erlang.string(fallbackFormat)}, ${region}}`,
        ),
        `location(_) ->\n    {location, [], ${erlang.string(DEFAULT_REGION_FORMAT)}, ${erlang.string(DEFAULT_FALLBACK_FORMAT)}, ${0}}`,
      ],
      [`words() ->\n    ${erlang.string(names.words.join(""))}`],
      startIndex(
        "word",
        names.words.map((w) => encoder.encode(w).length),
      ),
      [`name_words() ->\n    ${packed(names.names.flat(), NAME_BYTES)}`],
      [`labels() ->\n    ${erlang.string(names.labels.join(""))}`],
      [
        `region_codes() ->\n    ${erlang.tuple(names.regions.map(erlang.string))}`,
      ],
      [`world_region() ->\n    ${names.regions.indexOf(WORLD)}`],
      startIndex(
        "label",
        names.labels.map((l) => encoder.encode(l).length),
      ),
      startIndex(
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
