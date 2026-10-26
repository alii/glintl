# glintl

Format dates and times in many languages, on Erlang and JavaScript.

Every locale and calendar is loaded lazily, the first time you use it, so you only pay for the ones you need.

```sh
gleam add glintl gleam_time
```

```gleam
import gleam/time/duration
import gleam/time/timestamp
import glintl
import glintl/locale/en_gb
import glintl/locale/fr

pub fn main() {
  let now = timestamp.system_time()
  let offset = duration.hours(1)

  glintl.date_time_formatter(en_gb.locale(), date: glintl.Long, time: glintl.Short)
  |> glintl.format(now, offset:)
  // -> "25 October 2026 at 23:40"

  glintl.date_formatter(fr.locale(), style: glintl.Full)
  |> glintl.format(now, offset:)
  // -> "dimanche 25 octobre 2026"

  glintl.time_formatter(en_gb.locale(), style: glintl.Short)
  |> glintl.format(now, offset:)
  // -> "23:40"
}
```

You should try to reuse formatters, as making one is expensive and does lookup work, so that formatting is quite cheap.

## Styles

There are four styles, the same as `dateStyle` and `timeStyle` in JavaScript's `Intl.DateTimeFormat`. In British English:

| Style    | Date                    | Time               |
| -------- | ----------------------- | ------------------ |
| `Full`   | Sunday, 25 October 2026 | 23:40:58 GMT+01:00 |
| `Long`   | 25 October 2026         | 23:40:58 GMT+1     |
| `Medium` | 25 Oct 2026             | 23:40:58           |
| `Short`  | 25/10/2026              | 23:40              |

## Locales

Locales are defined in their own modules, this makes it easier to load only as much as you need.

```gleam
import glintl/locale/fr
import glintl/locale/ja
```

To pick one from a tag, such as an `Accept-Language` header, use `glintl/locales`:

```gleam
import glintl/locales

locales.from_tag("en-GB")  // -> Ok(en_gb.locale())
locales.from_tag("en-XX")  // -> Ok(en.locale())
locales.from_tag("xx")     // -> Error(Nil)
```

Note that `glintl/locales` imports every locale, so use it only when the locale isn't known until run time.

## Calendars

Each locale formats dates in its own calendar by default, like ICU does: Thai uses the Buddhist calendar, Persian the Persian calendar and Saudi Arabic the Umm al-Qura calendar. Use `with_calendar` to pick another:

```gleam
en_gb.locale()
|> glintl.with_calendar(glintl.Hebrew)
|> glintl.date_formatter(style: glintl.Long)
|> glintl.format(now, offset:)
// -> "14 Heshvan 5787"
```

glintl has every calendar ICU has: Gregorian, ISO 8601, Buddhist, Japanese, Republic of China, Persian, Indian, Hebrew, Chinese, Dangi, Coptic, Ethiopic (both eras), and the civil, tabular and Umm al-Qura Islamic calendars.

On Erlang, calendars with their own months are stored as tables of years made from ICU, covering the Gregorian years 1 to 4000. Dates outside that range are written in the Gregorian calendar. Calendars with Gregorian months (Gregorian, ISO 8601, Buddhist, Japanese and Republic of China) have no limit.

### How the calendars are checked

glintl copies ICU, mistakes included, so the output matches JavaScript. When the data is generated, every calendar's maths is checked against ICU on every day it covers, about 29 million days in all. The tests then check the Erlang calendar code field by field, and every locale's formats against `Intl.DateTimeFormat`.

As a separate check of ICU itself, its dates were compared once with the algorithms from Reingold and Dershowitz's _Calendrical Calculations_ (4th edition), on every day from year 1 to 4000. Coptic, Ethiopic, Hebrew, Persian (the 33-year rule) and the tabular Islamic calendars match on every day. The Chinese and Dangi (Korean) calendars match on most days from 1900 to 2100. On these, where glintl follows ICU 78.3, they don't:

| When                                           | Calendar | ICU 78.3                                  | The book                                                                        |
| ---------------------------------------------- | -------- | ----------------------------------------- | ------------------------------------------------------------------------------- |
| 1906, 1917, 1922                               | Chinese  | Starts some months a day earlier or later | Uses Beijing local time, as China did before 1929                               |
| 1904, 1905, 1908, 1911                         | Dangi    | Starts some months a day earlier          | Uses the time zones Korea used then: Seoul local time until 1908, then UTC+8:30 |
| 1954, 1955, 1987, 1999, 2012, 2018, 2057, 2070 | Chinese  | Starts some months a day earlier or later | Starts them on the other day                                                    |
| 2017, 2051, 2097                               | Dangi    | Starts some months a day earlier or later | Starts them on the other day                                                    |
| Chinese New Year 2027 and 2030                 | Chinese  | 7 February 2027 and 2 February 2030       | 6 February 2027 and 3 February 2030, the real dates                             |
| August 2033                                    | Both     | Puts the leap month elsewhere             | The well-known "2033 problem"                                                   |

So in those months, glintl and JavaScript are both a day out. ICU's Chinese calendar changes between versions: the ICU 78.1 in macOS gets 2027 and 2030 right, and has other differences instead. glintl's tables are regenerated from the pinned ICU, so they follow it.

The Umm al-Qura calendar follows Saudi Arabia's official tables, so it isn't compared with the book's rule.

One ICU quirk isn't copied yet. In the Coptic and Islamic calendars, at moments where the local date and the UTC date are in different eras, ICU takes the era and year from one date and the month and day from the other. For example, at 22:24 on 19 July 622 at UTC−10, it gives "29 Dhu al-Hijjah, 0 AH" where glintl gives "29 Dhu al-Hijjah, 1 BH". This only happens on the day before and the first day of those eras, AD 284 and AD 622, at times when the offset moves the date across midnight.

## How it works

On Erlang, the formats come from ICU when the package is generated, not when your app runs. `codegen/generate.ts` writes them to Erlang modules as literals: constant data that the BEAM keeps once and shares with every process, without copying it or garbage collecting it.

Each locale's data is its own module, and the BEAM loads a module the first time something calls it. So importing `glintl/locale/fr` costs nothing until `fr.locale()` runs, and a locale's data for calendars other than Gregorian is a separate module again, loaded only when you make a formatter for one of them. The same goes for each calendar's maths. A loaded module stays loaded until the app stops. Releases that load every module at boot, in Erlang's "embedded mode", lose the laziness and pay for every locale upfront.

On JavaScript, glintl uses the runtime's `Intl.DateTimeFormat`, so a locale is just its tag and there is no locale data in your bundle. Locale modules you don't import are left out by bundlers, and the runtime loads its own locale data as it needs it.

## Differences between targets

Output across the two targets can differ because Glintl on Erlang uses the ICU that glintl was generated with, while Glintl on JavaScript defers to the runtime. glintl is generated with Bun on Linux, the version in `.bun-version`. Most differences are small details like commas or spaces, but runtimes package ICU differently, so some are bigger. For example:

| Runtime                               | ICU  | Before 15 October 1582 in the Buddhist, Japanese and ROC calendars | ISO 8601 month names |
| ------------------------------------- | ---- | ------------------------------------------------------------------ | -------------------- |
| Bun 1.4.4 on Linux, which glintl uses | 78.3 | Julian dates                                                       | Missing              |
| Node 26 on macOS                      | 78.3 | Julian dates                                                       | Missing              |
| Node 26 on Linux                      | 78.3 | Julian dates                                                       | Present              |
| Bun 1.4.4 canary on macOS             | 78.1 | Gregorian dates                                                    | Present              |

## Limits

- On Erlang, calendars with their own months only cover the Gregorian years 1 to 4000. If you have a use case out side of this range, please open an issue!

- `format` takes an offset rather than a time zone like `Europe/London`, so zones are written like `GMT+1` rather than `British Summer Time`. Offsets are rounded down to whole minutes.

- There is no way to choose individual fields, such as month and year only.

## Contributing

These will need these commands in order to contribute:

```sh
# Install deps for the generator
bun install --cwd codegen

# Format, lint and typecheck the generator
bun fmt --cwd codegen
bun lint --cwd codegen
bun check --cwd codegen

# Run Gleam tests
gleam test --target erlang
gleam test --target javascript

# Measure how much formatting allocates, and how long it takes
gleam run -m glintl_bench

# Check glintl on Erlang against Intl.DateTimeFormat on random cases
bun codegen/conformance.ts 1000000
```

The generated data, the JavaScript tests and the conformance run all depend on Bun's ICU, which differs between Bun builds and systems. They must use the Bun in `.bun-version` on Linux, as CI does. On other systems, run them in Docker:

```sh
# Run the generator. It checks every calendar against ICU on every day, and
# every locale's formats, so it takes about 10 minutes.
docker run --rm -v "$PWD":/repo -w /repo oven/bun:$(cat .bun-version) bun codegen/generate.ts
gleam format src test
```

The conformance run needs Erlang as well, so in Docker, save cases with the pinned Bun and check them with your own Erlang:

```sh
docker run --rm -v "$PWD":/repo -w /repo oven/bun:$(cat .bun-version) bun codegen/conformance.ts --save cases.tsv 1000000
bun codegen/conformance.ts --check cases.tsv
```

CI runs all of these on every push to `master` and every pull request.

Generated files are marked in `.gitattributes`, so git and GitHub leave them out of diffs.
