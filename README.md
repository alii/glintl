# glintl

glintl formats dates and times in your users' languages. It works on Erlang and JavaScript, and on Erlang it aims to give the same output as JavaScript's `Intl.DateTimeFormat`.

It isn't ready to depend on yet, so expect breaking changes.

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

Making a formatter takes some work, so make it once and reuse it. You'll find every function explained on [Hexdocs](https://hexdocs.pm/glintl/).

Each locale is a module you import, like `glintl/locale/fr`. If you don't know the locale until your app runs, look it up with `glintl/locales`. It can also read an `Accept-Language` header.

```gleam
import glintl/locales

locales.from_tag("en-GB") // -> Ok(en_gb.locale())
locales.from_tag("en-XX") // -> Ok(en.locale())
locales.from_tag("xx") // -> Error(Nil)
```

## How it works

On JavaScript, glintl calls `Intl.DateTimeFormat`, so your bundle doesn't include any locale data.

On Erlang, we take the data from ICU when we build glintl and ship it inside the package. Your app never downloads it or reads it from disk. We store it as [literals](https://www.erlang.org/doc/system/eff_guide_processes.html#literal-pool), which Erlang keeps in one place for every process to share. We're still working on making it load faster.

If you're coming from Elixir, [Localize](https://github.com/elixir-localize/localize) does much more than glintl, like numbers and units. The main difference is that Localize loads locale data from files, and if a file is missing it quietly falls back to another locale. glintl builds the data in, and `glintl/locales` returns an `Error` for a tag it doesn't know.

## Limits

- We take time zones as offsets, so you'll see `GMT+1` and not `British Summer Time`.
- On Erlang, calendars with their own months only work from year 1 to 4000. Other years fall back to the Gregorian calendar.
- Erlang uses the ICU data we bundle, but JavaScript uses your runtime's own ICU. They can disagree on small things like spaces and commas.
- ICU 78.3 puts Chinese New Year 2027 and 2030 a day off. JavaScript gets this wrong too, so we match it.
- Around midnight near AD 284 and AD 622, ICU shows the wrong year in the Coptic and Islamic calendars. We don't copy this bug yet, so glintl and JavaScript can disagree there.

## Contributing

```sh
bun install --cwd codegen
bun fmt --cwd codegen && bun lint --cwd codegen && bun check --cwd codegen
gleam test --target erlang
gleam test --target javascript
gleam run -m glintl_bench
bun codegen/conformance.ts 1000000
```

The generator, the JavaScript tests and the conformance run need the Bun version in `.bun-version`, running on Linux. That's how CI runs them. On a Mac, run the generator in Docker:

```sh
docker run --rm -v "$PWD":/repo -w /repo oven/bun:$(cat .bun-version) bun codegen/generate.ts
gleam format src test
```
