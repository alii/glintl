// Works out what the matcher needs to pick patterns for fields, for each
// locale and calendar.

import { type CalendarId, DAY_MS, type Math_ } from "./calendars.ts";
import {
  type Resource,
  allChildren,
  bundleName,
  everyChild,
  chain,
  locate,
  lookup,
} from "./icu.ts";
import {
  APPEND_ITEM_KEYS,
  DAY_PERIOD,
  DEFAULT_APPEND_ITEM,
  DISPLAY_NAME_KEYS,
  FIELD_COUNT,
  type FieldOptions,
  type Matcher,
  type MatcherData,
  type Piece,
  ZONE,
  eraWorkaround,
  flippedYear,
  jscPattern,
  matcher,
  pieces,
  hasEra,
  runKey,
  skeleton,
  skeletonText,
} from "./matcher.ts";
import { type Token, checkDays, derive, icu, moment } from "./patterns.ts";
import { random } from "./random.ts";
import { type Moment, renderParts } from "./render.ts";
import {
  HOURS_PER_HALF_DAY,
  MINUTES_PER_HOUR,
  MS_PER_SECOND,
  SECONDS_PER_MINUTE,
} from "./time.ts";

// ICU's name for each calendar's data.
const ICU_CALENDARS: Record<CalendarId, string> = {
  gregory: "gregorian",
  iso8601: "iso8601",
  buddhist: "buddhist",
  japanese: "japanese",
  roc: "roc",
  persian: "persian",
  indian: "indian",
  hebrew: "hebrew",
  chinese: "chinese",
  dangi: "dangi",
  coptic: "coptic",
  ethiopic: "ethiopic",
  ethioaa: "ethiopic-amete-alem",
  "islamic-civil": "islamic-civil",
  "islamic-tbla": "islamic-tbla",
  "islamic-umalqura": "islamic-umalqura",
};

const GREGORIAN = "gregorian";

// ICU's DateTimePatterns hold 4 times, 4 dates, then glues from index 9.
const STANDARD_PATTERNS = 8;
const GLUES_FROM = 9;
const STYLE_COUNT = 4;

const text = (r: Resource | undefined): string | undefined => {
  if (r?.t === "string") {
    return r.value;
  }

  // Some patterns are a list of the pattern and its numbering override.
  if (r?.t === "array" && r.items[0]?.t === "string") {
    return r.items[0].value;
  }

  return undefined;
};

const items = (r: Resource | undefined): Resource[] =>
  r?.t === "array" ? r.items : [];

// Like ICU's `setDateTimeFromCalendar`: the calendar's `%atTime` glues, then
// Gregorian's, then the standard ones.
function glues(bundles: string[], calendar: string): string[] {
  const from = (name: string, key: string) => {
    const found = locate(bundles, ["calendar", name]);

    return found === undefined
      ? undefined
      : lookup(found.from, [...found.path, key], bundles);
  };

  const atTime = (name: string) => from(name, "DateTimePatterns%atTime");

  const chosen =
    (calendar === GREGORIAN ? undefined : atTime(calendar)) ??
    atTime(GREGORIAN);

  const standard = () =>
    (calendar === GREGORIAN ? undefined : from(calendar, "DateTimePatterns")) ??
    from(GREGORIAN, "DateTimePatterns");

  const list =
    chosen === undefined
      ? items(standard()).slice(GLUES_FROM, GLUES_FROM + STYLE_COUNT)
      : items(chosen).slice(0, STYLE_COUNT);

  const strings = list.map((r) => (r.t === "string" ? r.value : undefined));

  if (strings.length !== STYLE_COUNT || strings.includes(undefined)) {
    throw new Error(`No glues for ${bundles[0]} ${calendar}`);
  }

  return strings.map((s) => s!);
}

// Like ICU's `getFieldAndWidthIndices`: returns a key's field, or undefined
// if the key is for another width.
const OTHER_WIDTHS = ["-short", "-narrow"];

function displayNames(bundles: string[]): string[] {
  const wide = everyChild(bundles, ["fields"]).flatMap(
    ([key, value]): [string, string][] => {
      const hyphen = key.indexOf("-");

      if (hyphen >= 0 && OTHER_WIDTHS.includes(key.slice(hyphen))) {
        return [];
      }

      const name = text(child(value, "dn"));

      return name ? [[hyphen < 0 ? key : key.slice(0, hyphen), name]] : [];
    },
  );

  return DISPLAY_NAME_KEYS.map(
    (key, i) => wide.find(([k]) => k === key)?.[1] ?? `F${i}`,
  );
}

const child = (r: Resource, key: string) =>
  r.t === "table" ? r.entries.find(([k]) => k === key)?.[1] : undefined;

const HOUR_LETTERS = { h11: "K", h12: "h", h23: "H", h24: "k" } as const;

// The hour letter ICU uses for `j`: the one a lone hour gets.
function defaultHourLetter(tag: string, calendar: CalendarId): string {
  const cycle = new Intl.DateTimeFormat(tag, {
    hour: "numeric",
    calendar,
  }).resolvedOptions().hourCycle;

  if (cycle === undefined) {
    throw new Error(`${tag}: no hour cycle for a lone hour`);
  }

  return HOUR_LETTERS[cycle];
}

const FRACTION = 1.5;

function decimal(tag: string): string {
  const { numberingSystem } = new Intl.DateTimeFormat(tag).resolvedOptions();

  const part = new Intl.NumberFormat(tag, { numberingSystem })
    .formatToParts(FRACTION)
    .find((p) => p.type === "decimal");

  if (part === undefined) {
    throw new Error(`${tag}: no decimal separator`);
  }

  return part.value;
}

export function matcherData(tag: string, calendar: CalendarId): MatcherData {
  const bundles = chain(bundleName(tag));
  const icuCalendar = ICU_CALENDARS[calendar];
  const path = (key: string) => ["calendar", icuCalendar, key];

  const standard = items(lookup(bundles, path("DateTimePatterns")))
    .slice(0, STANDARD_PATTERNS)
    .map(text);

  if (standard.length !== STANDARD_PATTERNS || standard.includes(undefined)) {
    throw new Error(`No standard patterns for ${tag} ${calendar}`);
  }

  // ICU takes the first value that isn't empty.
  const appendItems = everyChild(bundles, path("appendItems"));

  return {
    standard: standard.map((s) => s!),
    // ICU adds an empty pattern for a skeleton whose value isn't a string.
    available: allChildren(bundles, path("availableFormats")).map(
      ([key, value]): [string, string] => [key, text(value) ?? ""],
    ),
    appendItems: APPEND_ITEM_KEYS.map(
      (key) =>
        appendItems
          .map(([k, v]) => (k === key ? text(v) : undefined))
          .find((v) => v) ?? DEFAULT_APPEND_ITEM,
    ),
    displayNames: displayNames(bundles),
    glues: glues(bundles, icuCalendar),
    defaultHourLetter: defaultHourLetter(tag, calendar),
    decimal: decimal(tag),
  };
}

// --- Every request ------------------------------------------------------------

type Choice = [keyof FieldOptions, (string | number | undefined)[]];

const WIDTHS = [undefined, "narrow", "short", "long"];
const DIGITS = [undefined, "numeric", "2-digit"];

// Intl's options for each field, in ICU's field order.
const CHOICES: (Choice | undefined)[] = [
  ["era", WIDTHS],
  ["year", DIGITS],
  undefined,
  ["month", [...DIGITS, "narrow", "short", "long"]],
  undefined,
  undefined,
  ["weekday", WIDTHS],
  undefined,
  undefined,
  ["day", DIGITS],
  ["dayPeriod", WIDTHS],
  ["hour", DIGITS],
  ["minute", DIGITS],
  ["second", DIGITS],
  ["fractionalSecondDigits", [undefined, 1, 2, 3]],
  [
    "timeZoneName",
    [
      undefined,
      "short",
      "long",
      "shortOffset",
      "longOffset",
      "shortGeneric",
      "longGeneric",
    ],
  ],
];

const HOUR_CYCLES: Choice = [
  "hourCycle",
  [undefined, "h11", "h12", "h23", "h24"],
];

// Every request that picks one value from each choice.
const every = (choices: Choice[]): FieldOptions[] =>
  choices.reduce<FieldOptions[]>(
    (requests, [key, values]) =>
      requests.flatMap((r) =>
        values.map((v) => (v === undefined ? r : { ...r, [key]: v })),
      ),
    [{}],
  );

const choicesFor = (fields: number[]) =>
  fields.flatMap((f) => (CHOICES[f] === undefined ? [] : [CHOICES[f]]));

const FIELDS = Array.from({ length: FIELD_COUNT }, (_, f) => f);
const DATE_FIELDS = FIELDS.filter((f) => f < DAY_PERIOD);
const TIME_FIELDS = FIELDS.filter((f) => f >= DAY_PERIOD && f <= ZONE);

const nonEmpty = (r: FieldOptions) =>
  Object.keys(r).some(
    (k) => k !== "hourCycle" && k !== "era" && k !== "timeZoneName",
  );

// A request that mixes dates and times gets a date pattern and a time
// pattern glued together, unless one stored pattern has exactly its fields.
// So the date requests and time requests below cover every request's fields.
const DATE_REQUESTS = every(choicesFor(DATE_FIELDS)).filter(nonEmpty);

const TIME_REQUESTS = every([...choicesFor(TIME_FIELDS), HOUR_CYCLES]).filter(
  nonEmpty,
);

// Requests for exactly a stored pattern's fields, for patterns with both
// dates and times.
function mixedRequests(m: Matcher): FieldOptions[] {
  return m.entries.flatMap((e) => {
    const fields = FIELDS.filter((f) => e.skeleton.type[f] !== 0);

    const mixed =
      fields.some((f) => f < DAY_PERIOD) && fields.some((f) => f >= DAY_PERIOD);

    if (!mixed || fields.some((f) => CHOICES[f] === undefined)) {
      return [];
    }

    const present = choicesFor(fields).map(([key, values]): Choice => [
      key,
      values.filter((v) => v !== undefined),
    ]);

    return every([...present, HOUR_CYCLES]);
  });
}

const SPOT_CHECKS = 32;
const SEED_BITS = 32;

// Some requests with both dates and times, picked the same way each run.
function spotChecks(name: string): FieldOptions[] {
  const next = random(
    Number(BigInt.asUintN(SEED_BITS, BigInt(Bun.hash(name)))),
  );

  const pick = <T>(list: T[]) => list[Math.floor(next() * list.length)]!;

  return Array.from({ length: SPOT_CHECKS }, () => ({
    ...pick(DATE_REQUESTS),
    ...pick(TIME_REQUESTS),
  }));
}

// Many locales and calendars share a matcher, so `reachable` searches each
// matcher once.
const reachableCache = new Map<string, Map<string, FieldOptions>>();

// Each run key the matcher can write, with a request that writes it.
function reachable(m: Matcher): Map<string, FieldOptions> {
  const key = JSON.stringify(m);
  const cached = reachableCache.get(key);

  if (cached !== undefined) {
    return cached;
  }

  const found = search(m);
  reachableCache.set(key, found);

  return found;
}

function search(m: Matcher): Map<string, FieldOptions> {
  return [...DATE_REQUESTS, ...TIME_REQUESTS, ...mixedRequests(m)].reduce(
    (found, request) => {
      const pattern = jscPattern(m, request);

      pieces(pattern).forEach((p) => {
        const key = p.t === "run" ? runKey(p.run, pattern) : undefined;

        if (key !== undefined && !found.has(key)) {
          found.set(key, request);
        }
      });

      return found;
    },
    new Map<string, FieldOptions>(),
  );
}

// --- Tokens -------------------------------------------------------------------

// The tokens each letter can be.
const KINDS = {
  G: ["era", "cycle_era"],
  y: ["year", "extended_year"],
  Y: ["week_year"],
  u: ["extended_year"],
  r: ["related_year"],
  U: ["year_name"],
  M: ["month_number", "month_name"],
  L: ["month_number", "month_name"],
  d: ["day", "day_name"],
  E: ["weekday"],
  c: ["weekday"],
  a: ["day_period"],
  b: ["day_period"],
  B: ["day_period"],
  h: ["hour"],
  H: ["hour"],
  k: ["hour"],
  K: ["hour"],
  m: ["minute"],
  s: ["second"],
  S: ["fraction"],
  z: ["zone"],
  O: ["zone"],
  v: ["zone"],
} satisfies Record<string, Token["t"][]>;

const kindOf = (t: Token): Token["t"] =>
  t.t === "ascii" ? kindOf(t.token) : t.t;

// The token for a run ICU writes as nothing, like an empty name. Intl leaves
// these runs out.
const EMPTY: Token = { t: "literal", value: "" };

type Item =
  | { t: "char"; value: string }
  | { t: "run"; run: string }
  | { t: "token"; token: Token };

const ourItems = (ps: Piece[]): Item[] =>
  ps.flatMap((p): Item[] =>
    p.t === "run"
      ? [{ t: "run", run: p.run }]
      : [...p.value].map((value) => ({ t: "char", value })),
  );

const theirItems = (ts: Token[]): Item[] =>
  ts.flatMap((t): Item[] =>
    t.t === "literal"
      ? [...t.value].map((value) => ({ t: "char", value }))
      : [{ t: "token", token: t }],
  );

// Matches a pattern's runs to Intl's tokens. A run Intl left out is empty.
function align(ours: Item[], theirs: Item[]): [string, Token][] | undefined {
  const [o, ...restOurs] = ours;
  const [t, ...restTheirs] = theirs;

  if (o === undefined) {
    return t === undefined ? [] : undefined;
  }

  if (o.t === "char") {
    return t?.t === "char" && t.value === o.value
      ? align(restOurs, restTheirs)
      : undefined;
  }

  if (o.t !== "run") {
    return undefined;
  }

  const letter = o.run[0]!;

  const kinds: Token["t"][] =
    Object.entries(KINDS).find(([l]) => l === letter)?.[1] ?? [];

  const taken =
    t?.t === "token" && kinds.includes(kindOf(t.token))
      ? align(restOurs, restTheirs)
      : undefined;

  if (taken && t?.t === "token") {
    return [[o.run, t.token], ...taken];
  }

  const empty = align(restOurs, theirs);

  return empty ? [[o.run, EMPTY], ...empty] : undefined;
}

// What the matcher needs for a locale and calendar. `codegen/pack.ts` packs it
// into the fields tables.
export type FieldsData = {
  // Each stored pattern: its skeleton, the pattern, and whether CLDR gave the
  // skeleton.
  entries: [string, string, boolean][];
  appendItems: string[];
  displayNames: string[];
  glues: string[];
  hourLetter: string;
  decimal: string;
  // Each run key the matcher can write, with its token.
  runs: [string, Token][];
};

// Tokens for a pattern, from the run keys' tokens.
export const tokensFor = (pattern: string, runs: Map<string, Token>): Token[] =>
  pieces(pattern).map((p) => {
    if (p.t === "text") {
      return { t: "literal", value: p.value };
    }

    const key = runKey(p.run, pattern);
    const token = runs.get(key);

    if (token === undefined) {
      throw new Error(`No token for ${key}`);
    }

    return token;
  });

// The moments we check: each check day at several times of day.
const CHECK_OFFSET = 330;
const CHECK_MS = [0, 123, 987];

function checkMoments(math: Math_) {
  const days = checkDays(math);
  const [probe] = days;

  const times = [
    [0, 0, 0],
    [HOURS_PER_HALF_DAY, 0, 0],
    [HOURS_PER_HALF_DAY - 1, MINUTES_PER_HOUR - 1, SECONDS_PER_MINUTE - 1],
    [HOURS_PER_HALF_DAY + 1, 1, 1],
    [HOURS_PER_HALF_DAY, 1, 1],
    [0, 1, 1],
  ];

  return [
    ...days.map((d, i) =>
      moment(
        math,
        d,
        CHECK_OFFSET,
        undefined,
        undefined,
        undefined,
        CHECK_MS[i % CHECK_MS.length],
      ),
    ),
    ...times.flatMap(([h, m, s]) =>
      CHECK_MS.map((ms) => moment(math, probe!, 0, h, m, s, ms)),
    ),
  ];
}

const endsWithSpace = /\s$/u;

// Applies JavaScriptCore's era workaround to each piece's text.
function withEraWorkaroundFor(
  calendar: CalendarId,
  pattern: string,
  request: FieldOptions,
  texts: string[],
  mo: Moment,
): string {
  const w = eraWorkaround(calendar);
  const ms = mo.unixSeconds * MS_PER_SECOND + mo.milliseconds;

  if (w === undefined || !hasEra(pattern) || ms >= w.beforeMs) {
    return texts.join("");
  }

  const letters = pieces(pattern).map((p) => (p.t === "run" ? p.run[0] : ""));

  if (!w.replaces) {
    const written = texts.map((t, i) => (letters[i] === "G" ? "" : t)).join("");

    return endsWithSpace.test(written)
      ? written + w.text
      : `${written} ${w.text}`;
  }

  const era = letters.lastIndexOf("G");
  const year = letters.lastIndexOf("y");

  return texts
    .map((t, i) =>
      i === era
        ? w.text
        : i === year
          ? flippedYear(mo.date.extended, request.year === "2-digit")
          : t,
    )
    .join("");
}

export function fieldsData(
  tag: string,
  calendar: CalendarId,
  math: Math_,
  digits: string[],
): FieldsData {
  const m = matcher(matcherData(tag, calendar));
  const witnesses = reachable(m);
  const requests = [...new Set(witnesses.values())];
  const name = (r: FieldOptions) => `${tag} ${calendar} ${JSON.stringify(r)}`;

  const withEraWorkaround = (
    pattern: string,
    request: FieldOptions,
    texts: string[],
    mo: Moment,
  ) => withEraWorkaroundFor(calendar, pattern, request, texts, mo);

  // Learns each key's token from what Intl writes for a request on a day.
  const learn = (request: FieldOptions) => {
    const pattern = jscPattern(m, request);
    const workaround = eraWorkaround(calendar);

    // JavaScriptCore's era workaround hides how ICU writes years, so `learn`
    // skips those days.
    const skip = (d: number) =>
      workaround !== undefined &&
      hasEra(pattern) &&
      d * DAY_MS < workaround.beforeMs + DAY_MS;

    const derived = derive(
      tag,
      calendar,
      math,
      request,
      digits,
      undefined,
      skip,
    );

    const found = align(ourItems(pieces(pattern)), theirItems(derived));

    if (found === undefined) {
      throw new Error(
        `${name(request)}: pattern ${pattern} doesn't match Intl's ${JSON.stringify(derived)}`,
      );
    }

    return found.map(([run, token]): [string, Token] => [
      runKey(run, pattern),
      token,
    ]);
  };

  const same = (a: Token, b: Token) => JSON.stringify(a) === JSON.stringify(b);

  const runs = requests.reduce((known, request) => {
    learn(request).forEach(([key, token]) => {
      const old = known.get(key);

      if (old !== undefined && !same(old, token)) {
        throw new Error(
          `${name(request)}: ${key} is ${JSON.stringify(token)} here but ${JSON.stringify(old)} before`,
        );
      }

      known.set(key, token);
    });

    return known;
  }, new Map<string, Token>());

  const moments = checkMoments(math);

  // Each key's token came from one request, so other requests check that it
  // works in their patterns too.
  [...requests, ...spotChecks(`${tag} ${calendar}`)].forEach((request) => {
    const pattern = jscPattern(m, request);
    const tokens = tokensFor(pattern, runs);

    moments.forEach((mo) => {
      const ours = withEraWorkaround(
        pattern,
        request,
        renderParts(tokens, digits, mo),
        mo,
      );

      const theirs = icu(tag, calendar, request, mo);

      if (ours !== theirs) {
        throw new Error(
          `${name(request)} on day ${mo.epochDay} at ${mo.hour}:${mo.minute}:${mo.second}.${mo.milliseconds}: ${ours} | ${theirs}`,
        );
      }
    });
  });

  // The runtime matcher reads each skeleton again from its text.
  m.entries.forEach((e) => {
    const text = skeletonText(e.skeleton);

    if (JSON.stringify(skeleton(text)) !== JSON.stringify(e.skeleton)) {
      throw new Error(`${tag} ${calendar}: skeleton ${text} reads differently`);
    }
  });

  return {
    entries: m.entries.map((e) => [
      skeletonText(e.skeleton),
      e.pattern,
      e.specified,
    ]),
    appendItems: m.appendItems,
    displayNames: m.displayNames,
    glues: m.glues,
    hourLetter: m.defaultHourLetter,
    decimal: m.decimal,
    runs: [...runs.entries()],
  };
}
