//// Format dates and times, like `Intl.DateTimeFormat` in JavaScript.
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
//// On Erlang, glintl uses data from ICU that we build into the package. On
//// JavaScript, glintl uses the runtime's own `Intl.DateTimeFormat`. So the
//// output can differ slightly between targets, and between JavaScript
//// runtimes.

import gleam/time/timestamp.{type Timestamp}
import glintl.{type DatePart, type Locale}
import glintl/internal/data
import glintl/internal/engine
import glintl/internal/matcher
import glintl/internal/render
import glintl/time_zone.{type TimeZone}

/// How much detail to show, from most to least.
///
/// These are the same as the `dateStyle` and `timeStyle` options of
/// JavaScript's `Intl.DateTimeFormat`. In British English:
///
/// | Style    | Date                       | Time                    |
/// | -------- | -------------------------- | ----------------------- |
/// | `Full`   | Sunday, 25 October 2026    | 23:40:58 GMT+01:00      |
/// | `Long`   | 25 October 2026            | 23:40:58 GMT+1          |
/// | `Medium` | 25 Oct 2026                | 23:40:58                |
/// | `Short`  | 25/10/2026                 | 23:40                   |
pub type Style {
  Full
  Long
  Medium
  Short
}

/// Formats dates and times in one locale and style.
///
/// Making a formatter does the lookup work once, so make one and reuse it.
pub opaque type Formatter {
  Formatter(compiled: engine.Compiled)
}

/// Format only the date.
pub fn date_formatter(locale: Locale, style style: Style) -> Formatter {
  Formatter(engine.styles(locale, render.DateOnly(internal_style(style))))
}

/// Format only the time.
pub fn time_formatter(locale: Locale, style style: Style) -> Formatter {
  Formatter(engine.styles(locale, render.TimeOnly(internal_style(style))))
}

/// Format both the date and the time.
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

/// Format the fields you pick, like the `weekday`, `month` and `hour`
/// options of JavaScript's `Intl.DateTimeFormat`. Start picking them with
/// `new`.
///
/// ```gleam
/// let options =
///   date_time.new()
///   |> date_time.day(glintl.Numeric)
///   |> date_time.month_name(glintl.Short)
///
/// date_time.fields_formatter(en_gb.locale(), options)
/// |> date_time.format(timestamp.system_time(), zone: time_zone.utc)
/// // -> "25 Oct"
/// ```
///
/// Like Intl, the formatter shows a numeric year, month and day when you pick
/// no date or time part. It adds an era or a time zone's name to that date.
pub fn fields_formatter(locale: Locale, fields: Fields) -> Formatter {
  Formatter(engine.fields(locale, fields.request))
}

/// The fields to show and how to write each one, like the `weekday`, `month`
/// and `hour` options of `Intl.DateTimeFormat`. Start with `new`, and make a
/// formatter with `fields_formatter`. Setting a field again replaces it.
pub opaque type Fields {
  Fields(request: matcher.Request)
}

/// How many digits of the fraction of a second to show. Later digits are
/// cut off, not rounded.
pub type Fraction {
  Tenths
  Hundredths
  Thousandths
}

/// How the time zone is written, like Intl's `timeZoneName`. In British
/// English, in summer:
///
/// | Name          | London              | An offset of +1 |
/// | ------------- | ------------------- | --------------- |
/// | `ShortName`   | BST                 | GMT+1           |
/// | `LongName`    | British Summer Time | GMT+01:00       |
/// | `ShortOffset` | GMT+1               | GMT+1           |
/// | `LongOffset`  | GMT+01:00           | GMT+01:00       |
///
/// Where a locale has no name for a zone, the names show the offset too.
pub type TimeZoneName {
  ShortName
  LongName
  ShortOffset
  LongOffset
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

/// Show the time of day in words, like "in the morning", where the locale
/// has them. Next to an hour, the words show on a 12 hour clock only.
pub fn day_period(options: Fields, width: glintl.Width) -> Fields {
  Fields(matcher.Request(..options.request, day_period: engine.width(width)))
}

/// Show the hour, in the locale's hour cycle. Change it with
/// `glintl.with_hour_cycle`.
pub fn hour(options: Fields, digits: glintl.Digits) -> Fields {
  Fields(matcher.Request(..options.request, hour: engine.digits(digits)))
}

/// Show the minute.
pub fn minute(options: Fields, digits: glintl.Digits) -> Fields {
  Fields(matcher.Request(..options.request, minute: engine.digits(digits)))
}

/// Show the second.
pub fn second(options: Fields, digits: glintl.Digits) -> Fields {
  Fields(matcher.Request(..options.request, second: engine.digits(digits)))
}

/// Show the fraction of a second.
pub fn fraction(options: Fields, fraction: Fraction) -> Fields {
  let digits = case fraction {
    Tenths -> 1
    Hundredths -> 2
    Thousandths -> 3
  }
  Fields(matcher.Request(..options.request, fractional_second_digits: digits))
}

/// Show the time zone.
pub fn time_zone_name(options: Fields, name: TimeZoneName) -> Fields {
  let name = case name {
    ShortName -> "short"
    LongName -> "long"
    ShortOffset -> "shortOffset"
    LongOffset -> "longOffset"
  }
  Fields(matcher.Request(..options.request, time_zone_name: name))
}

/// Format a moment as the clocks in `zone` show it.
///
/// For a date with no time or time zone, like a birthday, use `glintl/date`.
pub fn format(
  formatter: Formatter,
  timestamp: Timestamp,
  zone zone: TimeZone,
) -> String {
  let #(seconds, nanoseconds) =
    timestamp.to_unix_seconds_and_nanoseconds(timestamp)
  engine.format(formatter.compiled, seconds, nanoseconds, zone)
}

/// Like `format`, but in parts, so you can style each one. Joining the parts'
/// text gives what `format` returns.
///
/// ```gleam
/// date_time.date_formatter(en_gb.locale(), style: date_time.Long)
/// |> date_time.format_to_parts(moment, zone: time_zone.utc)
/// // -> [
/// //   glintl.Day("26"), glintl.Literal(" "), glintl.Month("October"),
/// //   glintl.Literal(" "), glintl.Year("2026"),
/// // ]
/// ```
pub fn format_to_parts(
  formatter: Formatter,
  timestamp: Timestamp,
  zone zone: TimeZone,
) -> List(DatePart) {
  let #(seconds, nanoseconds) =
    timestamp.to_unix_seconds_and_nanoseconds(timestamp)
  engine.format_to_parts(formatter.compiled, seconds, nanoseconds, zone)
}

fn internal_style(style: Style) -> data.Style {
  case style {
    Full -> data.Full
    Long -> data.Long
    Medium -> data.Medium
    Short -> data.Short
  }
}
