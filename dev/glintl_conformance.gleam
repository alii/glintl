//// Formats cases read from standard input, for `codegen/conformance.ts` to
//// compare with `Intl.DateTimeFormat`. Each line is a locale tag, an ICU
//// calendar name (empty for the locale's own), a date style and a time style
//// (0 for none, then 1 to 4 for full to short), an ICU hour cycle (empty for
//// the locale's own), Unix seconds and an offset in minutes, separated by
//// tabs. Only for Erlang: on JavaScript glintl is
//// `Intl`.

import gleam/dict.{type Dict}
import gleam/int
import gleam/io
import gleam/string
import gleam/time/duration
import gleam/time/timestamp
import glintl.{type Formatter}
import glintl/locales

pub fn main() -> Nil {
  loop(dict.new())
}

fn loop(formatters: Dict(String, Formatter)) -> Nil {
  case read_line() {
    Error(Nil) -> Nil
    Ok(line) -> {
      let assert [tag, calendar, date, time, hour_cycle, seconds, offset] =
        string.split(line, "\t")
      let key = string.join([tag, calendar, date, time, hour_cycle], "\t")
      let #(formatter, formatters) = case dict.get(formatters, key) {
        Ok(formatter) -> #(formatter, formatters)
        Error(Nil) -> {
          let formatter =
            new(tag, calendar, hour_cycle, number(date), number(time))
          #(formatter, dict.insert(formatters, key, formatter))
        }
      }
      let assert Ok(offset) =
        glintl.duration_to_offset(duration.minutes(number(offset)))
      glintl.format(
        formatter,
        timestamp.from_unix_seconds(number(seconds)),
        offset:,
      )
      |> io.println
      loop(formatters)
    }
  }
}

fn new(
  tag: String,
  calendar: String,
  hour_cycle: String,
  date: Int,
  time: Int,
) -> Formatter {
  let assert Ok(locale) = locales.from_tag(tag)
  let locale = case calendar {
    "" -> locale
    id -> glintl.with_calendar(locale, calendar_from_id(id))
  }
  let locale = case hour_cycle {
    "" -> locale
    "h11" -> glintl.with_hour_cycle(locale, glintl.H11)
    "h12" -> glintl.with_hour_cycle(locale, glintl.H12)
    "h23" -> glintl.with_hour_cycle(locale, glintl.H23)
    "h24" -> glintl.with_hour_cycle(locale, glintl.H24)
    _ -> panic as { "unknown hour cycle: " <> hour_cycle }
  }
  case date, time {
    0, time -> glintl.time_formatter(locale, style: style(time))
    date, 0 -> glintl.date_formatter(locale, style: style(date))
    date, time ->
      glintl.date_time_formatter(locale, date: style(date), time: style(time))
  }
}

fn number(text: String) -> Int {
  let assert Ok(n) = int.parse(text)
  n
}

fn calendar_from_id(id: String) -> glintl.Calendar {
  case id {
    "gregory" -> glintl.Gregorian
    "iso8601" -> glintl.Iso8601
    "buddhist" -> glintl.Buddhist
    "japanese" -> glintl.Japanese
    "roc" -> glintl.RepublicOfChina
    "persian" -> glintl.Persian
    "indian" -> glintl.Indian
    "hebrew" -> glintl.Hebrew
    "chinese" -> glintl.Chinese
    "dangi" -> glintl.Dangi
    "coptic" -> glintl.Coptic
    "ethiopic" -> glintl.Ethiopic
    "ethioaa" -> glintl.EthiopicAmeteAlem
    "islamic-civil" -> glintl.IslamicCivil
    "islamic-tbla" -> glintl.IslamicTabular
    "islamic-umalqura" -> glintl.IslamicUmmAlQura
    _ -> panic as { "unknown calendar: " <> id }
  }
}

fn style(index: Int) -> glintl.Style {
  case index {
    1 -> glintl.Full
    2 -> glintl.Long
    3 -> glintl.Medium
    4 -> glintl.Short
    _ -> panic as { "unknown style: " <> int.to_string(index) }
  }
}

@external(erlang, "glintl_conformance_ffi", "read_line")
fn read_line() -> Result(String, Nil) {
  panic as "only used on Erlang"
}
