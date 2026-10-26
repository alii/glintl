# glintl

Format dates and times in many languages, on Erlang and JavaScript.

Glintl lazy-loads locales for performance. On Erlang it aims to have the same output as JavaScript's `Intl.DateTimeFormat`.

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
}
```

It is recommended to reuse formatters for performance, because making one is expensive and does lookup work.

## Styles

| Style    | Date                    | Time               |
| -------- | ----------------------- | ------------------ |
| `Full`   | Sunday, 25 October 2026 | 23:40:58 GMT+01:00 |
| `Long`   | 25 October 2026         | 23:40:58 GMT+1     |
| `Medium` | 25 Oct 2026             | 23:40:58           |
| `Short`  | 25/10/2026              | 23:40              |

## Locales

- Import the ones you need: `import glintl/locale/ja`.
- Pick one from a tag with `locales.from_tag("en-GB")`.

  ```gleam
  import glintl/locales

  locales.from_tag("en-GB") // -> Ok(en_gb.locale())
  locales.from_tag("en-XX") // -> Ok(en.locale())
  locales.from_tag("xx") // -> Error(Nil)
  ```

- `glintl/locales` imports every locale. Only use it if you don't know the locale until run time.

## Calendars

- Each locale uses its own calendar by default. Thai uses Buddhist.
- Pick another with `glintl.with_calendar(locale, glintl.Hebrew)`.
- All of ICU's calendars: Gregorian, ISO 8601, Buddhist, Japanese, Republic of China, Persian, Indian, Hebrew, Chinese, Dangi, Coptic, Ethiopic (2 eras), and 3 Islamic calendars.

## How it works

On Erlang:

- Formats come from ICU when glintl is built, not when your app runs.
- Each locale is an Erlang module. It loads the first time you use it, and stays loaded.
- The data is shared by every process. It is never copied or garbage collected.
- Releases in "embedded mode" load every module at start-up instead.

On JavaScript:

- glintl calls `Intl.DateTimeFormat`.
- A locale is just its tag, so your bundle has no locale data.

## Limits

- Today, time zones in Glintl are passed as offsets. You get `GMT+1`, not `British Summer Time`.
- Today, Glintl does not allow you can't pick single fields like month and year only.
- On Erlang, calendars with their own months cover the years 1 to 4000. Other dates fall back to Gregorian.

## Known differences

- **Erlang vs JavaScript:** Erlang uses the ICU in Bun on Linux. JavaScript uses your runtime's ICU. Differences can exist, usually manifesting in small details like spaces and commas.
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

- The generator, JavaScript tests and conformance run need the Bun in `.bun-version`, on Linux. CI does this.
- On a Mac, run the generator in Docker. It takes about 10 minutes:

```sh
docker run --rm -v "$PWD":/repo -w /repo oven/bun:$(cat .bun-version) bun codegen/generate.ts
gleam format src test
```
