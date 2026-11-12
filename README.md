# glintl

Format dates and times in many languages, on Erlang and JavaScript.

On Erlang, Glintl aims to give the same output as JavaScript's `Intl` API, and is faster and has a much smaller memory footprint than other internationalisation libraries. On JavaScript, Glintl defers to the host's implementation of `Intl`.

[Documentation](https://hexdocs.pm/glintl/) • [Repository](https://github.com/alii/glintl)

It isn't ready to depend on yet, so expect breaking changes.

```sh
gleam add glintl gleam_time
```

```gleam
import gleam/time/timestamp
import glintl
import glintl/date_time
import glintl/locale/en_gb
import glintl/time_zone

pub fn main() {
  let assert Ok(zone) = time_zone.offset(hours: 1, minutes: 0)

  // Like Intl's { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }
  let options =
    date_time.new()
    |> date_time.day(glintl.Numeric)
    |> date_time.month_name(glintl.Short)
    |> date_time.hour(glintl.TwoDigit)
    |> date_time.minute(glintl.TwoDigit)

  let formatter = date_time.fields_formatter(en_gb.locale(), options)

  date_time.format(formatter, timestamp.system_time(), zone:)
  // -> "25 Oct, 23:40"
}
```

Creating a formatter is slightly expensive, so it's always best to make it once and reuse it when possible. There are also formatters for Intl's `dateStyle` and `timeStyle`, like `date_time.date_formatter(locale, style: date_time.Long)`. For dates with no time or time zone, like birthdays, use `glintl/date`.

Each locale is a separate Gleam module, like `glintl/locale/fr`. If you don't know the locale until your app runs, you can look it up with the helpers in `glintl/locales`. You can use these helpers to read an `Accept-Language` header, for example.

```gleam
import glintl/locales

locales.from_tag("en-GB") // -> Ok(en_gb.locale())
locales.from_tag("en-XX") // -> Ok(en.locale())
locales.from_tag("xx") // -> Error(Nil)
```

## How it works

On JavaScript, glintl calls JavaScript's `Intl.DateTimeFormat` directly. No locale data is included on JavaScript so it's safe to include Glintl in size-sensitive programs, like for the browser.

On Erlang, we take the data from ICU when we build glintl and ship it inside the package, so your program never needs to download it or read it from disk. We store it as [literals](https://www.erlang.org/doc/system/eff_guide_processes.html#literal-pool), which Erlang keeps in one place for every process to share. We're still working on making it load faster.

If you're coming from Elixir, [Localize](https://github.com/elixir-localize/localize) does much more than glintl, like formatting numbers and units. This is planned to be added to Glintl, but until then the main difference is that Localize loads locale data from files or the network, and if a file is missing it quietly falls back to another locale. Glintl gives you a lookup function. It never falls back on an unknown locale, but it has helpers so you can do that yourself.

## Limits

- On Erlang, calendars with their own months only work from year 1 to 4000. Other years fall back to the Gregorian calendar.
- glintl on Erlang uses the ICU bundled at Glintl's own build time, but JavaScript uses ICU built into the runtime. Differences in ICU versions mean the two targets can disagree on small things, often in spaces and commas.
- ICU 78.3 puts Chinese New Year 2027 and 2030 a day off. JavaScript gets this wrong too, so we intentionally match it in the name of behaviour parity.
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
