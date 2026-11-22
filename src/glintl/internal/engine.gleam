@target(erlang)
import gleam/list
@target(erlang)
import gleam/option.{type Option, None, Some}
@target(erlang)
import gleam/result
import glintl.{type Locale}
@target(erlang)
import glintl/internal/calendar_id
import glintl/internal/data
import glintl/internal/matcher
import glintl/internal/render
@target(erlang)
import glintl/internal/zones
import glintl/time_zone.{type TimeZone}

@target(erlang)
pub type Compiled {
  Compiled(rendered: render.Compiled, names: List(Int), location: data.Location)
}

@target(javascript)
/// Holds an `Intl.DateTimeFormat` for each time zone it has formatted in.
pub type Compiled

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

pub fn styles(locale: Locale, shown: render.Shown) -> Compiled {
  compile(locale, shown)
}

/// Like Intl, a request with no date or time field shows a numeric date.
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

pub fn format(
  compiled: Compiled,
  seconds: Int,
  nanoseconds: Int,
  zone: TimeZone,
) -> String {
  do_format(compiled, seconds, nanoseconds, zone)
}

/// Parts come back as Intl's name for their type and their text, such as
/// `#("weekday", "Sunday")`.
pub fn format_to_parts(
  compiled: Compiled,
  seconds: Int,
  nanoseconds: Int,
  zone: TimeZone,
) -> List(#(String, String)) {
  do_format_to_parts(compiled, seconds, nanoseconds, zone)
}

@target(erlang)
fn compile(locale: Locale, shown: render.Shown) -> Compiled {
  let calendar = glintl.locale_calendar(locale)
  let data = glintl.locale_data(locale)
  let cycle = glintl.hour_cycle_number(locale)
  let rendered = case calendar == glintl.gregorian {
    True -> render.compile(data, cycle, shown)
    False ->
      render.compile_other(
        data,
        glintl.calendar_position(calendar),
        cycle,
        calendar_math(calendar),
        shown,
      )
  }
  Compiled(
    rendered: with_numbering_system(rendered, locale),
    names: zones.name_chain(glintl.locale_tag(locale)),
    location: zones.location(glintl.locale_tag(locale)),
  )
}

@target(erlang)
/// `None` means the locale's default decimal separator.
fn decimal(locale: Locale) -> Option(String) {
  case glintl.numbering_system_number(locale) {
    None -> None
    Some(number) ->
      list.key_find(decimals(glintl.locale_tag(locale)), number)
      |> option.from_result
  }
}

@target(erlang)
/// Decimal separators that differ from the locale's default, by digits number.
@external(erlang, "glintl_generated_data", "decimals")
fn decimals(tag: String) -> List(#(Int, String))

@target(erlang)
fn with_numbering_system(
  rendered: render.Compiled,
  locale: Locale,
) -> render.Compiled {
  case glintl.numbering_system_number(locale) {
    None -> rendered
    Some(number) -> {
      let #(own_minus, found) = minus_signs(glintl.locale_tag(locale))
      let minus = list.key_find(found, number) |> result.unwrap(own_minus)
      render.with_digits(rendered, number, own_minus, minus)
    }
  }
}

@target(erlang)
/// The locale's default minus sign, then the ones that differ, by digits number.
@external(erlang, "glintl_generated_data", "minus_signs")
fn minus_signs(tag: String) -> #(String, List(#(Int, String)))

@target(erlang)
fn compile_fields(locale: Locale, request: matcher.Request) -> Compiled {
  let calendar = glintl.locale_calendar(locale)
  let rendered =
    render.compile_fields(
      glintl.locale_data(locale),
      glintl.calendar_position(calendar),
      request,
      calendar_math(calendar),
      decimal(locale),
    )
  Compiled(
    rendered: with_numbering_system(rendered, locale),
    names: zones.name_chain(glintl.locale_tag(locale)),
    location: zones.location(glintl.locale_tag(locale)),
  )
}

@target(javascript)
fn compile_fields(locale: Locale, request: matcher.Request) -> Compiled {
  intl_fields_formatter(
    glintl.locale_tag(locale),
    glintl.calendar_name(glintl.locale_calendar(locale)),
    request,
    glintl.intl_numbering_system_option(locale),
  )
}

@target(javascript)
@external(javascript, "../../glintl_ffi.mjs", "fieldsFormatter")
fn intl_fields_formatter(
  tag: String,
  calendar: String,
  request: matcher.Request,
  numbering_system: String,
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
    glintl.calendar_name(glintl.locale_calendar(locale)),
    date_style,
    time_style,
    glintl.intl_hour_cycle_option(locale),
    glintl.intl_numbering_system_option(locale),
  )
}

@target(javascript)
/// Pass `""` for a style to leave it out.
@external(javascript, "../../glintl_ffi.mjs", "formatter")
fn intl_formatter(
  tag: String,
  calendar: String,
  date_style: String,
  time_style: String,
  hour_cycle: String,
  numbering_system: String,
) -> Compiled

@target(javascript)
fn intl_style(style: data.Style) -> String {
  case style {
    data.Full -> "full"
    data.Long -> "long"
    data.Medium -> "medium"
    data.Short -> "short"
  }
}

@target(erlang)
pub fn calendar_math(calendar: glintl.Calendar) -> fn() -> data.Math {
  case glintl.calendar_id(calendar) {
    calendar_id.Gregorian -> fn() { data.gregorian }
    calendar_id.Iso8601 -> iso8601_math
    calendar_id.Buddhist -> buddhist_math
    calendar_id.Japanese -> japanese_math
    calendar_id.RepublicOfChina -> republic_of_china_math
    calendar_id.Persian -> persian_math
    calendar_id.Indian -> indian_math
    calendar_id.Hebrew -> hebrew_math
    calendar_id.Chinese -> chinese_math
    calendar_id.Dangi -> dangi_math
    calendar_id.Coptic -> coptic_math
    calendar_id.Ethiopic -> ethiopic_math
    calendar_id.EthiopicAmeteAlem -> ethiopic_amete_alem_math
    calendar_id.IslamicCivil -> islamic_civil_math
    calendar_id.IslamicTabular -> islamic_tabular_math
    calendar_id.IslamicUmmAlQura -> islamic_umm_al_qura_math
  }
}

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
  let #(offset, key, zone, daylight) = time_zone.at(zone, seconds)
  let names = case key < 0 {
    True -> data.Unnamed
    False ->
      data.Named(
        key:,
        zone:,
        daylight:,
        chain: compiled.names,
        location: compiled.location,
      )
  }
  render.render(
    compiled.rendered,
    seconds,
    nanoseconds / nanoseconds_per_millisecond,
    offset,
    names,
  )
}

@target(erlang)
fn do_format_to_parts(
  compiled: Compiled,
  seconds: Int,
  nanoseconds: Int,
  zone: TimeZone,
) -> List(#(String, String)) {
  let #(offset, names) = zone_at(compiled, zone, seconds)
  render.render_parts(
    compiled.rendered,
    seconds,
    nanoseconds / nanoseconds_per_millisecond,
    offset,
    names,
  )
  |> list.map(fn(part) { #(intl_type(part.0), part.1) })
}

@target(erlang)
fn zone_at(
  compiled: Compiled,
  zone: TimeZone,
  seconds: Int,
) -> #(Int, data.ZoneNames) {
  let #(offset, key, zone, daylight) = time_zone.at(zone, seconds)
  case key < 0 {
    True -> #(offset, data.Unnamed)
    False -> #(
      offset,
      data.Named(
        key:,
        zone:,
        daylight:,
        chain: compiled.names,
        location: compiled.location,
      ),
    )
  }
}

@target(erlang)
fn intl_type(kind: render.PartKind) -> String {
  case kind {
    render.EraPart -> "era"
    render.YearPart -> "year"
    render.RelatedYearPart -> "relatedYear"
    render.YearNamePart -> "yearName"
    render.MonthPart -> "month"
    render.DayPart -> "day"
    render.WeekdayPart -> "weekday"
    render.DayPeriodPart -> "dayPeriod"
    render.HourPart -> "hour"
    render.MinutePart -> "minute"
    render.SecondPart -> "second"
    render.FractionalSecondPart -> "fractionalSecond"
    render.TimeZoneNamePart -> "timeZoneName"
    render.LiteralPart -> "literal"
    render.UnknownPart -> "unknown"
  }
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
fn do_format_to_parts(
  compiled: Compiled,
  seconds: Int,
  nanoseconds: Int,
  zone: TimeZone,
) -> List(#(String, String)) {
  intl_format_to_parts(
    compiled,
    seconds,
    nanoseconds,
    time_zone.intl_time_zone(zone),
  )
}

@target(javascript)
@external(javascript, "../../glintl_ffi.mjs", "formatToParts")
fn intl_format_to_parts(
  compiled: Compiled,
  seconds: Int,
  nanoseconds: Int,
  time_zone: String,
) -> List(#(String, String))

@target(javascript)
@external(javascript, "../../glintl_ffi.mjs", "format")
fn intl_format(
  compiled: Compiled,
  seconds: Int,
  nanoseconds: Int,
  time_zone: String,
) -> String
