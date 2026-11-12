import cldr from "cldr-core/availableLocales.json" with { type: "json" };

const RESERVED = new Set(
  "as assert auto case const delegate derive echo else fn if implement import let macro opaque panic pub test todo type use".split(
    " ",
  ),
);

// A locale's Gleam module name: its tag in lower case with `_` for `-`, and
// a `_` after names that are Gleam keywords.
export function moduleName(tag: string): string {
  const name = tag.toLowerCase().replaceAll("-", "_");

  return RESERVED.has(name) ? name + "_" : name;
}

// JavaScript can't list the locales it has, so we ask it about each of
// CLDR's. A locale with no data falls back to another language and still
// formats dates, so we leave out tags whose language changes.
export const LOCALES = cldr.availableLocales.full
  .filter((tag) => tag !== "und")
  .filter((tag) => {
    const resolved = new Intl.DateTimeFormat(tag).resolvedOptions().locale;

    return resolved.split("-")[0] === tag.split("-")[0];
  })
  .map((tag): [string, string] => [moduleName(tag), tag]);
