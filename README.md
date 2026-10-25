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

## How it works

On Erlang, `codegen/generate.ts` writes ICU information to Erlang modules as literals, this lets BEAM share the ICU data between processes without ever copying or garbage collecting them. This saves memory usage and cpu time.

On JavaScript, Glintl simply defers to `Intl.DateTimeFormat` via Gleam's FFI. Therefore no locale information from Glintl is included in a bundle.

## Differences between targets

Output across the two targets can differ because Glintl on Erlang uses the ICU that glintl was generated while Glintl on JavaScript defers to the runtime. These differences usually manifest in small details like commas or spaces.

## Limits

- Today, only the Gregorian calendar is supported.

- `format` takes an offset rather than a time zone like `Europe/London`, so zones are written like `GMT+1` rather than `British Summer Time`. Offsets are rounded down to whole minutes.

- There is no way to choose individual fields, such as month and year only.

## Contributing

These will need these commands in order to contribute:

```sh
# Install deps for the generator
bun install --cwd codegen

# Run a typecheck on the generator
bun check --cwd codegen

# Run the generator
bun codegen/generate.ts

# Run Gleam tests
gleam test --target erlang
gleam test --target javascript
```
