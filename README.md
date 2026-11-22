# glintl

Format dates and times in many languages, on Erlang and JavaScript.

On Erlang, glintl aims to give the same output as JavaScript's `Intl` API. It's faster and uses much less memory than other internationalisation libraries. On JavaScript, glintl uses the runtime's own `Intl`.

[Documentation](https://hexdocs.pm/glintl/) • [Repository](https://github.com/alii/glintl)

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
  let fields =
    date_time.new()
    |> date_time.day(glintl.Numeric)
    |> date_time.month_name(glintl.Short)
    |> date_time.hour(glintl.TwoDigit)
    |> date_time.minute(glintl.TwoDigit)

  let formatter = date_time.fields_formatter(en_gb.locale(), fields)

  date_time.format(formatter, timestamp.system_time(), zone:)
  // -> "25 Oct, 23:40"
}
```

Creating a formatter takes some work, so create it once and reuse it.

Each locale is its own module, like `glintl/locale/fr`. To choose a locale while your app runs, use the helpers in `glintl/locales`. They can read an `Accept-Language` header, for example.

To change a locale's calendar, hour cycle or digits, use `glintl.with_calendar`, `glintl.with_hour_cycle` or `glintl.with_numbering_system`. `locales.from_tag` also reads them from a tag, like the Japanese calendar in `"ja-JP-u-ca-japanese"`.

To style each piece of a date, like a bold weekday, use `date_time.format_to_parts`.

## How it works

On JavaScript, glintl calls `Intl.DateTimeFormat` directly. glintl adds no locale data to your JavaScript bundle, so you can use it in size-sensitive programs, like in the browser.

On Erlang, glintl's locales are built-in to the package. The locales are generated when we build and publish glintl. We store the data as [literals](https://www.erlang.org/doc/system/eff_guide_processes.html#literal-pool), which Erlang keeps in one place for every process to share. This reduces memory usage compared to downloading or parsing files at runtime. And we're still working on improving performance!

Note that ICU updates will be done in a semver patch, and thus are not considered breaking changes.

If you're coming from Elixir, [Localize](https://github.com/elixir-localize/localize) offers a few more features than glintl, like formatting numbers and units. We do plan to add these to glintl. Beyond that, the main difference is where the locale data comes from:

- Localize loads locale data from files or the network. When a file is missing, it quietly falls back to another locale.
- glintl builds every locale into the package. `glintl/locales` returns an error for a tag it has no data for, and has helpers if you want to implement the fallback yourself.

[Limits](https://github.com/alii/glintl/blob/master/LIMITS.md) • [Contributing](https://github.com/alii/glintl/blob/master/CONTRIBUTING.md)
