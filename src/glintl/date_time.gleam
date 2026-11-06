//// Format dates and times, like `Intl.DateTimeFormat` in JavaScript.
////
//// ```gleam
//// import gleam/time/timestamp
//// import glintl/date_time
//// import glintl/locale/en_gb
////
//// let formatter =
////   date_time.date_time_formatter(
////     en_gb.locale(),
////     date: date_time.Long,
////     time: date_time.Short,
////   )
////
//// let assert Ok(offset) = date_time.offset(hours: 1, minutes: 0)
////
//// date_time.format(formatter, timestamp.system_time(), offset:)
//// // -> "25 October 2026 at 23:40"
//// ```
////
//// On Erlang the formats come from data baked into this package, made from
//// ICU when the package is built. On JavaScript the runtime's own
//// `Intl.DateTimeFormat` is used, so the output can differ slightly between
//// targets and between JavaScript runtimes.

import gleam/int
import gleam/time/calendar
import gleam/time/duration.{type Duration}
import gleam/time/timestamp.{type Timestamp}
import glintl.{type Locale}
import glintl/internal/data
import glintl/internal/render

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

@target(erlang)
/// Formats dates and times in one locale and style.
///
/// Making a formatter does the lookup work once, so make one and reuse it.
pub opaque type Formatter {
  Formatter(compiled: render.Compiled)
}

@target(javascript)
pub opaque type Formatter {
  Formatter(compiled: IntlFormatter)
}

@target(javascript)
/// An `Intl.DateTimeFormat` for each offset.
type IntlFormatter

/// Format only the date.
pub fn date_formatter(locale: Locale, style style: Style) -> Formatter {
  new(locale, render.DateOnly(internal_style(style)))
}

/// Format only the time.
pub fn time_formatter(locale: Locale, style style: Style) -> Formatter {
  new(locale, render.TimeOnly(internal_style(style)))
}

/// Format both the date and the time.
pub fn date_time_formatter(
  locale: Locale,
  date date: Style,
  time time: Style,
) -> Formatter {
  new(
    locale,
    render.DateAndTime(date: internal_style(date), time: internal_style(time)),
  )
}

/// How far a place's clocks are ahead of UTC. It's a whole number of minutes,
/// under 24 hours either way.
pub opaque type Offset {
  Offset(minutes: Int)
}

/// The offset of UTC, which is zero.
pub const utc = Offset(minutes: 0)

const seconds_per_minute = 60

const minutes_per_hour = 60

const hours_per_day = 24

/// Why an offset couldn't be made.
pub type OffsetError {
  /// `hours` and `minutes` have different signs, like
  /// `offset(hours: -3, minutes: 30)`.
  MixedSigns
  /// `minutes` is an hour or more either way.
  MinutesTooLarge
  /// The offset is 24 hours or more either way.
  OffsetTooLarge
}

/// An offset of `hours` and `minutes` ahead of UTC, like
/// `offset(hours: 5, minutes: 30)` for India. Behind UTC both are negative,
/// like `offset(hours: -3, minutes: -30)` for Newfoundland.
pub fn offset(
  hours hours: Int,
  minutes minutes: Int,
) -> Result(Offset, OffsetError) {
  let same_sign =
    { hours >= 0 && minutes >= 0 } || { hours <= 0 && minutes <= 0 }
  case same_sign, int.absolute_value(minutes) < minutes_per_hour {
    False, _ -> Error(MixedSigns)
    True, False -> Error(MinutesTooLarge)
    True, True -> from_minutes(hours * minutes_per_hour + minutes)
  }
}

/// An offset from a `gleam_time` duration, like `calendar.local_offset()`,
/// rounded down to whole minutes.
pub fn duration_to_offset(duration: Duration) -> Result(Offset, OffsetError) {
  let #(seconds, _) = duration.to_seconds_and_nanoseconds(duration)
  let remainder =
    { seconds % seconds_per_minute + seconds_per_minute } % seconds_per_minute
  from_minutes({ seconds - remainder } / seconds_per_minute)
}

fn from_minutes(minutes: Int) -> Result(Offset, OffsetError) {
  case int.absolute_value(minutes) < hours_per_day * minutes_per_hour {
    True -> Ok(Offset(minutes:))
    False -> Error(OffsetTooLarge)
  }
}

/// Format a timestamp in the local time of a place `offset` ahead of UTC.
///
/// Time zones are written as a GMT offset, like `GMT+1`, because glintl knows
/// the offset but not the zone's name.
pub fn format(
  formatter: Formatter,
  timestamp: Timestamp,
  offset offset: Offset,
) -> String {
  let #(seconds, nanoseconds) =
    timestamp.to_unix_seconds_and_nanoseconds(timestamp)
  do_format(formatter.compiled, seconds, nanoseconds, offset.minutes)
}

/// Format a date, like a birthday, that isn't tied to a time zone. If the
/// formatter shows a time, it shows midnight.
///
/// ```gleam
/// date_time.date_formatter(en_gb.locale(), style: date_time.Long)
/// |> date_time.format_date(calendar.Date(2026, calendar.October, 26))
/// // -> "26 October 2026"
/// ```
pub fn format_date(formatter: Formatter, date: calendar.Date) -> String {
  format_date_time(formatter, date, calendar.TimeOfDay(0, 0, 0, 0))
}

/// Format a date and a time of day that aren't tied to a time zone. If the
/// formatter shows a time zone, it shows UTC.
pub fn format_date_time(
  formatter: Formatter,
  date: calendar.Date,
  time: calendar.TimeOfDay,
) -> String {
  timestamp.from_calendar(date:, time:, offset: calendar.utc_offset)
  |> format(formatter, _, offset: utc)
}

@target(erlang)
fn new(locale: Locale, shown: render.Shown) -> Formatter {
  let calendar = glintl.locale_calendar(locale)
  let data = glintl.locale_data(locale)
  let cycle = glintl.hour_cycle_number(locale)
  Formatter(case calendar {
    glintl.Gregorian -> render.compile(data, cycle, shown)
    _ ->
      render.compile_other(
        data,
        glintl.calendar_position(calendar),
        cycle,
        fn() { calendar_math(calendar) },
        shown,
      )
  })
}

@target(javascript)
fn new(locale: Locale, shown: render.Shown) -> Formatter {
  let #(date_style, time_style) = case shown {
    render.DateOnly(date) -> #(intl_style(date), "")
    render.TimeOnly(time) -> #("", intl_style(time))
    render.DateAndTime(date:, time:) -> #(intl_style(date), intl_style(time))
  }
  Formatter(intl_formatter(
    glintl.locale_tag(locale),
    glintl.icu_calendar(glintl.locale_calendar(locale)),
    date_style,
    time_style,
    glintl.intl_hour_cycle_option(locale),
  ))
}

@target(javascript)
/// `""` means no style.
@external(javascript, "../glintl_ffi.mjs", "formatter")
fn intl_formatter(
  tag: String,
  calendar: String,
  date_style: String,
  time_style: String,
  hour_cycle: String,
) -> IntlFormatter

fn internal_style(style: Style) -> data.Style {
  case style {
    Full -> data.Full
    Long -> data.Long
    Medium -> data.Medium
    Short -> data.Short
  }
}

@target(javascript)
/// `dateStyle` and `timeStyle` for `Intl.DateTimeFormat`.
fn intl_style(style: data.Style) -> String {
  case style {
    data.Full -> "full"
    data.Long -> "long"
    data.Medium -> "medium"
    data.Short -> "short"
  }
}

@target(erlang)
/// How a calendar maps days to its own dates. Used by the tests.
@internal
pub fn calendar_math(calendar: glintl.Calendar) -> data.Math {
  case calendar {
    glintl.Gregorian -> data.gregorian
    glintl.Iso8601 -> iso8601_math()
    glintl.Buddhist -> buddhist_math()
    glintl.Japanese -> japanese_math()
    glintl.RepublicOfChina -> republic_of_china_math()
    glintl.Persian -> persian_math()
    glintl.Indian -> indian_math()
    glintl.Hebrew -> hebrew_math()
    glintl.Chinese -> chinese_math()
    glintl.Dangi -> dangi_math()
    glintl.Coptic -> coptic_math()
    glintl.Ethiopic -> ethiopic_math()
    glintl.EthiopicAmeteAlem -> ethiopic_amete_alem_math()
    glintl.IslamicCivil -> islamic_civil_math()
    glintl.IslamicTabular -> islamic_tabular_math()
    glintl.IslamicUmmAlQura -> islamic_umm_al_qura_math()
  }
}

// Each calendar's generated maths.

@target(erlang)
@external(erlang, "glintl_generated_calendar_iso8601", "math")
fn iso8601_math() -> data.Math

@target(erlang)
@external(erlang, "glintl_generated_calendar_buddhist", "math")
fn buddhist_math() -> data.Math

@target(erlang)
@external(erlang, "glintl_generated_calendar_japanese", "math")
fn japanese_math() -> data.Math

@target(erlang)
@external(erlang, "glintl_generated_calendar_roc", "math")
fn republic_of_china_math() -> data.Math

@target(erlang)
@external(erlang, "glintl_generated_calendar_persian", "math")
fn persian_math() -> data.Math

@target(erlang)
@external(erlang, "glintl_generated_calendar_indian", "math")
fn indian_math() -> data.Math

@target(erlang)
@external(erlang, "glintl_generated_calendar_hebrew", "math")
fn hebrew_math() -> data.Math

@target(erlang)
@external(erlang, "glintl_generated_calendar_chinese", "math")
fn chinese_math() -> data.Math

@target(erlang)
@external(erlang, "glintl_generated_calendar_dangi", "math")
fn dangi_math() -> data.Math

@target(erlang)
@external(erlang, "glintl_generated_calendar_coptic", "math")
fn coptic_math() -> data.Math

@target(erlang)
@external(erlang, "glintl_generated_calendar_ethiopic", "math")
fn ethiopic_math() -> data.Math

@target(erlang)
@external(erlang, "glintl_generated_calendar_ethioaa", "math")
fn ethiopic_amete_alem_math() -> data.Math

@target(erlang)
@external(erlang, "glintl_generated_calendar_islamic_civil", "math")
fn islamic_civil_math() -> data.Math

@target(erlang)
@external(erlang, "glintl_generated_calendar_islamic_tbla", "math")
fn islamic_tabular_math() -> data.Math

@target(erlang)
@external(erlang, "glintl_generated_calendar_islamic_umalqura", "math")
fn islamic_umm_al_qura_math() -> data.Math

@target(erlang)
fn do_format(
  formatter: render.Compiled,
  seconds: Int,
  _nanoseconds: Int,
  offset_minutes: Int,
) -> String {
  render.render(formatter, seconds, offset_minutes)
}

@target(javascript)
@external(javascript, "../glintl_ffi.mjs", "format")
fn do_format(
  formatter: IntlFormatter,
  seconds: Int,
  nanoseconds: Int,
  offset_minutes: Int,
) -> String
