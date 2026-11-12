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

Creating a formatter is slightly expensive, so it's always best to make it once and reuse it when possible. Each locale is its own module, like `glintl/locale/fr`, and `glintl/locales` finds one at runtime, for example from an `Accept-Language` header.

[How it works](HOW_IT_WORKS.md) • [Limits](LIMITS.md) • [Contributing](CONTRIBUTING.md)
