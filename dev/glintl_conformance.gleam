//// Formats cases read from standard input, for `codegen/conformance.ts` to
//// compare with `Intl.DateTimeFormat`. Each line holds these values,
//// separated by tabs:
////
//// - a locale tag
//// - an ICU calendar name, or empty for the locale's own
//// - a date style and a time style, each 0 for none or 1 to 4 for full to
////   short
//// - an ICU hour cycle, or empty for the locale's own
//// - fields as Intl options like `day=numeric,month=short`, or empty for
////   styles
//// - Unix seconds, then milliseconds
//// - a time zone, as an offset in minutes or a name like `Europe/London`
////
//// Cases that share a formatter come one after another, so the loop keeps
//// only the last formatter.
////
//// The module only runs on Erlang, because on JavaScript glintl calls `Intl`
//// directly.

import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/time/duration
import gleam/time/timestamp
import glintl
import glintl/date_time.{type Formatter}
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
      let zone = parse_zone(offset)
      let moment =
        timestamp.from_unix_seconds(number(seconds))
        |> timestamp.add(duration.milliseconds(number(milliseconds)))
      let text = date_time.format(formatter, moment, zone:)
      let parts = date_time.format_to_parts(formatter, moment, zone:)
      io.println(text <> "\t" <> written_parts(parts))
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
    0, 0 -> date_time.fields_formatter(locale, parse_fields(fields))
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

fn parse_fields(text: String) -> date_time.Fields {
  case text {
    "" -> []
    _ -> string.split(text, ",")
  }
  |> list.fold(date_time.new(), fn(f, option) {
    let assert [name, value] = string.split(option, "=")
    case name {
      "weekday" -> date_time.weekday(f, width(value))
      "era" -> date_time.era(f, width(value))
      "year" -> date_time.year(f, digits(value))
      "month" ->
        case value {
          "numeric" | "2-digit" -> date_time.month(f, digits(value))
          _ -> date_time.month_name(f, width(value))
        }
      "day" -> date_time.day(f, digits(value))
      "dayPeriod" -> date_time.day_period(f, width(value))
      "hour" -> date_time.hour(f, digits(value))
      "minute" -> date_time.minute(f, digits(value))
      "second" -> date_time.second(f, digits(value))
      "fractionalSecondDigits" ->
        date_time.fraction(f, case value {
          "1" -> date_time.Tenths
          "2" -> date_time.Hundredths
          _ -> date_time.Thousandths
        })
      "timeZoneName" ->
        date_time.time_zone_name(f, case value {
          "short" -> date_time.ShortName
          "long" -> date_time.LongName
          "shortOffset" -> date_time.ShortOffset
          _ -> date_time.LongOffset
        })
      _ -> panic as { "unknown field: " <> name }
    }
  })
}

fn width(value: String) -> glintl.Width {
  case value {
    "narrow" -> glintl.Narrow
    "short" -> glintl.Short
    "long" -> glintl.Long
    _ -> panic as { "unknown width: " <> value }
  }
}

fn digits(value: String) -> glintl.Digits {
  case value {
    "numeric" -> glintl.Numeric
    "2-digit" -> glintl.TwoDigit
    _ -> panic as { "unknown digits: " <> value }
  }
}

fn parse_zone(text: String) -> time_zone.TimeZone {
  let zone = case int.parse(text) {
    Ok(minutes) -> time_zone.from_duration(duration.minutes(minutes))
    Error(Nil) ->
      time_zone.from_name(text)
      |> result.replace_error(time_zone.OffsetTooLarge)
  }
  let assert Ok(zone) = zone
  zone
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

/// Between parts, and between each part's type and text, like
/// `PART_SEPARATOR` in `codegen/conformance.ts`.
const part_separator = "\u{1f}"

fn written_parts(parts: List(glintl.DatePart)) -> String {
  parts
  |> list.map(fn(part) { intl_type(part) <> "=" <> glintl.part_text(part) })
  |> string.join(part_separator)
}

/// Intl's name for a part's type.
fn intl_type(part: glintl.DatePart) -> String {
  case part {
    glintl.Era(_) -> "era"
    glintl.Year(_) -> "year"
    glintl.RelatedYear(_) -> "relatedYear"
    glintl.YearName(_) -> "yearName"
    glintl.Month(_) -> "month"
    glintl.Day(_) -> "day"
    glintl.Weekday(_) -> "weekday"
    glintl.DayPeriod(_) -> "dayPeriod"
    glintl.Hour(_) -> "hour"
    glintl.Minute(_) -> "minute"
    glintl.Second(_) -> "second"
    glintl.FractionalSecond(_) -> "fractionalSecond"
    glintl.TimeZoneName(_) -> "timeZoneName"
    glintl.Literal(_) -> "literal"
    glintl.Unknown(_) -> "unknown"
  }
}
