// Reads ICU's own data file to get what Intl hides, like the patterns ICU
// picks from for a set of fields. The file comes from the same ICU release as
// the pinned Bun, so the two agree.

import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { inflateRawSync } from "node:zlib";

const ICU_VERSION = "79.1";
const MAJOR = ICU_VERSION.split(".")[0];
const ZIP = `icu4c-${ICU_VERSION}-data-bin-l.zip`;
const URL = `https://github.com/unicode-org/icu/releases/download/release-${ICU_VERSION}/${ZIP}`;

const ZIP_SHA256 =
  "72489fb316a60ae1c1da205866edd01b17e8fbf8354ad0615e6cc60f74e08811";

const DAT = `icudt${MAJOR}l.dat`;

// ICU's tables for falling back from a locale that has no bundle. They're
// compiled into ICU's code, not its data file.
const FALLBACK_URL = `https://raw.githubusercontent.com/unicode-org/icu/release-${ICU_VERSION}/icu4c/source/common/localefallback_data.h`;

// The cached copy's name includes the ICU version, because the file has the
// same name in every release.
const FALLBACK = `localefallback_data-${ICU_VERSION}.h`;

const FALLBACK_SHA256 =
  "f022a3e22e21c88061228e6d8f9ff4b8ce87e8b66995e0490c9f7c11067490d0";

// ICU's files live outside `.cache`, because each run empties `.cache`.
const DIR = join(import.meta.dir, ".icu");

// --- The zip ------------------------------------------------------------------

const ZIP_END_SIGNATURE = 0x06054b50;
const ZIP_END_SIZE = 22;
const ZIP_END_ENTRIES = 10;
const ZIP_END_DIRECTORY = 16;
const ZIP_ENTRY_SIGNATURE = 0x02014b50;
const ZIP_ENTRY_SIZE = 46;
const ZIP_ENTRY_METHOD = 10;
const ZIP_ENTRY_COMPRESSED = 20;
const ZIP_ENTRY_NAME_LENGTH = 28;
const ZIP_ENTRY_EXTRA_LENGTH = 30;
const ZIP_ENTRY_COMMENT_LENGTH = 32;
const ZIP_ENTRY_HEADER = 42;
const ZIP_HEADER_SIZE = 30;
const ZIP_HEADER_NAME_LENGTH = 26;
const ZIP_HEADER_EXTRA_LENGTH = 28;
const DEFLATE = 8;

// Takes one file out of a zip with no comment at its end.
function unzip(zip: Buffer, name: string): Buffer {
  const end = zip.length - ZIP_END_SIZE;

  if (zip.readUInt32LE(end) !== ZIP_END_SIGNATURE) {
    throw new Error(`${ZIP}: not a zip`);
  }

  type Entry = { header: number; method: number; size: number };

  // Walks the central directory for the file's entry.
  const search = (at: number, left: number): Entry | undefined => {
    if (left === 0) {
      return undefined;
    }

    if (zip.readUInt32LE(at) !== ZIP_ENTRY_SIGNATURE) {
      throw new Error(`${ZIP}: bad entry`);
    }

    const nameLength = zip.readUInt16LE(at + ZIP_ENTRY_NAME_LENGTH);
    const start = at + ZIP_ENTRY_SIZE;

    if (zip.toString("utf8", start, start + nameLength) === name) {
      return {
        header: zip.readUInt32LE(at + ZIP_ENTRY_HEADER),
        method: zip.readUInt16LE(at + ZIP_ENTRY_METHOD),
        size: zip.readUInt32LE(at + ZIP_ENTRY_COMPRESSED),
      };
    }

    return search(
      start +
        nameLength +
        zip.readUInt16LE(at + ZIP_ENTRY_EXTRA_LENGTH) +
        zip.readUInt16LE(at + ZIP_ENTRY_COMMENT_LENGTH),
      left - 1,
    );
  };

  const entry = search(
    zip.readUInt32LE(end + ZIP_END_DIRECTORY),
    zip.readUInt16LE(end + ZIP_END_ENTRIES),
  );

  if (entry === undefined || entry.method !== DEFLATE) {
    throw new Error(`${ZIP}: no deflated ${name}`);
  }

  const { header } = entry;

  const data =
    header +
    ZIP_HEADER_SIZE +
    zip.readUInt16LE(header + ZIP_HEADER_NAME_LENGTH) +
    zip.readUInt16LE(header + ZIP_HEADER_EXTRA_LENGTH);

  return inflateRawSync(zip.subarray(data, data + entry.size));
}

async function download(): Promise<Buffer> {
  const path = join(DIR, DAT);

  if (existsSync(path)) {
    return readFileSync(path);
  }

  const response = await fetch(URL);

  if (!response.ok) {
    throw new Error(`Can't download ${URL}: ${response.status}`);
  }

  const zip = Buffer.from(await response.arrayBuffer());
  const sha = createHash("sha256").update(zip).digest("hex");

  if (sha !== ZIP_SHA256) {
    throw new Error(`${URL} has SHA-256 ${sha}, not ${ZIP_SHA256}`);
  }

  const dat = unzip(zip, DAT);
  mkdirSync(DIR, { recursive: true });
  writeFileSync(path, dat);

  return dat;
}

if (process.versions.icu !== ICU_VERSION) {
  throw new Error(
    `Bun has ICU ${process.versions.icu}, but icu.ts reads ICU ${ICU_VERSION}`,
  );
}

async function downloadFallback(): Promise<string> {
  const path = join(DIR, FALLBACK);

  if (existsSync(path)) {
    return readFileSync(path, "utf8");
  }

  const response = await fetch(FALLBACK_URL);

  if (!response.ok) {
    throw new Error(`Can't download ${FALLBACK_URL}: ${response.status}`);
  }

  const text = await response.text();
  const sha = createHash("sha256").update(text).digest("hex");

  if (sha !== FALLBACK_SHA256) {
    throw new Error(
      `${FALLBACK_URL} has SHA-256 ${sha}, not ${FALLBACK_SHA256}`,
    );
  }

  mkdirSync(DIR, { recursive: true });
  writeFileSync(path, text);

  return text;
}

const buffer = await download();
const fallback = await downloadFallback();

// Each table's entries end with a comment like `// sr -> Cyrl`.
const fallbackTable = (name: string): Map<string, string> => {
  const start = fallback.indexOf(`${name}[] = {`);
  const end = fallback.indexOf("};", start);

  return new Map(
    [...fallback.slice(start, end).matchAll(/\/\/ (\S+) -> (\S+)/g)].map(
      (m): [string, string] => [m[1]!, m[2]!],
    ),
  );
};

const defaultScripts = fallbackTable("defaultScriptTable");
const parentLocales = fallbackTable("parentLocaleTable");
const view = new DataView(buffer.buffer, buffer.byteOffset, buffer.byteLength);

// --- The data file's table of contents ------------------------------------------

const BYTES_PER_WORD = 4;
const BYTES_PER_UNIT = 2;
const TOC_ENTRY = 8;

const word = (at: number) => view.getUint32(at, true);
const unit = (at: number) => view.getUint16(at, true);

const cString = (at: number): string =>
  buffer.toString("latin1", at, buffer.indexOf(0, at));

const tocStart = unit(0);

const toc = new Map(
  Array.from({ length: word(tocStart) }, (_, i): [string, number] => {
    const entry = tocStart + BYTES_PER_WORD + i * TOC_ENTRY;

    return [
      cString(tocStart + word(entry)),
      tocStart + word(entry + BYTES_PER_WORD),
    ];
  }),
);

const PACKAGE = `icudt${MAJOR}l`;

// --- Resource bundles -------------------------------------------------------------

// A value in a bundle, with tables kept in ICU's order.
export type Resource =
  | { t: "string"; value: string }
  | { t: "alias"; path: string }
  | { t: "int"; value: number }
  | { t: "table"; entries: [string, Resource][] }
  | { t: "array"; items: Resource[] }
  | { t: "ints"; values: number[] }
  | { t: "binary"; bytes: Uint8Array }
  | { t: "other" };

// Resource types, from ICU's `uresdata.h`.
const STRING = 0;
const BINARY = 1;
const TABLE = 2;
const ALIAS = 3;
const TABLE32 = 4;
const TABLE16 = 5;
const STRING_V2 = 6;
const INT = 7;
const ARRAY = 8;
const ARRAY16 = 9;
const INT_VECTOR = 14;

const TYPE_SHIFT = 28;
const OFFSET_MASK = 0x0fffffff;
const INT_SIGN_SHIFT = 4;
const HEADER_FORMAT_VERSION = 16;
const FORMAT_VERSION_WITH_POOL_LIMIT = 3;
const INDEX_KEYS_TOP = 2;
const INDEX_ATTRIBUTES = 5;
const ATTRIBUTE_USES_POOL = 4;
const ATTRIBUTE_POOL_LIMIT_MASK = 0xf000;
const ATTRIBUTE_POOL_LIMIT_SHIFT = 12;
const ATTRIBUTE_POOL_16_SHIFT = 16;
const INDEX_LENGTH_MASK = 0xff;
const POOL_LIMIT_SHIFT = 8;
const KEY_OFFSET_MASK = 0x7fffffff;

// Lengths of UTF-16 strings, from ICU's `uresdata.cpp`.
const LEAD_LENGTH_FIRST = 0xdc00;
const LEAD_LENGTH_SHORT = 0xdfef;
const LEAD_LENGTH_LONG = 0xdfff;
const SHORT_LENGTH_MASK = 0x3ff;
const UNITS_SHIFT = 16;

type Bundle = {
  base: number;
  indexLength: number;
  p16: number;
  usesPool: boolean;
  poolStringLimit: number;
  poolString16Limit: number;
  root: number;
  pool: Bundle | undefined;
};

function openBundle(at: number, pool: Bundle | undefined): Bundle {
  const base = at + unit(at);
  const index = (i: number) => word(base + (1 + i) * BYTES_PER_WORD);
  const indexLength = index(0) & INDEX_LENGTH_MASK;

  const attributes =
    indexLength > INDEX_ATTRIBUTES ? index(INDEX_ATTRIBUTES) : 0;

  const formatVersion = buffer[at + HEADER_FORMAT_VERSION]!;

  const limit =
    formatVersion >= FORMAT_VERSION_WITH_POOL_LIMIT
      ? index(0) >>> POOL_LIMIT_SHIFT
      : 0;

  return {
    base,
    indexLength,
    p16: base + (index(INDEX_KEYS_TOP - 1) << 2),
    usesPool: (attributes & ATTRIBUTE_USES_POOL) !== 0,
    poolStringLimit:
      limit |
      ((attributes & ATTRIBUTE_POOL_LIMIT_MASK) << ATTRIBUTE_POOL_LIMIT_SHIFT),
    poolString16Limit: attributes >>> ATTRIBUTE_POOL_16_SHIFT,
    root: word(base),
    pool,
  };
}

const keysStart = (b: Bundle) => b.base + (1 + b.indexLength) * BYTES_PER_WORD;

function poolKeyLimit(b: Bundle): number {
  const pool = b.pool!;

  return (
    (word(pool.base + INDEX_KEYS_TOP * BYTES_PER_WORD) << 2) -
    (1 + pool.indexLength) * BYTES_PER_WORD
  );
}

function key16(b: Bundle, offset: number): string {
  if (!b.usesPool) {
    return cString(b.base + offset);
  }

  const limit = poolKeyLimit(b);

  return offset < limit
    ? cString(keysStart(b.pool!) + offset)
    : cString(keysStart(b) + offset - limit);
}

const key32 = (b: Bundle, offset: number): string =>
  offset >= 0
    ? cString(b.base + offset)
    : cString(keysStart(b.pool!) + (offset & KEY_OFFSET_MASK));

const zeroUnitFrom = (at: number): number =>
  unit(at) === 0 ? at : zeroUnitFrom(at + BYTES_PER_UNIT);

function utf16(at: number, length: number): string {
  return buffer.toString("utf16le", at, at + length * BYTES_PER_UNIT);
}

function string16(b: Bundle, offset: number): string {
  const at =
    offset < b.poolStringLimit
      ? b.pool!.p16 + offset * BYTES_PER_UNIT
      : b.p16 + (offset - b.poolStringLimit) * BYTES_PER_UNIT;

  const first = unit(at);

  if (first < LEAD_LENGTH_FIRST || first > LEAD_LENGTH_LONG) {
    return utf16(at, (zeroUnitFrom(at) - at) / BYTES_PER_UNIT);
  }

  if (first < LEAD_LENGTH_SHORT) {
    return utf16(at + BYTES_PER_UNIT, first & SHORT_LENGTH_MASK);
  }

  if (first < LEAD_LENGTH_LONG) {
    return utf16(
      at + 2 * BYTES_PER_UNIT,
      ((first - LEAD_LENGTH_SHORT) << UNITS_SHIFT) | unit(at + BYTES_PER_UNIT),
    );
  }

  return utf16(
    at + 3 * BYTES_PER_UNIT,
    (unit(at + BYTES_PER_UNIT) << UNITS_SHIFT) | unit(at + 2 * BYTES_PER_UNIT),
  );
}

function string(b: Bundle, res: number): string {
  const offset = res & OFFSET_MASK;

  if (res >>> TYPE_SHIFT === STRING_V2) {
    return string16(b, offset);
  }

  if (res === 0) {
    return "";
  }

  const at = b.base + offset * BYTES_PER_WORD;

  return utf16(at + BYTES_PER_WORD, view.getInt32(at, true));
}

const from16 = (b: Bundle, r16: number): number =>
  (STRING_V2 << TYPE_SHIFT) |
  (r16 < b.poolString16Limit
    ? r16
    : r16 - b.poolString16Limit + b.poolStringLimit);

function read(b: Bundle, res: number): Resource {
  const type = res >>> TYPE_SHIFT;
  const offset = res & OFFSET_MASK;
  const at = b.base + offset * BYTES_PER_WORD;
  const at16 = b.p16 + offset * BYTES_PER_UNIT;

  switch (type) {
    case STRING:
    case STRING_V2:
      return { t: "string", value: string(b, res) };
    case ALIAS:
      return { t: "alias", path: string(b, offset) };
    case INT:
      return { t: "int", value: (offset << INT_SIGN_SHIFT) >> INT_SIGN_SHIFT };
    case INT_VECTOR:
      return {
        t: "ints",
        values:
          offset === 0
            ? []
            : Array.from({ length: view.getInt32(at, true) }, (_, i) =>
                view.getInt32(at + (1 + i) * BYTES_PER_WORD, true),
              ),
      };
    case BINARY:
      return {
        t: "binary",
        bytes:
          offset === 0
            ? new Uint8Array()
            : buffer.subarray(
                at + BYTES_PER_WORD,
                at + BYTES_PER_WORD + view.getInt32(at, true),
              ),
      };
    case TABLE: {
      if (offset === 0) {
        return { t: "table", entries: [] };
      }

      const n = unit(at);
      const keys = at + BYTES_PER_UNIT;
      const values = keys + n * BYTES_PER_UNIT + ((n + 1) % 2) * BYTES_PER_UNIT;

      return {
        t: "table",
        entries: Array.from({ length: n }, (_, i): [string, Resource] => [
          key16(b, unit(keys + i * BYTES_PER_UNIT)),
          read(b, word(values + i * BYTES_PER_WORD)),
        ]),
      };
    }

    case TABLE16: {
      const n = unit(at16);
      const keys = at16 + BYTES_PER_UNIT;

      return {
        t: "table",
        entries: Array.from({ length: n }, (_, i): [string, Resource] => [
          key16(b, unit(keys + i * BYTES_PER_UNIT)),
          read(b, from16(b, unit(keys + (n + i) * BYTES_PER_UNIT))),
        ]),
      };
    }

    case TABLE32: {
      if (offset === 0) {
        return { t: "table", entries: [] };
      }

      const n = view.getInt32(at, true);
      const keys = at + BYTES_PER_WORD;

      return {
        t: "table",
        entries: Array.from({ length: n }, (_, i): [string, Resource] => [
          key32(b, view.getInt32(keys + i * BYTES_PER_WORD, true)),
          read(b, word(keys + (n + i) * BYTES_PER_WORD)),
        ]),
      };
    }

    case ARRAY: {
      if (offset === 0) {
        return { t: "array", items: [] };
      }

      return {
        t: "array",
        items: Array.from({ length: view.getInt32(at, true) }, (_, i) =>
          read(b, word(at + (1 + i) * BYTES_PER_WORD)),
        ),
      };
    }

    case ARRAY16:
      return {
        t: "array",
        items: Array.from({ length: unit(at16) }, (_, i) =>
          read(b, from16(b, unit(at16 + (1 + i) * BYTES_PER_UNIT))),
        ),
      };
    default:
      throw new Error(`Unknown resource type ${type}`);
  }
}

// Each folder of bundles, like `zone/`, shares strings through its own pool.
const pools = new Map<string, Bundle | undefined>();

function poolFor(name: string): Bundle | undefined {
  const folder = name.slice(0, name.lastIndexOf("/") + 1);

  if (pools.has(folder)) {
    return pools.get(folder);
  }

  const at = toc.get(`${PACKAGE}/${folder}pool.res`);
  const pool = at === undefined ? undefined : openBundle(at, undefined);
  pools.set(folder, pool);

  return pool;
}

const bundles = new Map<string, Resource | undefined>();

// The names of the bundles in a folder, like `zone/en_GB` in `zone/`.
export const bundlesIn = (folder: string): string[] =>
  [...toc.keys()].flatMap((key) => {
    const name = key.slice(PACKAGE.length + 1, -".res".length);
    const rest = name.slice(folder.length);

    return key.startsWith(`${PACKAGE}/${folder}`) &&
      key.endsWith(".res") &&
      rest !== "pool" &&
      !rest.includes("/")
      ? [name]
      : [];
  });

// A locale's bundle, like `en_GB`, or undefined if ICU has none.
function bundle(name: string): Resource | undefined {
  if (bundles.has(name)) {
    return bundles.get(name);
  }

  const at = toc.get(`${PACKAGE}/${name}.res`);
  const opened = at === undefined ? undefined : openBundle(at, poolFor(name));
  const resource = opened === undefined ? undefined : read(opened, opened.root);
  bundles.set(name, resource);

  return resource;
}

export const child = (r: Resource | undefined, key: string) =>
  r?.t === "table" ? r.entries.find(([k]) => k === key)?.[1] : undefined;

const stringChild = (r: Resource | undefined, key: string) => {
  const found = child(r, key);

  return found?.t === "string" ? found.value : undefined;
};

// --- Fallback ---------------------------------------------------------------------

const ROOT = "root";

// The bundles ICU looks in for a locale, most specific first, ending with
// root. It follows `%%ALIAS` and `%%Parent`. Otherwise, in the main folder a
// missing locale drops its last part, which is how Intl picks a locale ICU
// has. In other folders, like `zone/`, ICU's own rules pick the parent.
export function chain(name: string, folder = "", original = name): string[] {
  const b = bundle(folder + name);
  const alias = stringChild(b, "%%ALIAS");

  if (b !== undefined && alias !== undefined) {
    return chain(alias, folder, original);
  }

  if (name === ROOT) {
    return [folder + ROOT];
  }

  const cut = name.lastIndexOf("_");

  const parent =
    stringChild(b, "%%Parent") ??
    (b === undefined && folder !== ""
      ? icuParent(name, original)
      : undefined) ??
    (cut < 0 ? ROOT : name.slice(0, cut));

  return b === undefined
    ? chain(parent, folder, original)
    : [folder + name, ...chain(parent, folder, original)];
}

const LATIN = "Latn";

// A language's default script in a region, like ICU's `getDefaultScript`.
const defaultScript = (language: string, region: string | undefined) =>
  (region === undefined
    ? undefined
    : defaultScripts.get(`${language}_${region}`)) ??
  defaultScripts.get(language) ??
  LATIN;

const SCRIPT = /^[A-Z][a-z]{3}$/;

// ICU's `getParentLocaleID`: the parent of a locale with no bundle. It
// keeps whichever of the script and the region says more, so `sr_Cyrl_ME`,
// whose script is Serbian's default, falls back to `sr_ME`. `original` is the
// locale first asked for.
function icuParent(name: string, original: string): string | undefined {
  const explicit = parentLocales.get(name);

  if (explicit !== undefined) {
    return explicit;
  }

  const [language, ...rest] = name.split("_");
  const script = rest.find((part) => SCRIPT.test(part));
  const region = rest.find((part) => !SCRIPT.test(part));

  if (language === undefined || rest.length > (script === undefined ? 1 : 2)) {
    return undefined;
  }

  if (script !== undefined && region !== undefined) {
    return defaultScript(language, region) === script
      ? `${language}_${region}`
      : `${language}_${script}`;
  }

  if (region !== undefined) {
    const originalScript = original
      .split("_")
      .find((part) => SCRIPT.test(part));

    return `${language}_${originalScript ?? defaultScript(language, region)}`;
  }

  if (script !== undefined) {
    return defaultScript(language, undefined) === script ? language : undefined;
  }

  return undefined;
}

// Where ICU found a resource: the bundles from the one holding it, and its
// path there once aliases are followed.
type Found = { resource: Resource; from: string[]; path: string[] };

const LOCALE_ALIAS = "/LOCALE/";
const ICUDATA_ALIAS = "/ICUDATA/";

// Like ICU's `ures_getByKeyWithFallback`. `requested` is the chain that
// `/LOCALE/` aliases start again from.
function find(
  bundles: string[],
  path: string[],
  requested: string[] = bundles,
): Found | undefined {
  const [first, ...rest] = bundles;

  if (first === undefined) {
    return undefined;
  }

  const walk = (r: Resource | undefined, i: number): Found | undefined => {
    if (r === undefined) {
      return undefined;
    }

    if (r.t === "alias") {
      const remaining = path.slice(i);

      if (r.path.startsWith(LOCALE_ALIAS)) {
        return find(requested, [
          ...r.path.slice(LOCALE_ALIAS.length).split("/"),
          ...remaining,
        ]);
      }

      const [locale, ...aliasPath] = r.path
        .replace(ICUDATA_ALIAS, "")
        .split("/");

      return find(chain(locale!), [...aliasPath, ...remaining].filter(Boolean));
    }

    if (i === path.length) {
      return { resource: r, from: bundles, path };
    }

    return walk(child(r, path[i]!), i + 1);
  };

  return walk(bundle(first), 0) ?? find(rest, path, requested);
}

// Looks for a resource in `bundles`. A `/LOCALE/` alias starts again from
// `requested`.
export const lookup = (
  bundles: string[],
  path: string[],
  requested: string[] = bundles,
) => find(bundles, path, requested)?.resource;

export const locate = (bundles: string[], path: string[]) =>
  find(bundles, path);

// Like ICU's `ures_getAllChildrenWithFallback`: each child of a table, from
// the bundle ICU finds it in and then each of that one's parents. A key can
// come more than once, most specific first.
//
// A `/LOCALE/` alias in a parent starts again from the requested locale.
export function everyChild(
  bundles: string[],
  path: string[],
  requested: string[] = bundles,
): [string, Resource][] {
  const found = find(bundles, path, requested);

  if (found === undefined) {
    return [];
  }

  const [, ...parents] = found.from;
  const here = found.resource.t === "table" ? found.resource.entries : [];

  return [...here, ...everyChild(parents, found.path, requested)];
}

// Each child once, with its most specific value.
export const allChildren = (bundles: string[], path: string[]) =>
  everyChild(bundles, path).filter(
    ([key], i, all) => all.findIndex(([k]) => k === key) === i,
  );

// ICU's bundle name for a BCP 47 tag.
export const bundleName = (tag: string) => tag.replaceAll("-", "_");
