# glintl

Format dates and times in many languages, on Erlang and JavaScript.

**glintl isn't ready to depend on yet. Expect breaking changes.**

On Erlang it aims to have the same output as JavaScript's `Intl.DateTimeFormat`.

```sh
gleam add glintl gleam_time
```

```gleam
import gleam/time/timestamp
import glintl/date_time
import glintl/locale/en_gb
import glintl/locale/fr

pub fn main() {
  let now = timestamp.system_time()
  let assert Ok(offset) = date_time.offset(hours: 1, minutes: 0)

  date_time.date_time_formatter(
    en_gb.locale(),
    date: date_time.Long,
    time: date_time.Short,
  )
  |> date_time.format(now, offset:)
  // -> "25 October 2026 at 23:40"

  date_time.date_formatter(fr.locale(), style: date_time.Full)
  |> date_time.format(now, offset:)
  // -> "dimanche 25 octobre 2026"
}
```

Making a formatter does lookup work and is expensive, so reuse formatters where you can.

## Styles

| Style    | Date                    | Time               |
| -------- | ----------------------- | ------------------ |
| `Full`   | Sunday, 25 October 2026 | 23:40:58 GMT+01:00 |
| `Long`   | 25 October 2026         | 23:40:58 GMT+1     |
| `Medium` | 25 Oct 2026             | 23:40:58           |
| `Short`  | 25/10/2026              | 23:40              |

## Locales

- Import the locales you need, like `glintl/locale/en_gb`, if you can. To support several, import each one.
- If you need them all, or only know the locale at runtime, use `locales.from_tag("en-GB")` from `glintl/locales`.

  ```gleam
  import glintl/locales

  locales.from_tag("en-GB") // -> Ok(en_gb.locale())
  locales.from_tag("en-XX") // -> Ok(en.locale())
  locales.from_tag("xx") // -> Error(Nil)
  ```

- Pick one from an `Accept-Language` header with `locales.from_accept_language(header)`, or from your own list with `locales.negotiate(header, among: supported)`.

## Calendars

- Each locale uses its own calendar by default.
- Use other calendars with `glintl.with_calendar(locale, glintl.Hebrew)`.
- glintl supports all of ICU's calendars: Gregorian, ISO 8601, Buddhist, Japanese, Republic of China, Persian, Indian, Hebrew, Chinese, Dangi, Coptic, Ethiopic (2 eras), and 3 Islamic calendars.

## Hour cycles

- Each locale uses its own hour cycle by default. American English uses the 12 hour clock and British English uses the 24 hour clock.
- Use another with `glintl.with_hour_cycle(locale, glintl.H23)`, like the `hourCycle` option of `Intl.DateTimeFormat`.

## Offsets and dates

- Make an offset with `date_time.offset(hours: 5, minutes: 30)`, or from a `gleam_time` duration with `date_time.duration_to_offset`. `date_time.utc` is an offset of zero.
- Format a date with no time zone, like a birthday, with `date_time.format_date(formatter, date)`.

## How it works

On Erlang:

- Formats come from ICU when glintl is built, not when your app runs.
- All locale data is defined as [literals](https://www.erlang.org/doc/system/eff_guide_processes.html#literal-pool), with repeated parts stored once. This saves memory, because every process can safely share the data and it's rarely copied or garbage collected.
- We're working on making the start-up cost smaller.

On JavaScript:

- glintl calls `Intl.DateTimeFormat`.
- A locale is just its tag, so your bundle has no locale data.

## Compared to Localize

[Localize](https://github.com/elixir-localize/localize) combines the Elixir `ex_cldr` set of libraries into one package. Today, it covers far more than glintl, like numbers, units and messages. The big difference is where the locale data comes from.

- **Localize** keeps locale data in files you download, when you build or, if you turn it on, from its server while your app runs. It reads a locale's file from disk the first time you use that locale. If the file is missing, it falls back to a parent locale or English without telling you.
- **glintl** compiles every locale into its own module. You don't download anything, and glintl never fetches or reads data files while your app runs, so a missing file or a server outage can't change your output. A mistyped locale module won't compile, and `glintl/locales` returns an `Error` for a tag it doesn't know.

## Limits

- Time zones are passed as offsets, so you get `GMT+1` rather than `British Summer Time`.
- You can't yet pick single fields, like only the month and year.
- On Erlang, calendars with their own months cover the years 1 to 4000. Other dates fall back to Gregorian.

## Known differences

- **Erlang vs JavaScript:** the ICU data glintl bundles for Erlang can differ from the ICU in your JavaScript runtime, so output can differ between targets. It's usually small details like spaces and commas.
- **ICU bugs glintl copies:** ICU 78.3 puts Chinese New Year 2027 and 2030 a day off. JavaScript does the same.
- **ICU bug glintl doesn't copy yet:** near AD 284 and AD 622, the Coptic and Islamic calendars can show the wrong year around midnight.

## Contributing

```sh
bun install --cwd codegen
bun fmt --cwd codegen && bun lint --cwd codegen && bun check --cwd codegen
gleam test --target erlang
gleam test --target javascript
gleam run -m glintl_bench
bun codegen/conformance.ts 1000000
```

- The generator, the JavaScript tests and the conformance run need the Bun version in `.bun-version`, on Linux. CI runs them that way.
- On a Mac, run the generator in Docker:

```sh
docker run --rm -v "$PWD":/repo -w /repo oven/bun:$(cat .bun-version) bun codegen/generate.ts
gleam format src test
```
