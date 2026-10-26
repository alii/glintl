# glintl

Format dates and times in many languages, on Erlang and JavaScript.

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

As a separate check of ICU itself, its dates were compared once with the algorithms from Reingold and Dershowitz's _Calendrical Calculations_ (4th edition), on every day from year 1 to 4000. Coptic, Ethiopic, Hebrew, Persian (the 33-year rule) and the tabular Islamic calendars match on every day. The Chinese and Dangi (Korean) calendars match on every day from 1900 to 2100 except these, where glintl follows ICU:

| When | Calendar | ICU | The book |
| --- | --- | --- | --- |
| 1906, 1914, 1916, 1920 | Chinese | Starts some months a day earlier | Uses Beijing local time, as China did before 1929 |
| 1904, 1905, 1908, 1911 | Dangi | Starts some months a day earlier | Uses the time zones Korea used then: Seoul local time until 1908, then UTC+8:30 |
| August 2033 | Both | Puts the leap month elsewhere | The well-known "2033 problem" |
| 28 September 2057, 7 August 2097 | Chinese | Calls the day "day 0" | Day 1 of the month |
| 13 January 2097 | Dangi | Calls the day "day 0" | Day 1 of the month |

The Umm al-Qura calendar follows Saudi Arabia's official tables, so it isn't compared with the book's rule.

## How it works

On Erlang, `codegen/generate.ts` writes ICU information to Erlang modules as literals, this lets BEAM share the ICU data between processes without ever copying or garbage collecting them. This saves memory usage and cpu time.

On JavaScript, Glintl simply defers to `Intl.DateTimeFormat` via Gleam's FFI. Therefore no locale information from Glintl is included in a bundle.

## Differences between targets

Output across the two targets can differ because Glintl on Erlang uses the ICU that glintl was generated while Glintl on JavaScript defers to the runtime. These differences usually manifest in small details like commas or spaces.

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

# Run the generator. It checks every calendar against ICU on every day, and
# every locale's formats, so it takes about 10 minutes.
bun codegen/generate.ts

# Run Gleam tests
gleam test --target erlang
gleam test --target javascript

# Measure how much formatting allocates, and how long it takes
gleam run -m glintl_bench
```

Generated files are marked in `.gitattributes`, so git and GitHub leave them out of diffs.
