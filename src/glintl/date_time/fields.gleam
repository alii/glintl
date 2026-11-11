//// Pick the parts of a date and time to show, like the `weekday`, `month`
//// and `hour` options of JavaScript's `Intl.DateTimeFormat`. The locale
//// decides their order and the text between them.
////
//// ```gleam
//// import gleam/time/timestamp
//// import glintl/date_time
//// import glintl/date_time/fields
//// import glintl/locale/en_gb
//// import glintl/time_zone
////
//// let formatter =
////   fields.new()
////   |> fields.weekday(fields.Long)
////   |> fields.day(fields.Numeric)
////   |> fields.month_name(fields.Long)
////   |> date_time.fields_formatter(en_gb.locale(), _)
////
//// date_time.format(formatter, timestamp.system_time(), zone: time_zone.utc)
//// // -> "Sunday 25 October"
//// ```
////
//// Setting a field again replaces it. Like Intl, with no date or time part,
//// a formatter shows a numeric year, month and day.

import glintl/internal/matcher

/// The fields to show and how to write each one. Start with `new`.
pub opaque type Fields {
  Fields(request: matcher.Request)
}

/// How wide a name is. In British English, a weekday is `Narrow` "S",
/// `Short` "Sun" or `Long` "Sunday".
pub type Width {
  Narrow
  Short
  Long
}

/// How a number is written. `Numeric` has as many digits as it needs, and
/// `TwoDigit` always has two, like "05", or a year's last two, like "26".
pub type Digits {
  Numeric
  TwoDigit
}

/// How many digits of the fraction of a second to show. Later digits are
/// cut off, not rounded.
pub type Fraction {
  Tenths
  Hundredths
  Thousandths
}

/// How the time zone is written. glintl only knows offsets, so these all
/// show the offset. In British English, an hour ahead of UTC is:
///
/// | Name          | Ahead of UTC | At UTC              |
/// | ------------- | ------------ | ------------------- |
/// | `ShortName`   | GMT+1        | GMT                 |
/// | `LongName`    | GMT+01:00    | Greenwich Mean Time |
/// | `ShortOffset` | GMT+1        | GMT+0               |
/// | `LongOffset`  | GMT+01:00    | GMT+00:00           |
pub type TimeZone {
  ShortName
  LongName
  ShortOffset
  LongOffset
}

/// Makes an empty set of fields. Add the ones you want to show.
pub fn new() -> Fields {
  Fields(matcher.Request(
    weekday: "",
    era: "",
    year: "",
    month: "",
    day: "",
    day_period: "",
    hour: "",
    minute: "",
    second: "",
    fractional_second_digits: 0,
    time_zone_name: "",
    hour_cycle: "",
  ))
}

/// Show the day of the week.
pub fn weekday(fields: Fields, width: Width) -> Fields {
  Fields(matcher.Request(..fields.request, weekday: width_option(width)))
}

/// Show the era, like "AD".
pub fn era(fields: Fields, width: Width) -> Fields {
  Fields(matcher.Request(..fields.request, era: width_option(width)))
}

/// Show the year.
pub fn year(fields: Fields, digits: Digits) -> Fields {
  Fields(matcher.Request(..fields.request, year: digits_option(digits)))
}

/// Show the month as a number, like "3". This replaces `month_name`.
pub fn month(fields: Fields, digits: Digits) -> Fields {
  Fields(matcher.Request(..fields.request, month: digits_option(digits)))
}

/// Show the month's name, like "March". This replaces `month`.
pub fn month_name(fields: Fields, width: Width) -> Fields {
  Fields(matcher.Request(..fields.request, month: width_option(width)))
}

/// Show the day of the month.
pub fn day(fields: Fields, digits: Digits) -> Fields {
  Fields(matcher.Request(..fields.request, day: digits_option(digits)))
}

/// Show the time of day in words, like "in the morning", where the locale
/// has them. With an hour, it only shows on a 12 hour clock.
pub fn day_period(fields: Fields, width: Width) -> Fields {
  Fields(matcher.Request(..fields.request, day_period: width_option(width)))
}

/// Show the hour, in the locale's hour cycle. Change it with
/// `glintl.with_hour_cycle`.
pub fn hour(fields: Fields, digits: Digits) -> Fields {
  Fields(matcher.Request(..fields.request, hour: digits_option(digits)))
}

/// Show the minute.
pub fn minute(fields: Fields, digits: Digits) -> Fields {
  Fields(matcher.Request(..fields.request, minute: digits_option(digits)))
}

/// Show the second.
pub fn second(fields: Fields, digits: Digits) -> Fields {
  Fields(matcher.Request(..fields.request, second: digits_option(digits)))
}

/// Show the fraction of a second.
pub fn fraction(fields: Fields, fraction: Fraction) -> Fields {
  let digits = case fraction {
    Tenths -> 1
    Hundredths -> 2
    Thousandths -> 3
  }
  Fields(matcher.Request(..fields.request, fractional_second_digits: digits))
}

/// Show the time zone.
pub fn time_zone(fields: Fields, time_zone: TimeZone) -> Fields {
  let name = case time_zone {
    ShortName -> "short"
    LongName -> "long"
    ShortOffset -> "shortOffset"
    LongOffset -> "longOffset"
  }
  Fields(matcher.Request(..fields.request, time_zone_name: name))
}

/// Turns the fields into `Intl.DateTimeFormat` options, with the given hour
/// cycle.
@internal
pub fn request(fields: Fields, hour_cycle: String) -> matcher.Request {
  matcher.Request(..fields.request, hour_cycle:)
}

fn width_option(width: Width) -> String {
  case width {
    Narrow -> "narrow"
    Short -> "short"
    Long -> "long"
  }
}

fn digits_option(digits: Digits) -> String {
  case digits {
    Numeric -> "numeric"
    TwoDigit -> "2-digit"
  }
}
