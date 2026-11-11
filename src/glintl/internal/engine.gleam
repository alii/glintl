//// The engine behind `glintl/date` and `glintl/date_time`. It turns picked
//// fields or styles into a formatter, and formats with it.

import glintl.{type Locale}
import glintl/internal/data
import glintl/internal/matcher
import glintl/internal/render
import glintl/time_zone.{type TimeZone}

@target(erlang)
pub type Compiled =
  render.Compiled

@target(javascript)
/// An `Intl.DateTimeFormat` for each time zone.
pub type Compiled

/// No fields picked yet.
pub const no_fields =
  matcher.Request(
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
  )

/// Intl's value for a number with as many digits as it needs.
const numeric = "numeric"

pub fn width(width: glintl.Width) -> String {
  case width {
    glintl.Narrow -> "narrow"
    glintl.Short -> "short"
    glintl.Long -> "long"
  }
}

pub fn digits(digits: glintl.Digits) -> String {
  case digits {
    glintl.Numeric -> numeric
    glintl.TwoDigit -> "2-digit"
  }
}

/// A formatter for a date style, a time style or both.
pub fn styles(locale: Locale, shown: render.Shown) -> Compiled {
  compile(locale, shown)
}

/// A formatter for fields. Like Intl, with no date or time part, it shows a
/// numeric year, month and day.
pub fn fields(locale: Locale, request: matcher.Request) -> Compiled {
  let request =
    matcher.Request(
      ..request,
      hour_cycle: glintl.intl_hour_cycle_option(locale),
    )
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
    any_set([weekday, year, month, day, day_period, hour, minute, second])
    || fractional_second_digits > 0
  case shown {
    True -> compile_fields(locale, request)
    False ->
      compile_fields(
        locale,
        matcher.Request(..request, year: numeric, month: numeric, day: numeric),
      )
  }
}

fn any_set(options: List(String)) -> Bool {
  case options {
    [] -> False
    ["", ..rest] -> any_set(rest)
    [_, ..] -> True
  }
}

/// Formats a moment as the clocks in `zone` show it.
pub fn format(
  compiled: Compiled,
  seconds: Int,
  nanoseconds: Int,
  zone: TimeZone,
) -> String {
  do_format(compiled, seconds, nanoseconds, zone)
}

@target(erlang)
fn compile(locale: Locale, shown: render.Shown) -> Compiled {
  let calendar = glintl.locale_calendar(locale)
  let data = glintl.locale_data(locale)
  let cycle = glintl.hour_cycle_number(locale)
  case calendar {
    glintl.Gregorian -> render.compile(data, cycle, shown)
    _ ->
      render.compile_other(
        data,
        glintl.calendar_position(calendar),
        cycle,
        fn() { calendar_math(calendar) },
        shown,
      )
  }
}

@target(erlang)
fn compile_fields(locale: Locale, request: matcher.Request) -> Compiled {
  let calendar = glintl.locale_calendar(locale)
  render.compile_fields(
    glintl.locale_data(locale),
    glintl.calendar_position(calendar),
    request,
    glintl.icu_calendar(calendar),
    fn() { calendar_math(calendar) },
  )
}

@target(javascript)
fn compile_fields(locale: Locale, request: matcher.Request) -> Compiled {
  intl_fields_formatter(
    glintl.locale_tag(locale),
    glintl.icu_calendar(glintl.locale_calendar(locale)),
    request,
  )
}

@target(javascript)
@external(javascript, "../../glintl_ffi.mjs", "fieldsFormatter")
fn intl_fields_formatter(
  tag: String,
  calendar: String,
  request: matcher.Request,
) -> Compiled

@target(javascript)
fn compile(locale: Locale, shown: render.Shown) -> Compiled {
  let #(date_style, time_style) = case shown {
    render.DateOnly(date) -> #(intl_style(date), "")
    render.TimeOnly(time) -> #("", intl_style(time))
    render.DateAndTime(date:, time:) -> #(intl_style(date), intl_style(time))
  }
  intl_formatter(
    glintl.locale_tag(locale),
    glintl.icu_calendar(glintl.locale_calendar(locale)),
    date_style,
    time_style,
    glintl.intl_hour_cycle_option(locale),
  )
}

@target(javascript)
/// `""` means no style.
@external(javascript, "../../glintl_ffi.mjs", "formatter")
fn intl_formatter(
  tag: String,
  calendar: String,
  date_style: String,
  time_style: String,
  hour_cycle: String,
) -> Compiled

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
/// How a calendar maps days to its own dates.
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
  compiled: Compiled,
  seconds: Int,
  nanoseconds: Int,
  zone: TimeZone,
) -> String {
  render.render(
    compiled,
    seconds,
    nanoseconds / nanoseconds_per_millisecond,
    time_zone.offset_seconds(zone, seconds),
  )
}

@target(javascript)
fn do_format(
  compiled: Compiled,
  seconds: Int,
  nanoseconds: Int,
  zone: TimeZone,
) -> String {
  intl_format(compiled, seconds, nanoseconds, time_zone.intl_time_zone(zone))
}

@target(javascript)
@external(javascript, "../../glintl_ffi.mjs", "format")
fn intl_format(
  compiled: Compiled,
  seconds: Int,
  nanoseconds: Int,
  time_zone: String,
) -> String
