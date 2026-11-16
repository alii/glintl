//// This module formats moments in time the way JavaScript's
//// `Intl.DateTimeFormat` does.
////
//// ```gleam
//// import gleam/time/timestamp
//// import glintl/date_time
//// import glintl/locale/en_gb
//// import glintl/time_zone
////
//// let formatter =
////   date_time.date_time_formatter(
////     en_gb.locale(),
////     date: date_time.Long,
////     time: date_time.Short,
////   )
////
//// let assert Ok(zone) = time_zone.offset(hours: 1, minutes: 0)
////
//// date_time.format(formatter, timestamp.system_time(), zone:)
//// // -> "25 October 2026 at 23:40"
//// ```
////
//// On Erlang, glintl formats with ICU data that's built into the package. On
//// JavaScript, it uses the runtime's `Intl.DateTimeFormat`. The two can differ
//// slightly, and so can different JavaScript runtimes.

import gleam/list
import gleam/time/timestamp.{type Timestamp}
import glintl.{type Locale}
import glintl/internal/data
import glintl/internal/engine
import glintl/internal/matcher
import glintl/internal/render
import glintl/time_zone.{type TimeZone}

/// How much detail to show. `Full` shows the most and `Short` the least.
///
/// These match Intl's `dateStyle` and `timeStyle` options. This is how they look
/// in British English, one hour ahead of UTC:
///
/// | Style    | Date                    | Time               |
/// | -------- | ----------------------- | ------------------ |
/// | `Full`   | Sunday, 25 October 2026 | 23:40:58 GMT+01:00 |
/// | `Long`   | 25 October 2026         | 23:40:58 GMT+1     |
/// | `Medium` | 25 Oct 2026             | 23:40:58           |
/// | `Short`  | 25/10/2026              | 23:40              |
pub type Style {
  Full
  Long
  Medium
  Short
}

/// A formatter for dates and times in one locale.
///
/// Creating a formatter takes some work, so create it once and reuse it.
pub opaque type Formatter {
  Formatter(compiled: engine.Compiled)
}

/// The fields to show and how to write each one. Start with `new`, pick fields
/// with the functions below, then create a formatter with `fields_formatter`.
///
/// Picking a field again replaces it.
pub opaque type Fields {
  Fields(request: matcher.Request)
}

/// How much of a second to show.
///
/// Like Intl, glintl cuts off the digits after these rather than rounding, so
/// 0.98 seconds in tenths is 9.
pub type Fraction {
  Tenths
  Hundredths
  Thousandths
}

/// How to write the time zone.
///
/// This is how London and a zone one hour ahead of UTC look in British English in
/// summer:
///
/// | Style          | London              | One hour ahead |
/// | -------------- | ------------------- | -------------- |
/// | `ShortName`    | BST                 | GMT+1          |
/// | `LongName`     | British Summer Time | GMT+01:00      |
/// | `ShortOffset`  | GMT+1               | GMT+1          |
/// | `LongOffset`   | GMT+01:00           | GMT+01:00      |
/// | `ShortGeneric` | United Kingdom Time | GMT+1          |
/// | `LongGeneric`  | British Time        | GMT+01:00      |
///
/// Generic names don't change between summer and winter. When a locale has no
/// generic name for a zone, glintl names its country or city instead. When it has
/// no name at all, glintl shows the offset.
pub type TimeZoneStyle {
  ShortName
  LongName
  ShortOffset
  LongOffset
  ShortGeneric
  LongGeneric
}

/// Create a formatter that shows the date in a style.
pub fn date_formatter(locale: Locale, style style: Style) -> Formatter {
  Formatter(engine.styles(locale, render.DateOnly(internal_style(style))))
}

/// Create a formatter that shows the time in a style.
pub fn time_formatter(locale: Locale, style style: Style) -> Formatter {
  Formatter(engine.styles(locale, render.TimeOnly(internal_style(style))))
}

/// Create a formatter that shows the date and the time, each in its own style.
pub fn date_time_formatter(
  locale: Locale,
  date date: Style,
  time time: Style,
) -> Formatter {
  Formatter(engine.styles(
    locale,
    render.DateAndTime(date: internal_style(date), time: internal_style(time)),
  ))
}

/// Create a formatter that shows the fields you pick, like the `weekday`,
/// `month` and `hour` options of `Intl.DateTimeFormat`.
///
/// ```gleam
/// let fields =
///   date_time.new()
///   |> date_time.day(glintl.Numeric)
///   |> date_time.month_name(glintl.Short)
///
/// date_time.fields_formatter(en_gb.locale(), fields)
/// |> date_time.format(timestamp.system_time(), zone: time_zone.utc)
/// // -> "25 Oct"
/// ```
///
/// If you don't pick any date or time fields, the formatter shows a numeric date
/// like Intl does. An era or time zone you pick goes with it.
pub fn fields_formatter(locale: Locale, fields: Fields) -> Formatter {
  Formatter(engine.fields(locale, fields.request))
}

/// Start a set of fields with nothing picked.
pub fn new() -> Fields {
  Fields(engine.no_fields)
}

/// Show the day of the week.
pub fn weekday(fields: Fields, width: glintl.Width) -> Fields {
  Fields(matcher.Request(..fields.request, weekday: engine.width(width)))
}

/// Show the era. In English, this is "AD" or "BC".
pub fn era(fields: Fields, width: glintl.Width) -> Fields {
  Fields(matcher.Request(..fields.request, era: engine.width(width)))
}

/// Show the year.
pub fn year(fields: Fields, digits: glintl.Digits) -> Fields {
  Fields(matcher.Request(..fields.request, year: engine.digits(digits)))
}

/// Show the month as a number. This replaces `month_name`, because a date only
/// shows its month once.
pub fn month(fields: Fields, digits: glintl.Digits) -> Fields {
  Fields(matcher.Request(..fields.request, month: engine.digits(digits)))
}

/// Show the month's name. This replaces `month`, because a date only shows its
/// month once.
pub fn month_name(fields: Fields, width: glintl.Width) -> Fields {
  Fields(matcher.Request(..fields.request, month: engine.width(width)))
}

/// Show the day of the month.
pub fn day(fields: Fields, digits: glintl.Digits) -> Fields {
  Fields(matcher.Request(..fields.request, day: engine.digits(digits)))
}

/// Show words for the time of day where the locale has them. In English, these
/// are "in the morning", "in the afternoon" and so on.
///
/// Next to an hour, the words only show with a 12 hour clock.
pub fn day_period(fields: Fields, width: glintl.Width) -> Fields {
  Fields(matcher.Request(..fields.request, day_period: engine.width(width)))
}

/// Show the hour.
///
/// Whether this runs from 1 to 12 or 0 to 23 depends on the locale's hour cycle,
/// which you can change with `glintl.with_hour_cycle`.
pub fn hour(fields: Fields, digits: glintl.Digits) -> Fields {
  Fields(matcher.Request(..fields.request, hour: engine.digits(digits)))
}

/// Show the minute.
pub fn minute(fields: Fields, digits: glintl.Digits) -> Fields {
  Fields(matcher.Request(..fields.request, minute: engine.digits(digits)))
}

/// Show the second.
pub fn second(fields: Fields, digits: glintl.Digits) -> Fields {
  Fields(matcher.Request(..fields.request, second: engine.digits(digits)))
}

/// Show tenths, hundredths or thousandths of a second.
pub fn fractional_second(fields: Fields, fraction: Fraction) -> Fields {
  let digits = case fraction {
    Tenths -> 1
    Hundredths -> 2
    Thousandths -> 3
  }
  Fields(matcher.Request(..fields.request, fractional_second_digits: digits))
}

/// Show the time zone.
pub fn time_zone_name(fields: Fields, style: TimeZoneStyle) -> Fields {
  let name = case style {
    ShortName -> "short"
    LongName -> "long"
    ShortOffset -> "shortOffset"
    LongOffset -> "longOffset"
    ShortGeneric -> "shortGeneric"
    LongGeneric -> "longGeneric"
  }
  Fields(matcher.Request(..fields.request, time_zone_name: name))
}

/// Format a moment as the clocks in a time zone show it.
///
/// To format a birthday or another date without a time, use `glintl/date`.
pub fn format(
  formatter: Formatter,
  timestamp: Timestamp,
  zone zone: TimeZone,
) -> String {
  let #(seconds, nanoseconds) =
    timestamp.to_unix_seconds_and_nanoseconds(timestamp)
  engine.format(formatter.compiled, seconds, nanoseconds, zone)
}

/// Format a moment in parts so you can style each one.
///
/// ```gleam
/// date_time.date_formatter(en_gb.locale(), style: date_time.Long)
/// |> date_time.format_to_parts(timestamp.system_time(), zone: time_zone.utc)
/// // -> [
/// //   date_time.Day("25"), date_time.Literal(" "), date_time.Month("October"),
/// //   date_time.Literal(" "), date_time.Year("2026"),
/// // ]
/// ```
///
/// Joining the text of every part gives the same as `format`.
pub fn format_to_parts(
  formatter: Formatter,
  timestamp: Timestamp,
  zone zone: TimeZone,
) -> List(Part) {
  let #(seconds, nanoseconds) =
    timestamp.to_unix_seconds_and_nanoseconds(timestamp)
  engine.format_to_parts(formatter.compiled, seconds, nanoseconds, zone)
  |> list.map(fn(part) { to_part(part.0, part.1) })
}

/// A part of a formatted date or time.
///
/// ```gleam
/// [Day("25"), Literal(" "), Month("October"), Literal(" "), Year("2026")]
/// ```
pub type Part {
  Era(String)
  Year(String)
  /// The Gregorian year of a Chinese or Korean date.
  RelatedYear(String)
  /// The name of a Chinese or Korean year in the 60 year cycle.
  YearName(String)
  Month(String)
  Day(String)
  Weekday(String)
  DayPeriod(String)
  Hour(String)
  Minute(String)
  Second(String)
  FractionalSecond(String)
  TimeZoneName(String)
  /// Text between fields such as spaces and punctuation.
  Literal(String)
  /// A field without a type of its own, like the week-based year.
  Unknown(String)
}

/// Get the text of a part.
pub fn part_text(part: Part) -> String {
  case part {
    Era(text)
    | Year(text)
    | RelatedYear(text)
    | YearName(text)
    | Month(text)
    | Day(text)
    | Weekday(text)
    | DayPeriod(text)
    | Hour(text)
    | Minute(text)
    | Second(text)
    | FractionalSecond(text)
    | TimeZoneName(text)
    | Literal(text)
    | Unknown(text) -> text
  }
}

fn to_part(intl_type: String, text: String) -> Part {
  case intl_type {
    "era" -> Era(text)
    "year" -> Year(text)
    "relatedYear" -> RelatedYear(text)
    "yearName" -> YearName(text)
    "month" -> Month(text)
    "day" -> Day(text)
    "weekday" -> Weekday(text)
    "dayPeriod" -> DayPeriod(text)
    "hour" -> Hour(text)
    "minute" -> Minute(text)
    "second" -> Second(text)
    "fractionalSecond" -> FractionalSecond(text)
    "timeZoneName" -> TimeZoneName(text)
    "literal" -> Literal(text)
    _ -> Unknown(text)
  }
}

fn internal_style(style: Style) -> data.Style {
  case style {
    Full -> data.Full
    Long -> data.Long
    Medium -> data.Medium
    Short -> data.Short
  }
}
