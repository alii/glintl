//// Format dates that have no time or time zone, like birthdays. For moments
//// in time, use `glintl/date_time`.
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
//// You can also pick the parts to show, like the date options of
//// `Intl.DateTimeFormat`:
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
////

import gleam/time/calendar
import gleam/time/timestamp
import glintl.{type DateTimePart, type Locale}
import glintl/internal/data
import glintl/internal/engine
import glintl/internal/matcher
import glintl/internal/render
import glintl/time_zone

/// How much detail to show, from most to least.
///
/// These are the same as the `dateStyle` option of JavaScript's
/// `Intl.DateTimeFormat`. In British English:
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

/// Formats dates in one locale and style.
///
/// Making a formatter does the lookup work once, so make one and reuse it.
pub opaque type Formatter {
  Formatter(compiled: engine.Compiled)
}

/// The fields to show and how to write each one, like the `weekday`, `month`
/// and `day` options of `Intl.DateTimeFormat`. Start with `new`, and make a
/// formatter with `fields_formatter`. Setting a field again replaces it.
pub opaque type Fields {
  Fields(request: matcher.Request)
}

/// Format the date in a style.
pub fn date_formatter(locale: Locale, style style: Style) -> Formatter {
  Formatter(engine.styles(locale, render.DateOnly(internal_style(style))))
}

/// Format the fields you pick, like the `weekday`, `month` and `day` options
/// of JavaScript's `Intl.DateTimeFormat`. Start picking them with `new`.
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
/// Like Intl, the formatter shows a numeric year, month and day when you pick
/// no year, month, day or weekday. It adds an era to that date.
pub fn fields_formatter(locale: Locale, fields: Fields) -> Formatter {
  Formatter(engine.fields(locale, fields.request))
}

/// Start picking the fields to show.
pub fn new() -> Fields {
  Fields(engine.no_fields)
}

/// Show the day of the week.
pub fn weekday(fields: Fields, width: glintl.Width) -> Fields {
  Fields(matcher.Request(..fields.request, weekday: engine.width(width)))
}

/// Show the era, like "AD".
pub fn era(fields: Fields, width: glintl.Width) -> Fields {
  Fields(matcher.Request(..fields.request, era: engine.width(width)))
}

/// Show the year.
pub fn year(fields: Fields, digits: glintl.Digits) -> Fields {
  Fields(matcher.Request(..fields.request, year: engine.digits(digits)))
}

/// Show the month as a number, like "3". This replaces `month_name`.
pub fn month(fields: Fields, digits: glintl.Digits) -> Fields {
  Fields(matcher.Request(..fields.request, month: engine.digits(digits)))
}

/// Show the month's name, like "March". This replaces `month`.
pub fn month_name(fields: Fields, width: glintl.Width) -> Fields {
  Fields(matcher.Request(..fields.request, month: engine.width(width)))
}

/// Show the day of the month.
pub fn day(fields: Fields, digits: glintl.Digits) -> Fields {
  Fields(matcher.Request(..fields.request, day: engine.digits(digits)))
}

/// Format a date. A date that doesn't exist rolls over, like gleam_time's
/// `timestamp.from_calendar`, so 31 February 2026 is 3 March.
pub fn format(formatter: Formatter, date: calendar.Date) -> String {
  engine.format(formatter.compiled, seconds(date), 0, time_zone.utc)
}

/// Like `format`, but in parts, so you can style each one. Joining the parts'
/// text gives what `format` returns.
///
/// ```gleam
/// date.date_formatter(en_gb.locale(), style: date.Long)
/// |> date.format_to_parts(calendar.Date(2026, calendar.October, 25))
/// // -> [
/// //   glintl.Day("25"), glintl.Literal(" "), glintl.Month("October"),
/// //   glintl.Literal(" "), glintl.Year("2026"),
/// // ]
/// ```
pub fn format_to_parts(
  formatter: Formatter,
  date: calendar.Date,
) -> List(DateTimePart) {
  engine.format_to_parts(formatter.compiled, seconds(date), 0, time_zone.utc)
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
