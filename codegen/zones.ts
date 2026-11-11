// Reads ICU's time zones: the names Intl accepts, and when each zone's offset
// changes. Writes them as one Erlang module, so `glintl/time_zone` can look
// zones up on Erlang.
//
// On its own it writes just that module, which is quicker than the whole
// generator: `bun codegen/zones.ts`.

import { join } from "node:path";
import * as erlang from "./erlang.ts";
import { lookup, type Resource } from "./icu.ts";
import { requirePinnedBun } from "./runtime.ts";

const ROOT = join(import.meta.dir, "..");
const MODULE = "glintl_generated_time_zones";
export const PATH = `src/glintl/internal/generated/erlang/${MODULE}.erl`;

export const DESCRIPTION =
  "Every time zone's name and when its offset changes.";

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
  // Each name Intl accepts, with its zone's number.
  names: [string, number][];
  zones: Rules[];
};

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

  return {
    names: accepted,
    zones: real.map((i) => rules(zones[i]!, ruleTable)),
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

export function zonesModule(header: string): string {
  const data = zoneData();

  return erlang.module(
    MODULE,
    header,
    ["zone/1", "rules/0"],
    [
      [
        ...data.names.map(
          ([name, n]) =>
            `zone(${erlang.string(name.toLowerCase())}) ->\n    {ok, {${erlang.string(name)}, ${n}}}`,
        ),
        "zone(_) ->\n    {error, nil}",
      ],
      [`rules() ->\n    ${erlang.tuple(data.zones.map(rulesTerm))}`],
    ],
  );
}

if (import.meta.main) {
  requirePinnedBun("codegen/zones.ts");
  await Bun.write(join(ROOT, PATH), zonesModule(erlang.header(DESCRIPTION)));
  console.log(`Wrote ${PATH}.`);
}
