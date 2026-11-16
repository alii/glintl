//// This module is for formatting birthdays and other dates that have no time or
//// time zone. To format a moment in time, use `glintl/date_time`.
////
//// ```gleam
//// import gleam/time/calendar
//// import glintl/date
//// import glintl/locale/en_gb
////
//// let formatter = date.date_formatter(en_gb.locale(), style: date.Long)
////
//// date.format(formatter, calendar.Date(2026, calendar.October, 25))
//// // -> "25 October 2026"
//// ```
////
//// You can also pick which fields to show:
////
//// ```gleam
//// import glintl
////
//// let fields =
////   date.new()
////   |> date.weekday(glintl.Long)
////   |> date.day(glintl.Numeric)
////   |> date.month_name(glintl.Long)
////
//// date.fields_formatter(en_gb.locale(), fields)
//// |> date.format(calendar.Date(2026, calendar.October, 25))
//// // -> "Sunday 25 October"
//// ```

import gleam/list
import gleam/time/calendar
import gleam/time/timestamp
import glintl.{type Locale}
import glintl/internal/data
import glintl/internal/engine
import glintl/internal/matcher
import glintl/internal/render
import glintl/time_zone

/// How much detail to show. `Full` shows the most and `Short` the least.
///
/// These match Intl's `dateStyle` option. This is how they look in British
/// English:
///
/// | Style    | Date                    |
/// | -------- | ----------------------- |
/// | `Full`   | Sunday, 25 October 2026 |
/// | `Long`   | 25 October 2026         |
/// | `Medium` | 25 Oct 2026             |
/// | `Short`  | 25/10/2026              |
pub type Style {
  Full
  Long
  Medium
  Short
}

/// A formatter for dates in one locale.
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

/// Create a formatter that shows a date in a style.
pub fn date_formatter(locale: Locale, style style: Style) -> Formatter {
  Formatter(engine.styles(locale, render.DateOnly(internal_style(style))))
}

/// Create a formatter that shows the fields you pick, like the `weekday`,
/// `month` and `day` options of `Intl.DateTimeFormat`.
///
/// ```gleam
/// let fields =
///   date.new()
///   |> date.day(glintl.Numeric)
///   |> date.month_name(glintl.Short)
///
/// date.fields_formatter(en_gb.locale(), fields)
/// |> date.format(calendar.Date(2026, calendar.October, 25))
/// // -> "25 Oct"
/// ```
///
/// If you don't pick a year, month, day or weekday, the formatter shows a
/// numeric date like Intl does. An era you pick goes with it.
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

/// Format a date.
///
/// A date that doesn't exist rolls over, so 31 February 2026 is formatted as
/// 3 March.
pub fn format(formatter: Formatter, date: calendar.Date) -> String {
  engine.format(formatter.compiled, seconds(date), 0, time_zone.utc)
}

/// Format a date in parts so you can style each one.
///
/// ```gleam
/// date.date_formatter(en_gb.locale(), style: date.Long)
/// |> date.format_to_parts(calendar.Date(2026, calendar.October, 25))
/// // -> [
/// //   date.Day("25"), date.Literal(" "), date.Month("October"),
/// //   date.Literal(" "), date.Year("2026"),
/// // ]
/// ```
///
/// Joining the text of every part gives the same as `format`.
pub fn format_to_parts(
  formatter: Formatter,
  date: calendar.Date,
) -> List(Part) {
  engine.format_to_parts(formatter.compiled, seconds(date), 0, time_zone.utc)
  |> list.map(fn(part) { to_part(part.0, part.1) })
}

/// A part of a formatted date.
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
    "literal" -> Literal(text)
    _ -> Unknown(text)
  }
}

fn seconds(date: calendar.Date) -> Int {
  // Date formatters never show a time or a time zone, so any time works.
  let #(seconds, _) =
    timestamp.from_calendar(
      date:,
      time: calendar.TimeOfDay(0, 0, 0, 0),
      offset: calendar.utc_offset,
    )
    |> timestamp.to_unix_seconds_and_nanoseconds
  seconds
}

fn internal_style(style: Style) -> data.Style {
  case style {
    Full -> data.Full
    Long -> data.Long
    Medium -> data.Medium
    Short -> data.Short
  }
}
