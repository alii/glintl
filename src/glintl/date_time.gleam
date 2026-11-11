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
//// On Erlang the formats come from data baked into this package, made from
//// ICU when the package is built. On JavaScript the runtime's own
//// `Intl.DateTimeFormat` is used, so the output can differ slightly between
//// targets and between JavaScript runtimes.

import gleam/time/timestamp.{type Timestamp}
import glintl.{type Locale}
import glintl/date_time/fields.{type Fields}
import glintl/internal/data
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

/// Format the fields you pick, like the `weekday`, `month` and `hour`
/// options of JavaScript's `Intl.DateTimeFormat`. See `glintl/date_time/fields`.
///
/// ```gleam
/// let options =
///   fields.new()
///   |> fields.day(fields.Numeric)
///   |> fields.month_name(fields.Short)
///
/// date_time.fields_formatter(en_gb.locale(), options)
/// |> date_time.format(timestamp.system_time(), zone: time_zone.utc)
/// // -> "25 Oct"
/// ```
///
/// Like Intl, if you pick no date or time part, this adds a numeric year,
/// month and day. An era or a time zone's name is added to that.
pub fn fields_formatter(locale: Locale, fields: Fields) -> Formatter {
  let request = fields.request(fields, glintl.intl_hour_cycle_option(locale))
  let matcher.Request(
    weekday:,
    year:,
    month:,
    day:,
    day_period:,
    hour:,
    minute:,
    second:,
    fractional_second_digits:,
    ..,
  ) = request
  let shown =
    [weekday, year, month, day, day_period, hour, minute, second]
    |> list_any_set
  case shown || fractional_second_digits > 0 {
    True -> new_fields(locale, request)
    False ->
      new_fields(
        locale,
        matcher.Request(..request, year: numeric, month: numeric, day: numeric),
      )
  }
}

/// Intl's value for a number with as many digits as it needs.
const numeric = "numeric"

fn list_any_set(options: List(String)) -> Bool {
  case options {
    [] -> False
    ["", ..rest] -> list_any_set(rest)
    [_, ..] -> True
  }
}

/// Format a moment as the clocks in `zone` show it.
///
/// A date with no time zone, like a birthday, is a moment at UTC shown in
/// UTC:
///
/// ```gleam
/// let birthday =
///   timestamp.from_calendar(
///     date: calendar.Date(2026, calendar.October, 26),
///     time: calendar.TimeOfDay(0, 0, 0, 0),
///     offset: calendar.utc_offset,
///   )
///
/// date_time.date_formatter(en_gb.locale(), style: date_time.Long)
/// |> date_time.format(birthday, zone: time_zone.utc)
/// // -> "26 October 2026"
/// ```
///
/// Time zones are written as a GMT offset, like `GMT+1`, because glintl knows
/// the offset but not the zone's name.
pub fn format(
  formatter: Formatter,
  timestamp: Timestamp,
  zone zone: TimeZone,
) -> String {
  let #(seconds, nanoseconds) =
    timestamp.to_unix_seconds_and_nanoseconds(timestamp)
  do_format(
    formatter.compiled,
    seconds,
    nanoseconds,
    time_zone.offset_minutes(zone),
  )
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

@target(erlang)
fn new_fields(locale: Locale, request: matcher.Request) -> Formatter {
  let calendar = glintl.locale_calendar(locale)
  Formatter(
    render.compile_fields(
      glintl.locale_data(locale),
      glintl.calendar_position(calendar),
      request,
      glintl.icu_calendar(calendar),
      fn() { calendar_math(calendar) },
    ),
  )
}

@target(javascript)
fn new_fields(locale: Locale, request: matcher.Request) -> Formatter {
  Formatter(intl_fields_formatter(
    glintl.locale_tag(locale),
    glintl.icu_calendar(glintl.locale_calendar(locale)),
    request,
  ))
}

@target(javascript)
@external(javascript, "../glintl_ffi.mjs", "fieldsFormatter")
fn intl_fields_formatter(
  tag: String,
  calendar: String,
  request: matcher.Request,
) -> IntlFormatter

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
const nanoseconds_per_millisecond = 1_000_000

@target(erlang)
fn do_format(
  formatter: render.Compiled,
  seconds: Int,
  nanoseconds: Int,
  offset_minutes: Int,
) -> String {
  render.render(
    formatter,
    seconds,
    nanoseconds / nanoseconds_per_millisecond,
    offset_minutes,
  )
}

@target(javascript)
@external(javascript, "../glintl_ffi.mjs", "format")
fn do_format(
  formatter: IntlFormatter,
  seconds: Int,
  nanoseconds: Int,
  offset_minutes: Int,
) -> String
