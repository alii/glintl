// This module copies ICU's DateTimePatternGenerator, which picks a pattern for
// some fields. It also copies the way JavaScriptCore calls it.
// `src/glintl/internal/matcher.gleam` does the same on Erlang, and the
// generator checks both against Intl.

// Fields, in ICU's `UDateTimePatternField` order.
export const ERA = 0;
export const YEAR = 1;
const QUARTER = 2;
export const MONTH = 3;
const WEEK_OF_YEAR = 4;
const WEEK_OF_MONTH = 5;
export const WEEKDAY = 6;
const DAY_OF_YEAR = 7;
const DAY_OF_WEEK_IN_MONTH = 8;
export const DAY = 9;
export const DAY_PERIOD = 10;
export const HOUR = 11;
export const MINUTE = 12;
export const SECOND = 13;
export const FRACTIONAL_SECOND = 14;
export const ZONE = 15;
export const FIELD_COUNT = 16;

const FIELDS = Array.from({ length: FIELD_COUNT }, (_, i) => i);

// What each kind of difference between fields costs, from ICU's
// `dtptngen_impl.h`.
const NONE = 0;
const EXTRA_FIELD = 0x10000;
const MISSING_FIELD = 0x1000;
const NARROW = -0x101;
const SHORTER = -0x102;
const SHORT = -0x103;
const LONG = -0x104;
const NUMERIC = 0x100;
const DELTA = 0x10;

const FIX_FRACTIONAL_SECONDS = 1;
const USES_CAP_J = 2;

// JavaScriptCore asks ICU to give hours the requested length, but minutes
// and seconds keep the pattern's.
const MATCH_LENGTH = 1 << HOUR;

const FRACTIONAL_MASK = 1 << FRACTIONAL_SECOND;
const SECOND_AND_FRACTIONAL_MASK = (1 << SECOND) | FRACTIONAL_MASK;
const DATE_MASK = (1 << DAY_PERIOD) - 1;
const TIME_MASK = (1 << FIELD_COUNT) - 1 - DATE_MASK;

type Row = { letter: string; field: number; type: number; minLength: number };

const row = (
  letter: string,
  field: number,
  type: number,
  minLength: number,
): Row => ({ letter, field, type, minLength });

// ICU's `dtTypes`: each pattern letter, its field, and how it compares.
const ROWS: Row[] = [
  row("G", ERA, SHORT, 1),
  row("G", ERA, LONG, 4),
  row("G", ERA, NARROW, 5),
  row("y", YEAR, NUMERIC, 1),
  row("Y", YEAR, NUMERIC + DELTA, 1),
  row("u", YEAR, NUMERIC + 2 * DELTA, 1),
  row("r", YEAR, NUMERIC + 3 * DELTA, 1),
  row("U", YEAR, SHORT, 1),
  row("U", YEAR, LONG, 4),
  row("U", YEAR, NARROW, 5),
  row("Q", QUARTER, NUMERIC, 1),
  row("Q", QUARTER, SHORT, 3),
  row("Q", QUARTER, LONG, 4),
  row("Q", QUARTER, NARROW, 5),
  row("q", QUARTER, NUMERIC + DELTA, 1),
  row("q", QUARTER, SHORT - DELTA, 3),
  row("q", QUARTER, LONG - DELTA, 4),
  row("q", QUARTER, NARROW - DELTA, 5),
  row("M", MONTH, NUMERIC, 1),
  row("M", MONTH, SHORT, 3),
  row("M", MONTH, LONG, 4),
  row("M", MONTH, NARROW, 5),
  row("L", MONTH, NUMERIC + DELTA, 1),
  row("L", MONTH, SHORT - DELTA, 3),
  row("L", MONTH, LONG - DELTA, 4),
  row("L", MONTH, NARROW - DELTA, 5),
  row("l", MONTH, NUMERIC + DELTA, 1),
  row("w", WEEK_OF_YEAR, NUMERIC, 1),
  row("W", WEEK_OF_MONTH, NUMERIC, 1),
  row("E", WEEKDAY, SHORT, 1),
  row("E", WEEKDAY, LONG, 4),
  row("E", WEEKDAY, NARROW, 5),
  row("E", WEEKDAY, SHORTER, 6),
  row("c", WEEKDAY, NUMERIC + 2 * DELTA, 1),
  row("c", WEEKDAY, SHORT - 2 * DELTA, 3),
  row("c", WEEKDAY, LONG - 2 * DELTA, 4),
  row("c", WEEKDAY, NARROW - 2 * DELTA, 5),
  row("c", WEEKDAY, SHORTER - 2 * DELTA, 6),
  row("e", WEEKDAY, NUMERIC + DELTA, 1),
  row("e", WEEKDAY, SHORT - DELTA, 3),
  row("e", WEEKDAY, LONG - DELTA, 4),
  row("e", WEEKDAY, NARROW - DELTA, 5),
  row("e", WEEKDAY, SHORTER - DELTA, 6),
  row("d", DAY, NUMERIC, 1),
  row("d", DAY, SHORT, 3),
  row("g", DAY, NUMERIC + DELTA, 1),
  row("D", DAY_OF_YEAR, NUMERIC, 1),
  row("F", DAY_OF_WEEK_IN_MONTH, NUMERIC, 1),
  row("a", DAY_PERIOD, SHORT, 1),
  row("a", DAY_PERIOD, LONG, 4),
  row("a", DAY_PERIOD, NARROW, 5),
  row("b", DAY_PERIOD, SHORT - DELTA, 1),
  row("b", DAY_PERIOD, LONG - DELTA, 4),
  row("b", DAY_PERIOD, NARROW - DELTA, 5),
  row("B", DAY_PERIOD, SHORT - 3 * DELTA, 1),
  row("B", DAY_PERIOD, LONG - 3 * DELTA, 4),
  row("B", DAY_PERIOD, NARROW - 3 * DELTA, 5),
  row("H", HOUR, NUMERIC + 10 * DELTA, 1),
  row("k", HOUR, NUMERIC + 11 * DELTA, 1),
  row("h", HOUR, NUMERIC, 1),
  row("K", HOUR, NUMERIC + DELTA, 1),
  row("J", HOUR, NUMERIC + 5 * DELTA, 1),
  row("j", HOUR, NUMERIC + 6 * DELTA, 1),
  row("C", HOUR, NUMERIC + 7 * DELTA, 1),
  row("m", MINUTE, NUMERIC, 1),
  row("s", SECOND, NUMERIC, 1),
  row("A", SECOND, NUMERIC + DELTA, 1),
  row("S", FRACTIONAL_SECOND, NUMERIC, 1),
  row("v", ZONE, SHORT - 2 * DELTA, 1),
  row("v", ZONE, LONG - 2 * DELTA, 4),
  row("z", ZONE, SHORT, 1),
  row("z", ZONE, LONG, 4),
  row("Z", ZONE, NARROW - DELTA, 1),
  row("Z", ZONE, LONG - DELTA, 4),
  row("Z", ZONE, SHORT - DELTA, 5),
  row("O", ZONE, SHORT - DELTA, 1),
  row("O", ZONE, LONG - DELTA, 4),
  row("V", ZONE, SHORT - DELTA, 1),
  row("V", ZONE, LONG - DELTA, 2),
  row("V", ZONE, LONG - 1 - DELTA, 3),
  row("V", ZONE, LONG - 2 - DELTA, 4),
  row("X", ZONE, NARROW - DELTA, 1),
  row("X", ZONE, SHORT - DELTA, 2),
  row("X", ZONE, LONG - DELTA, 4),
  row("x", ZONE, NARROW - DELTA, 1),
  row("x", ZONE, SHORT - DELTA, 2),
  row("x", ZONE, LONG - DELTA, 4),
];

// ICU's `Canonical_Items`, one pattern for each field.
const CANONICAL_ITEMS = [
  "G",
  "y",
  "Q",
  "M",
  "w",
  "W",
  "E",
  "D",
  "F",
  "d",
  "a",
  "H",
  "m",
  "s",
  "S",
  "v",
];

// The CLDR names of fields, for append items and display names.
export const APPEND_ITEM_KEYS = [
  "Era",
  "Year",
  "Quarter",
  "Month",
  "Week",
  "*",
  "Day-Of-Week",
  "*",
  "*",
  "Day",
  "*",
  "Hour",
  "Minute",
  "Second",
  "*",
  "Timezone",
];

export const DISPLAY_NAME_KEYS = [
  "era",
  "year",
  "quarter",
  "month",
  "week",
  "weekOfMonth",
  "weekday",
  "dayOfYear",
  "weekdayOfMonth",
  "day",
  "dayperiod",
  "hour",
  "minute",
  "second",
  "*",
  "zone",
];

export const DEFAULT_APPEND_ITEM = "{0} ├{2}: {1}┤";

const QUOTE = "'";
const SEPARATORS = "'\\ :\",-";
const DOT = ".";

// ICU's `FormatParser` keeps only this many items of a pattern.
const MAX_ITEMS = 50;

// Splits a pattern into runs of one letter and single other characters.
function items(pattern: string): string[] {
  const runs = pattern.match(/([A-Za-z])\1*|[^]/gu) ?? [];

  return runs.slice(0, MAX_ITEMS);
}

// Joins a quoted run starting at item `i`, quotes and all. Returns it and the
// index of its last item, like ICU's `getQuoteLiteral`.
function quoteLiteral(list: string[], i: number): [string, number] {
  const start = list[i]![0] === QUOTE ? i + 1 : i;
  const head = list[i]![0] === QUOTE ? list[i]! : "";

  const go = (j: number, text: string): [string, number] => {
    if (j >= list.length) {
      return [text, j];
    }

    const item = list[j]!;

    if (item[0] !== QUOTE) {
      return go(j + 1, text + item);
    }

    if (j + 1 < list.length && list[j + 1]![0] === QUOTE) {
      return go(j + 2, text + item + list[j + 1]!);
    }

    return [text + item, j];
  };

  return go(start, head);
}

// Whether a field holds only separators. Like ICU, the check looks for a dot
// in the item at each character's index, not in the character itself.
const isSeparator = (field: string, list: string[]) =>
  [...field].every((c, i) => SEPARATORS.includes(c) || list[i]?.[0] === DOT);

// A pattern letter's field, like ERA or MONTH.
export function fieldOf(letter: string): number {
  const found = ROWS.find((r) => r.letter === letter);

  if (found === undefined) {
    throw new Error(`${letter} isn't a pattern letter`);
  }

  return found.field;
}

function canonicalIndex(s: string): number {
  const letter = s[0];

  if (letter === undefined || [...s].some((c) => c !== letter)) {
    return -1;
  }

  const first = ROWS.findIndex((r) => r.letter === letter);

  if (first < 0) {
    return -1;
  }

  const last = ROWS.findLastIndex((r) => r.letter === letter);

  const longest = ROWS.slice(first, last + 1).findLastIndex(
    (r) => r.minLength <= s.length,
  );

  return first + Math.max(longest, 0);
}

type Fields = { letters: string[]; lengths: number[] };

export type Skeleton = {
  type: number[];
  original: Fields;
  base: Fields;
};

const fieldsText = (f: Fields) =>
  FIELDS.map((i) => f.letters[i]!.repeat(f.lengths[i]!)).join("");

export const skeletonText = (s: Skeleton) => fieldsText(s.original);

const set = <T>(list: T[], i: number, value: T) =>
  list.map((old, j) => (j === i ? value : old));

function withField(
  s: Skeleton,
  field: number,
  letter: string,
  length: number,
  baseLetter: string,
  baseLength: number,
  type: number,
): Skeleton {
  return {
    type: set(s.type, field, type),
    original: {
      letters: set(s.original.letters, field, letter),
      lengths: set(s.original.lengths, field, length),
    },
    base: {
      letters: set(s.base.letters, field, baseLetter),
      lengths: set(s.base.lengths, field, baseLength),
    },
  };
}

const emptyFields = (): Fields => ({
  letters: FIELDS.map(() => ""),
  lengths: FIELDS.map(() => 0),
});

const EMPTY: Skeleton = {
  type: FIELDS.map(() => NONE),
  original: emptyFields(),
  base: emptyFields(),
};

const has = (s: Skeleton, field: number) => s.original.lengths[field]! > 0;

// Like ICU's `DateTimeMatcher::set`.
export function skeleton(pattern: string): Skeleton {
  const list = items(pattern);

  const walk = (i: number, s: Skeleton): Skeleton => {
    if (i >= list.length) {
      return s;
    }

    const item = list[i]!;

    if (item[0] === QUOTE) {
      return walk(quoteLiteral(list, i)[1] + 1, s);
    }

    const index = canonicalIndex(item);

    if (index < 0) {
      return walk(i + 1, s);
    }

    const r = ROWS[index]!;
    const type = r.type > 0 ? r.type + item.length : r.type;

    return walk(
      i + 1,
      withField(s, r.field, item[0]!, item.length, r.letter, r.minLength, type),
    );
  };

  const parsed = walk(0, EMPTY);

  // ICU-20739: minutes and fractions of a second need seconds.
  const withSeconds =
    has(parsed, MINUTE) &&
    has(parsed, FRACTIONAL_SECOND) &&
    !has(parsed, SECOND)
      ? withField(parsed, SECOND, "s", 1, "s", 1, NUMERIC + 1)
      : parsed;

  if (!has(withSeconds, HOUR)) {
    return withSeconds;
  }

  // ICU-13183: a 12 hour clock needs a day period, and others have none.
  const hour = withSeconds.original.letters[HOUR];

  if (hour === "h" || hour === "K") {
    return has(withSeconds, DAY_PERIOD)
      ? withSeconds
      : withField(withSeconds, DAY_PERIOD, "a", 1, "a", 1, SHORT);
  }

  return withField(withSeconds, DAY_PERIOD, "", 0, "", 0, NONE);
}

type Distance = { distance: number; missing: number; extra: number };

function distance(want: Skeleton, other: Skeleton, mask: number): Distance {
  return FIELDS.reduce<Distance>(
    (d, i) => {
      const mine = (mask & (1 << i)) === 0 ? NONE : want.type[i]!;
      const theirs = other.type[i]!;

      if (mine === theirs) {
        return d;
      }

      if (mine === NONE) {
        return {
          distance: d.distance + EXTRA_FIELD,
          missing: d.missing,
          extra: d.extra | (1 << i),
        };
      }

      if (theirs === NONE) {
        return {
          distance: d.distance + MISSING_FIELD,
          missing: d.missing | (1 << i),
          extra: d.extra,
        };
      }

      return {
        distance: d.distance + Math.abs(mine - theirs),
        missing: d.missing,
        extra: d.extra,
      };
    },
    { distance: 0, missing: 0, extra: 0 },
  );
}

const fieldMask = (s: Skeleton) =>
  FIELDS.reduce((m, i) => (s.type[i] === NONE ? m : m | (1 << i)), 0);

// A stored pattern, with the skeleton it's stored under. `specified` is true
// when CLDR gave the skeleton, and false when ICU worked it out.
export type Entry = {
  skeleton: Skeleton;
  pattern: string;
  specified: boolean;
};

const baseText = (s: Skeleton) => fieldsText(s.base);

// ICU keeps patterns in lists by the first letter of their base, A to Z then
// a to z.
const LETTERS = [
  ..."ABCDEFGHIJKLMNOPQRSTUVWXYZ",
  ..."abcdefghijklmnopqrstuvwxyz",
];

const letterIndex = (s: Skeleton) => LETTERS.indexOf(baseText(s)[0] ?? "");

const sameType = (a: Skeleton, b: Skeleton) =>
  a.type.every((t, i) => t === b.type[i]);

// Like ICU's `addPatternWithOptionalSkeleton`.
function add(
  map: Entry[],
  pattern: string,
  given: string | undefined,
  override: boolean,
): Entry[] {
  const s = skeleton(given ?? pattern);

  if (letterIndex(s) < 0) {
    return map;
  }

  const base = baseText(s);
  const sameBase = map.find((e) => baseText(e.skeleton) === base);

  if (
    sameBase &&
    (!sameBase.specified || (given !== undefined && !override)) &&
    !override
  ) {
    return map;
  }

  const sameSkeleton = map.find(
    (e) => skeletonText(e.skeleton) === skeletonText(s),
  );

  if (
    sameSkeleton &&
    (!override || (given !== undefined && sameSkeleton.specified))
  ) {
    return map;
  }

  const specified = given !== undefined;

  const duplicate = map.findIndex(
    (e) => baseText(e.skeleton) === base && sameType(e.skeleton, s),
  );

  // ICU keeps a duplicate's old skeleton.
  return duplicate < 0
    ? [...map, { skeleton: s, pattern, specified }]
    : set(map, duplicate, { ...map[duplicate]!, pattern, specified });
}

// The data ICU's generator reads for a locale and calendar.
export type MatcherData = {
  // DateTimePatterns: times from full to short, then dates.
  standard: string[];
  // availableFormats, in ICU's order, with their skeletons.
  available: [string, string][];
  appendItems: string[];
  displayNames: string[];
  // How to join a date and a time, from full to short.
  glues: string[];
  defaultHourLetter: string;
  decimal: string;
};

export type Matcher = {
  entries: Entry[];
  appendItems: string[];
  displayNames: string[];
  glues: string[];
  defaultHourLetter: string;
  decimal: string;
};

// Builds ICU's list of patterns, in the order it searches them.
export function matcher(data: MatcherData): Matcher {
  const firstAvailable = data.available.filter(
    ([key], i) => data.available.findIndex(([k]) => k === key) === i,
  );

  const map = [
    ...CANONICAL_ITEMS.map((p): [string, string | undefined, boolean] => [
      p,
      undefined,
      false,
    ]),
    ...data.standard.map((p): [string, string | undefined, boolean] => [
      p,
      undefined,
      false,
    ]),
    ...firstAvailable.map(([key, p]): [string, string | undefined, boolean] => [
      p,
      key,
      true,
    ]),
  ].reduce<Entry[]>(
    (m, [pattern, given, override]) => add(m, pattern, given, override),
    [],
  );

  const entries = LETTERS.flatMap((_, i) =>
    map.filter((e) => letterIndex(e.skeleton) === i),
  );

  return {
    entries,
    appendItems: data.appendItems,
    displayNames: data.displayNames,
    glues: data.glues,
    defaultHourLetter: data.defaultHourLetter,
    decimal: data.decimal,
  };
}

type Best = { entry: Entry; missing: number; extra: number };

// Like ICU's `getBestRaw`, finds the closest pattern. On a tie it prefers the
// pattern whose missing fields are less significant.
function best(m: Matcher, want: Skeleton, mask: number): Best {
  type Search = Best & { distance: number };

  const found = m.entries.reduce<Search | undefined>((so, entry) => {
    if (so?.distance === 0) {
      return so;
    }

    const d = distance(want, entry.skeleton, mask);

    if (
      so === undefined ||
      d.distance < so.distance ||
      (d.distance === so.distance && so.missing < d.missing)
    ) {
      return { entry, ...d };
    }

    return so;
  }, undefined);

  if (found === undefined) {
    throw new Error("A matcher has no patterns");
  }

  return found;
}

const DATE_FIELDS_KEEP_PATTERN_LETTER = [HOUR, MONTH, WEEKDAY];

// Like ICU's `adjustFieldTypes`: gives the pattern's fields the requested
// lengths.
function adjust(
  m: Matcher,
  pattern: string,
  specified: Skeleton | undefined,
  want: Skeleton,
  flags: number,
): string {
  const list = items(pattern);

  const field = (item: string): string => {
    const index = canonicalIndex(item);

    if (index < 0) {
      return item;
    }

    const r = ROWS[index]!;
    const f = r.field;

    if ((flags & FIX_FRACTIONAL_SECONDS) !== 0 && f === SECOND) {
      return (
        item +
        m.decimal +
        want.original.letters[FRACTIONAL_SECOND]!.repeat(
          want.original.lengths[FRACTIONAL_SECOND]!,
        )
      );
    }

    if (want.type[f] === NONE) {
      return item;
    }

    const wantLetter = want.original.letters[f]!;
    const wantLength = want.original.lengths[f]!;
    const requested = wantLetter === "E" && wantLength < 3 ? 3 : wantLength;

    const unmatched =
      [HOUR, MINUTE, SECOND].includes(f) && (MATCH_LENGTH & (1 << f)) === 0;

    const keepLength =
      unmatched ||
      (specified !== undefined &&
        wantLetter !== "c" &&
        wantLetter !== "e" &&
        (specified.original.lengths[f] === requested ||
          r.type > 0 !== want.type[f]! > 0));

    const length = keepLength ? item.length : requested;

    const letter =
      DATE_FIELDS_KEEP_PATTERN_LETTER.includes(f) ||
      (f === YEAR && wantLetter !== "Y")
        ? item[0]!
        : wantLetter;

    const named = letter === "E" && length < 3 ? "e" : letter;

    return hourLetter(m, f, named, wantLetter, flags).repeat(length);
  };

  const walk = (i: number, out: string): string => {
    if (i >= list.length) {
      return out;
    }

    const item = list[i]!;

    if (item[0] === QUOTE) {
      const [text, last] = quoteLiteral(list, i);

      return walk(last + 1, out + text);
    }

    if (isSeparator(item, list)) {
      return walk(i + 1, out + item);
    }

    return walk(i + 1, out + field(item));
  };

  return walk(0, "");
}

// Picks the hour letter to write from the requested one and the locale's.
const HOUR_SWAPS = [
  ["h", "K", "K"],
  ["H", "k", "k"],
  ["k", "H", "H"],
  ["K", "h", "h"],
] as const;

// ICU matches the hour letter to the locale's hour cycle.
function hourLetter(
  m: Matcher,
  field: number,
  letter: string,
  wanted: string,
  flags: number,
): string {
  const d = m.defaultHourLetter;

  if (field !== HOUR) {
    return letter;
  }

  if ((flags & USES_CAP_J) !== 0 || wanted === d) {
    return d;
  }

  const swap = HOUR_SWAPS.find(
    ([from, locale]) => from === wanted && locale === d,
  );

  return swap?.[2] ?? letter;
}

// Like ICU's `mapSkeletonMetacharacters`, for the `j` JavaScriptCore uses.
// Like ICU, it drops quoted text.
function mapMetacharacters(m: Matcher, form: string): string {
  const runs = form.replace(/'[^']*'?/gu, "").match(/(.)\1*/gu) ?? [];

  return runs
    .map((run) => {
      if (run[0] !== "j") {
        return run;
      }

      const extra = run.length - 1;
      const hourLength = 1 + (extra & 1);
      const periodLength = extra < 2 ? 1 : 3 + (extra >> 1);
      const hour = m.defaultHourLetter;
      const period = hour === "H" || hour === "k" ? 0 : periodLength;

      return "a".repeat(period) + hour.repeat(hourLength);
    })
    .join("");
}

const HIGHEST_BIT = 31;

// ICU reads before the start of its append items when there are no fields, so
// `topBit` throws instead.
function topBit(mask: number): number {
  if (mask === 0) {
    throw new Error("A pattern was appended for no fields");
  }

  return Math.min(HIGHEST_BIT - Math.clz32(mask), ZONE);
}

// Like ICU's `getBestAppending`: finds patterns for the fields in `mask`,
// joining any missing ones on with append items.
function appending(
  m: Matcher,
  want: Skeleton,
  mask: number,
  flags: number,
): string {
  if (mask === 0) {
    return "";
  }

  const first = best(m, want, mask);

  const specified = (b: Best) =>
    b.entry.specified ? b.entry.skeleton : undefined;

  const start = adjust(m, first.entry.pattern, specified(first), want, flags);

  type Step = {
    result: string;
    missing: number;
    last: number;
    specified: Skeleton | undefined;
  };

  const go = (s: Step): string => {
    if (s.missing === 0 || s.last === s.missing) {
      return s.result;
    }

    if (
      (s.missing & SECOND_AND_FRACTIONAL_MASK) === FRACTIONAL_MASK &&
      (mask & SECOND_AND_FRACTIONAL_MASK) === SECOND_AND_FRACTIONAL_MASK
    ) {
      return go({
        result: adjust(
          m,
          s.result,
          s.specified,
          want,
          flags | FIX_FRACTIONAL_SECONDS,
        ),
        missing: s.missing & ~FRACTIONAL_MASK,
        last: s.last,
        specified: s.specified,
      });
    }

    const next = best(m, want, s.missing);
    const found = s.missing & ~next.missing;
    const top = topBit(found);
    const piece = adjust(m, next.entry.pattern, specified(next), want, flags);
    const format = m.appendItems[top]!;

    const result =
      format.length === 0
        ? s.result
        : simpleFormat(format, [s.result, piece, `'${m.displayNames[top]}'`]);

    return go({
      result,
      missing: next.missing,
      last: next.missing,
      specified: specified(next),
    });
  };

  return go({
    result: start,
    missing: first.missing,
    last: 0,
    specified: specified(first),
  });
}

// Like ICU's `SimpleFormatter`: fills in `{0}` and so on. An apostrophe
// quotes braces, and two make one.
export function simpleFormat(pattern: string, args: string[]): string {
  const walk = (i: number, quoted: boolean, out: string): string => {
    if (i >= pattern.length) {
      return out;
    }

    const c = pattern[i]!;
    const next = pattern[i + 1];

    if (c === QUOTE) {
      if (next === QUOTE) {
        return walk(i + 2, quoted, out + QUOTE);
      }

      if (quoted) {
        return walk(i + 1, false, out);
      }

      if (next === "{" || next === "}") {
        return walk(i + 1, true, out);
      }

      return walk(i + 1, quoted, out + QUOTE);
    }

    const argument = quoted ? null : /^\{(\d+)\}/u.exec(pattern.slice(i));

    if (argument) {
      return walk(
        i + argument[0].length,
        quoted,
        out + (args[Number(argument[1])] ?? ""),
      );
    }

    return walk(i + 1, quoted, out + c);
  };

  return walk(0, false, "");
}

const FULL = 0;
const LONG_STYLE = 1;
const MEDIUM = 2;
const SHORT_STYLE = 3;
const LONG_MONTH = 4;
const SHORT_MONTH = 3;

// Like ICU's `getBestPattern`.
export function bestPattern(m: Matcher, form: string): string {
  const want = skeleton(mapMetacharacters(m, form));
  const raw = best(m, want, -1);
  const specified = raw.entry.specified ? raw.entry.skeleton : undefined;

  if (raw.missing === 0 && raw.extra === 0) {
    return adjust(m, raw.entry.pattern, specified, want, 0);
  }

  const needed = fieldMask(want);
  const date = appending(m, want, needed & DATE_MASK, 0);
  const time = appending(m, want, needed & TIME_MASK, 0);

  if (date.length === 0) {
    return time;
  }

  if (time.length === 0) {
    return date;
  }

  const month = want.base.lengths[MONTH];

  const style =
    month === LONG_MONTH
      ? want.base.lengths[WEEKDAY]! > 0
        ? FULL
        : LONG_STYLE
      : month === SHORT_MONTH
        ? MEDIUM
        : SHORT_STYLE;

  return simpleFormat(m.glues[style]!, [time, date]);
}

// --- JavaScriptCore -----------------------------------------------------------------

export type Width = "narrow" | "short" | "long";

export type Digits = "numeric" | "2-digit";

export type ZoneName =
  | "short"
  | "long"
  | "shortOffset"
  | "longOffset"
  | "shortGeneric"
  | "longGeneric";

export type Cycle = "h11" | "h12" | "h23" | "h24";

// Intl's options for fields.
export type FieldOptions = {
  weekday?: Width;
  era?: Width;
  year?: Digits;
  month?: Digits | Width;
  day?: Digits;
  dayPeriod?: Width;
  hour?: Digits;
  minute?: Digits;
  second?: Digits;
  fractionalSecondDigits?: 1 | 2 | 3;
  timeZoneName?: ZoneName;
  hourCycle?: Cycle;
};

const NAMES: Record<Width, number> = { narrow: 5, short: 3, long: 4 };
const NUMBERS: Record<Digits, number> = { numeric: 1, "2-digit": 2 };

// JavaScriptCore asks for a short day period with one letter.
const DAY_PERIODS: Record<Width, number> = { narrow: 5, short: 1, long: 4 };

const ZONE_LETTERS: Record<ZoneName, string> = {
  short: "z",
  long: "zzzz",
  shortOffset: "O",
  longOffset: "OOOO",
  shortGeneric: "v",
  longGeneric: "vvvv",
};

const isDigits = (w: Digits | Width): w is Digits =>
  w === "numeric" || w === "2-digit";

const repeat = <T extends string>(
  letter: string,
  w: T | undefined,
  lengths: Record<T, number>,
) => (w === undefined ? "" : letter.repeat(lengths[w]));

// JavaScriptCore's `buildSkeleton`, without defaults.
export function jscSkeleton(o: FieldOptions): string {
  const hourLetter =
    o.hourCycle === undefined
      ? "j"
      : o.hourCycle === "h11" || o.hourCycle === "h12"
        ? "h"
        : "H";

  const month =
    o.month === undefined
      ? ""
      : isDigits(o.month)
        ? repeat("M", o.month, NUMBERS)
        : repeat("M", o.month, NAMES);

  return [
    repeat("E", o.weekday, NAMES),
    repeat("G", o.era, NAMES),
    repeat("y", o.year, NUMBERS),
    month,
    repeat("d", o.day, NUMBERS),
    repeat(hourLetter, o.hour, NUMBERS),
    repeat("B", o.dayPeriod, DAY_PERIODS),
    repeat("m", o.minute, NUMBERS),
    repeat("s", o.second, NUMBERS),
    "S".repeat(o.fractionalSecondDigits ?? 0),
    o.timeZoneName === undefined ? "" : ZONE_LETTERS[o.timeZoneName],
  ].join("");
}

const HOUR_LETTERS = "hHkK";

const CYCLE_LETTERS: Record<Cycle, string> = {
  h11: "K",
  h12: "h",
  h23: "H",
  h24: "k",
};

// JavaScriptCore's `replaceHourCycleInPattern`: uses the hour cycle's letter,
// and makes a lone 12 hour letter two long for a 24 hour clock.
export function replaceHourCycle(
  pattern: string,
  cycle: Cycle | undefined,
): string {
  if (cycle === undefined) {
    return pattern;
  }

  const to = CYCLE_LETTERS[cycle];
  const to24 = cycle === "h23" || cycle === "h24";
  const chars = [...pattern];

  const walk = (i: number, out: string[]): string[] => {
    if (i >= chars.length) {
      return out;
    }

    const c = chars[i]!;

    if (c === QUOTE) {
      const close = chars.indexOf(QUOTE, i + 1);

      const end =
        i + 1 >= chars.length
          ? chars.length
          : close < 0
            ? chars.length
            : close + 1;

      return walk(end, [...out, ...chars.slice(i, end)]);
    }

    if (!HOUR_LETTERS.includes(c)) {
      return walk(i + 1, [...out, c]);
    }

    const from12 = c === "h" || c === "K";
    const before = i > 0 && HOUR_LETTERS.includes(chars[i - 1]!);
    const after = i + 1 < chars.length && HOUR_LETTERS.includes(chars[i + 1]!);
    const lone = to24 && from12 && !before && !after;

    return walk(i + 1, lone ? [...out, to, to] : [...out, to]);
  };

  return walk(0, []).join("");
}

// The pattern JavaScriptCore formats with for some fields.
export function jscPattern(m: Matcher, o: FieldOptions): string {
  return replaceHourCycle(bestPattern(m, jscSkeleton(o)), o.hourCycle);
}

const NARROW_NO_BREAK_SPACE = " ";
const THIN_SPACE = " ";

// JavaScriptCore writes these spaces as plain ones.
export const jscText = (s: string) =>
  s.replaceAll(NARROW_NO_BREAK_SPACE, " ").replaceAll(THIN_SPACE, " ");

// What JavaScriptCore can ask for in each field: letters and lengths.
const REQUESTS: [number, string, number[]][] = [
  [ERA, "G", [NAMES.short, NAMES.long, NAMES.narrow]],
  [YEAR, "y", [NUMBERS.numeric, NUMBERS["2-digit"]]],
  [MONTH, "M", [...Object.values(NUMBERS), ...Object.values(NAMES)]],
  [WEEKDAY, "E", Object.values(NAMES)],
  [DAY, "d", Object.values(NUMBERS)],
  [DAY_PERIOD, "B", Object.values(DAY_PERIODS)],
  [DAY_PERIOD, "a", [1]],
  [MINUTE, "m", Object.values(NUMBERS)],
  [SECOND, "s", Object.values(NUMBERS)],
  [FRACTIONAL_SECOND, "S", [1, 2, 3]],
  ...Object.values(ZONE_LETTERS).map((z): [number, string, number[]] => [
    ZONE,
    z[0]!,
    [z.length],
  ]),
  ...[..."hHkK"].map((h): [number, string, number[]] => [
    HOUR,
    h,
    Object.values(NUMBERS),
  ]),
];

// The fields in a pattern, as runs of one letter like `MMM`, without quoted
// text.
export function fieldRuns(pattern: string): string[] {
  const list = items(pattern);

  const walk = (i: number, out: string[]): string[] => {
    if (i >= list.length) {
      return out;
    }

    const item = list[i]!;

    if (item[0] === QUOTE) {
      return walk(quoteLiteral(list, i)[1] + 1, out);
    }

    return walk(i + 1, /[A-Za-z]/u.test(item) ? [...out, item] : out);
  };

  return walk(0, []);
}

// Every field run the matcher could write for this locale, and more: each
// stored pattern's fields as they are, or with any length and letter that
// `adjust` and the hour cycle could give them.
export function possibleRuns(m: Matcher): Set<string> {
  const fromPatterns = m.entries.flatMap((e) =>
    fieldRuns(e.pattern).flatMap((run) => {
      const index = canonicalIndex(run);

      if (index < 0) {
        return [run];
      }

      const f = ROWS[index]!.field;

      const keepsLetter =
        DATE_FIELDS_KEEP_PATTERN_LETTER.includes(f) || f === YEAR;

      const requested = REQUESTS.filter(([field]) => field === f).flatMap(
        ([, letter, lengths]) =>
          [...lengths, run.length].map((n) => {
            const l = keepsLetter ? run[0]! : letter;
            const shown = l === "E" && n < 3 ? "e" : l;

            return shown.repeat(n);
          }),
      );

      return [run, ...requested];
    }),
  );

  const fromText = [...m.appendItems, ...m.glues].flatMap((t) =>
    fieldRuns(t.replace(/\{\d+\}/gu, "")),
  );

  const fractions = ["S", "SS", "SSS"];

  const all = [...fromPatterns, ...fromText, ...fractions];

  // Any hour letter can become any other, and a lone one can double.
  const hours = all.flatMap((run) =>
    HOUR_LETTERS.includes(run[0]!)
      ? [..."hHkK"].flatMap((h) => [h.repeat(run.length), h.repeat(2)])
      : [],
  );

  return new Set([...all, ...hours]);
}

// A piece of a pattern: text, or a run of one letter like `MMM`.
export type Piece = { t: "text"; value: string } | { t: "run"; run: string };

// Splits a pattern the way ICU's SimpleDateFormat reads it. Two apostrophes
// make one, and text between apostrophes is quoted. JavaScriptCore writes
// narrow and thin spaces as plain ones.
export function pieces(pattern: string): Piece[] {
  const chars = [...pattern];

  const walk = (i: number, quoted: boolean, out: Piece[]): Piece[] => {
    if (i >= chars.length) {
      return out;
    }

    const c = chars[i]!;

    const text = (value: string, next: number, q: boolean) => {
      const last = out.at(-1);

      return last?.t === "text"
        ? walk(next, q, [
            ...out.slice(0, -1),
            { t: "text", value: last.value + value },
          ])
        : walk(next, q, [...out, { t: "text", value }]);
    };

    if (c === QUOTE) {
      return chars[i + 1] === QUOTE
        ? text(QUOTE, i + 2, quoted)
        : walk(i + 1, !quoted, out);
    }

    if (quoted || !/[A-Za-z]/u.test(c)) {
      return text(jscText(c), i + 1, quoted);
    }

    const length = chars.slice(i).findIndex((d) => d !== c);
    const run = c.repeat(length < 0 ? chars.length - i : length);

    return walk(i + run.length, quoted, [...out, { t: "run", run }]);
  };

  return walk(0, false, []);
}

// --- JavaScriptCore's era workaround ------------------------------------------

// Bun's JavaScriptCore writes its own era before these instants, because ICU
// never picks that era. For Islamic calendars JavaScriptCore replaces ICU's
// era and writes the year as 1 minus ICU's, in ASCII digits. Coptic's first
// era has no name in ICU, so JavaScriptCore adds the era to the end.
// JavaScriptCore applies the workaround only when the pattern has an era.
type EraWorkaround = {
  beforeMs: number;
  text: string;
  // True when JavaScriptCore replaces the era ICU writes and flips the year.
  replaces: boolean;
};

const ISLAMIC_EPOCH_MS = -42521558822000;
const ISLAMIC_TABULAR_EPOCH_MS = -42521645222000;
const COPTIC_EPOCH_MS = -53184182822000;
const BEFORE_HIJRA = "Before Hijra";

export function eraWorkaround(calendar: string): EraWorkaround | undefined {
  switch (calendar) {
    case "islamic-civil":
    case "islamic-umalqura":
      return { beforeMs: ISLAMIC_EPOCH_MS, text: BEFORE_HIJRA, replaces: true };
    case "islamic-tbla":
      return {
        beforeMs: ISLAMIC_TABULAR_EPOCH_MS,
        text: BEFORE_HIJRA,
        replaces: true,
      };
    case "coptic":
      return {
        beforeMs: COPTIC_EPOCH_MS,
        text: "Anno Martyrum",
        replaces: false,
      };
    default:
      return undefined;
  }
}

const TWO_DIGIT_YEARS = 100;

// JavaScriptCore's flipped year, in ASCII digits, and always two of them for
// a two digit year.
export function flippedYear(icuYear: number, twoDigit: boolean): string {
  const flipped = 1 - icuYear;

  return twoDigit
    ? String(
        ((flipped % TWO_DIGIT_YEARS) + TWO_DIGIT_YEARS) % TWO_DIGIT_YEARS,
      ).padStart(2, "0")
    : String(flipped);
}

// --- Run keys -----------------------------------------------------------------

const HAN_YEAR = "\u5e74";

export const hasEra = (pattern: string) => hasRun(pattern, "G");

const hasRun = (pattern: string, letters: string) =>
  pieces(pattern).some((p) => p.t === "run" && letters.includes(p.run[0]!));

// Flags in a run's key, for tokens that depend on their pattern. ICU writes
// Japanese year 1 as 元 when the pattern has 年 anywhere, and JavaScriptCore
// changes years in some calendars when the pattern has an era. ICU says noon
// all through 12 o'clock unless the pattern shows minutes or seconds.
export const HAS_HAN_YEAR = 1;
export const HAS_ERA = 2;
export const HAS_MINUTES = 4;

const FLAGS = "#";

// A run's key in a locale's table, like `MMM` or `yy#2`.
export function runKey(run: string, pattern: string): string {
  const flags = (() => {
    switch (run[0]) {
      case "y":
        return (
          (pattern.includes(HAN_YEAR) ? HAS_HAN_YEAR : 0) |
          (hasEra(pattern) ? HAS_ERA : 0)
        );
      case "b":
      case "B":
        return hasRun(pattern, "ms") ? HAS_MINUTES : 0;
      default:
        return 0;
    }
  })();

  return flags === 0 ? run : `${run}${FLAGS}${flags}`;
}

// A key's letter, length and flags.
export function keyParts(key: string): [string, number, number] {
  const [run, flags] = key.split(FLAGS);

  return [run![0]!, run!.length, Number(flags ?? 0)];
}
