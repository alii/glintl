//// Format dates that have no time or time zone, like birthdays. For moments
//// in time, use `glintl/date_time`.
////
//// ```gleam
//// import gleam/time/calendar
//// import glintl/date
//// import glintl/locale/en_gb
////
//// let formatter = date.formatter(en_gb.locale(), style: date.Long)
////
//// date.format(formatter, calendar.Date(2026, calendar.October, 26))
//// // -> "26 October 2026"
//// ```
////
//// Or pick the parts to show, like the date options of `Intl.DateTimeFormat`:
////
//// ```gleam
//// import glintl
////
//// let options =
////   date.new()
////   |> date.weekday(glintl.Long)
////   |> date.day(glintl.Numeric)
////   |> date.month_name(glintl.Long)
////
//// date.fields_formatter(en_gb.locale(), options)
//// |> date.format(calendar.Date(2026, calendar.October, 26))
//// // -> "Monday 26 October"
//// ```
////
//// Like Intl, with no year, month, day or weekday, a formatter shows a
//// numeric date.

import gleam/time/calendar
import gleam/time/timestamp
import glintl.{type Locale}
import glintl/internal/data
import glintl/internal/engine
import glintl/internal/matcher
import glintl/internal/render

/// How much detail to show, from most to least.
///
/// These are the same as the `dateStyle` option of JavaScript's
/// `Intl.DateTimeFormat`. In British English:
///
/// | Style    | Date                    |
/// | -------- | ----------------------- |
/// | `Full`   | Monday, 26 October 2026 |
/// | `Long`   | 26 October 2026         |
/// | `Medium` | 26 Oct 2026             |
/// | `Short`  | 26/10/2026              |
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

/// The fields of a date to show and how to write each one, like the
/// `weekday`, `month` and `day` options of `Intl.DateTimeFormat`. Start with
/// `new`, and make a formatter with `fields_formatter`. Setting a field again
/// replaces it.
pub opaque type Fields {
  Fields(request: matcher.Request)
}

/// Format the date in a style.
pub fn formatter(locale: Locale, style style: Style) -> Formatter {
  let style = case style {
    Full -> data.Full
    Long -> data.Long
    Medium -> data.Medium
    Short -> data.Short
  }
  Formatter(engine.styles(locale, render.DateOnly(style)))
}

/// Format the fields you pick. Start picking them with `new`.
pub fn fields_formatter(locale: Locale, fields: Fields) -> Formatter {
  Formatter(engine.fields(locale, fields.request))
}

/// Format a date.
pub fn format(formatter: Formatter, date: calendar.Date) -> String {
  // Date formatters never show a time or a time zone, so any time works.
  let #(seconds, _) =
    timestamp.from_calendar(
      date:,
      time: calendar.TimeOfDay(0, 0, 0, 0),
      offset: calendar.utc_offset,
    )
    |> timestamp.to_unix_seconds_and_nanoseconds
  engine.format(formatter.compiled, seconds, 0, 0)
}

/// Start picking the fields to show.
pub fn new() -> Fields {
  Fields(engine.no_fields)
}

/// Show the day of the week.
pub fn weekday(options: Fields, width: glintl.Width) -> Fields {
  Fields(matcher.Request(..options.request, weekday: engine.width(width)))
}

/// Show the era, like "AD".
pub fn era(options: Fields, width: glintl.Width) -> Fields {
  Fields(matcher.Request(..options.request, era: engine.width(width)))
}

/// Show the year.
pub fn year(options: Fields, digits: glintl.Digits) -> Fields {
  Fields(matcher.Request(..options.request, year: engine.digits(digits)))
}

/// Show the month as a number, like "3". This replaces `month_name`.
pub fn month(options: Fields, digits: glintl.Digits) -> Fields {
  Fields(matcher.Request(..options.request, month: engine.digits(digits)))
}

/// Show the month's name, like "March". This replaces `month`.
pub fn month_name(options: Fields, width: glintl.Width) -> Fields {
  Fields(matcher.Request(..options.request, month: engine.width(width)))
}

/// Show the day of the month.
pub fn day(options: Fields, digits: glintl.Digits) -> Fields {
  Fields(matcher.Request(..options.request, day: engine.digits(digits)))
}
