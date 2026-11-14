# glintl

Format dates and times in many languages, on Erlang and JavaScript.

On Erlang, glintl aims to give the same output as JavaScript's `Intl` API. It's faster and uses much less memory than other internationalisation libraries. On JavaScript, glintl uses the runtime's own `Intl`.

[Documentation](https://hexdocs.pm/glintl/) • [Repository](https://github.com/alii/glintl)

glintl is in early development, so expect breaking changes.

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

Creating a formatter takes some work, so create it once and reuse it.

Each locale is its own module, like `glintl/locale/fr`. To choose a locale while your app runs, use the helpers in `glintl/locales`. They can read an `Accept-Language` header, for example.

To style each piece of a date, like a bold weekday, use `date_time.format_to_parts`.

## How it works

On JavaScript, glintl calls `Intl.DateTimeFormat` directly. glintl adds no locale data to your JavaScript bundle, so you can use it in size-sensitive programs, like in the browser.

On Erlang, glintl reads its data from ICU when we build the package, and ships that data inside the package. Your program reads it from the package itself, with no files to download or read from disk. glintl stores the data as [literals](https://www.erlang.org/doc/system/eff_guide_processes.html#literal-pool), which Erlang keeps in one place for every process to share. We're still working on making it load even faster.

If you're coming from Elixir, [Localize](https://github.com/elixir-localize/localize) does much more than glintl, like formatting numbers and units. We plan to add these to glintl too. The main difference is where the locale data comes from:

- Localize loads locale data from files or the network. When a file is missing, it quietly falls back to another locale.
- glintl builds every locale into the package. `glintl/locales` returns an error for a tag it has no data for, and has helpers if you want to fall back yourself.

[Limits](LIMITS.md) • [Contributing](CONTRIBUTING.md)
