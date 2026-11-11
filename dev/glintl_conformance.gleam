//// Formats cases read from standard input, for `codegen/conformance.ts` to
//// compare with `Intl.DateTimeFormat`. Each line is a locale tag, an ICU
//// calendar name (empty for the locale's own), a date style and a time style
//// (0 for none, then 1 to 4 for full to short), an ICU hour cycle (empty for
//// the locale's own), fields as Intl options like `day=numeric,month=short`
//// (empty for styles), Unix seconds, milliseconds and an offset in minutes,
//// separated by tabs. Cases that share a formatter come one after another,
//// so it only keeps the last formatter.
////
//// It only runs on Erlang, because on JavaScript glintl just calls `Intl`.

import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/time/duration
import gleam/time/timestamp
import glintl
import glintl/date_time.{type Formatter}
import glintl/date_time/fields.{type Fields}
import glintl/locales
import glintl/time_zone

pub fn main() -> Nil {
  loop(None)
}

fn loop(last: Option(#(String, Formatter))) -> Nil {
  case read_line() {
    Error(Nil) -> Nil
    Ok(line) -> {
      let assert [
        tag,
        calendar,
        date,
        time,
        hour_cycle,
        fields,
        seconds,
        milliseconds,
        offset,
      ] = string.split(line, "\t")
      let key =
        string.join([tag, calendar, date, time, hour_cycle, fields], "\t")
      let formatter = case last {
        Some(#(last_key, formatter)) if last_key == key -> formatter
        _ -> new(tag, calendar, hour_cycle, number(date), number(time), fields)
      }
      let assert Ok(zone) =
        time_zone.from_duration(duration.minutes(number(offset)))
      let moment =
        timestamp.from_unix_seconds(number(seconds))
        |> timestamp.add(duration.milliseconds(number(milliseconds)))
      date_time.format(formatter, moment, zone:)
      |> io.println
      loop(Some(#(key, formatter)))
    }
  }
}

fn new(
  tag: String,
  calendar: String,
  hour_cycle: String,
  date: Int,
  time: Int,
  fields: String,
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
    0, 0 -> {
      let assert Ok(formatter) =
        date_time.fields_formatter(locale, parse_fields(fields))
      formatter
    }
    0, time -> date_time.time_formatter(locale, style: style(time))
    date, 0 -> date_time.date_formatter(locale, style: style(date))
    date, time ->
      date_time.date_time_formatter(
        locale,
        date: style(date),
        time: style(time),
      )
  }
}

fn parse_fields(text: String) -> Fields {
  text
  |> string.split(",")
  |> list.fold(fields.new(), fn(f, option) {
    let assert [name, value] = string.split(option, "=")
    case name {
      "weekday" -> fields.weekday(f, width(value))
      "era" -> fields.era(f, width(value))
      "year" -> fields.year(f, digits(value))
      "month" ->
        case value {
          "numeric" | "2-digit" -> fields.month(f, digits(value))
          _ -> fields.month_name(f, width(value))
        }
      "day" -> fields.day(f, digits(value))
      "dayPeriod" -> fields.day_period(f, width(value))
      "hour" -> fields.hour(f, digits(value))
      "minute" -> fields.minute(f, digits(value))
      "second" -> fields.second(f, digits(value))
      "fractionalSecondDigits" ->
        fields.fraction(f, case value {
          "1" -> fields.Tenths
          "2" -> fields.Hundredths
          _ -> fields.Thousandths
        })
      "timeZoneName" ->
        fields.time_zone(f, case value {
          "short" -> fields.ShortName
          "long" -> fields.LongName
          "shortOffset" -> fields.ShortOffset
          _ -> fields.LongOffset
        })
      _ -> panic as { "unknown field: " <> name }
    }
  })
}

fn width(value: String) -> fields.Width {
  case value {
    "narrow" -> fields.Narrow
    "short" -> fields.Short
    "long" -> fields.Long
    _ -> panic as { "unknown width: " <> value }
  }
}

fn digits(value: String) -> fields.Digits {
  case value {
    "numeric" -> fields.Numeric
    "2-digit" -> fields.TwoDigit
    _ -> panic as { "unknown digits: " <> value }
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

fn style(index: Int) -> date_time.Style {
  case index {
    1 -> date_time.Full
    2 -> date_time.Long
    3 -> date_time.Medium
    4 -> date_time.Short
    _ -> panic as { "unknown style: " <> int.to_string(index) }
  }
}

@external(erlang, "glintl_conformance_ffi", "read_line")
fn read_line() -> Result(String, Nil) {
  panic as "only used on Erlang"
}
