//// Format dates and times in many languages, on Erlang and JavaScript.
////
//// ```gleam
//// import glintl
//// import glintl/locale/en_gb
//// import gleam/time/duration
//// import gleam/time/timestamp
////
//// let formatter =
////   glintl.date_time_formatter(en_gb.locale(), date: glintl.Long, time: glintl.Short)
////
//// glintl.format(formatter, timestamp.system_time(), offset: duration.hours(1))
//// // -> "25 October 2026 at 23:40"
//// ```
////
//// On Erlang the formats come from data baked into this package, made from
//// ICU when the package is built. On JavaScript the runtime's own
//// `Intl.DateTimeFormat` is used, so the output can differ slightly between
//// targets and between JavaScript runtimes.

import gleam/int
import gleam/list
import gleam/time/duration.{type Duration}
import gleam/time/timestamp.{type Timestamp}
import glintl/internal/data.{
  type Calendars, type Data, Calendars, Data, NoCalendars, NoData,
  gregorian as gregorian_math,
}
import glintl/internal/math
import glintl/internal/render.{type Compiled}

/// A language and region to format for, such as British English.
///
/// Get one from a locale module, like `glintl/locale/en_gb`, or by tag from
/// `glintl/locales`.
pub opaque type Locale {
  Locale(
    tag: String,
    calendar: Calendar,
    data: Data,
    calendars: fn() -> Calendars,
  )
}

/// Make a locale. Used by the generated locale modules.
@internal
pub fn new_locale(
  tag: String,
  calendar: Calendar,
  data: Data,
  calendars: fn() -> Calendars,
) -> Locale {
  Locale(tag:, calendar:, data:, calendars:)
}

/// The BCP 47 tag of a locale, such as `"en-GB"`.
pub fn locale_tag(locale: Locale) -> String {
  locale.tag
}

/// The calendars glintl can format dates in.
///
/// Each locale has a default: most use `Gregorian`, Thai uses `Buddhist`,
/// Persian uses `Persian`, and Saudi Arabic uses `IslamicUmmAlQura`.
///
/// On Erlang, calendars with their own months work for years 1 to 4000 of
/// the Gregorian calendar, and dates outside that are written in the
/// Gregorian calendar instead. These are every calendar but `Gregorian`,
/// `Iso8601`, `Buddhist`, `Japanese` and `RepublicOfChina`.
pub type Calendar {
  Gregorian
  /// The Gregorian calendar, with ISO 8601 rules for weeks and patterns.
  Iso8601
  /// The Thai solar calendar: Gregorian, with years counted from 543 BC.
  Buddhist
  /// Gregorian, with years counted in Japanese eras.
  Japanese
  /// The Minguo calendar used in Taiwan: Gregorian, with years counted
  /// from 1912.
  RepublicOfChina
  /// The Solar Hijri calendar used in Iran and Afghanistan.
  Persian
  /// The Indian national calendar.
  Indian
  Hebrew
  Chinese
  /// The Korean calendar.
  Dangi
  Coptic
  /// The Ethiopian calendar, with years counted in the Amete Mihret era.
  Ethiopic
  /// The Ethiopian calendar, with years counted in the Amete Alem era.
  EthiopicAmeteAlem
  /// The tabular Islamic calendar, counting from 16 July 622 in the Julian
  /// calendar, as civil tables do.
  IslamicCivil
  /// The tabular Islamic calendar, counting from 15 July 622 in the Julian
  /// calendar, the astronomical start.
  IslamicTabular
  /// The Umm al-Qura calendar used in Saudi Arabia.
  IslamicUmmAlQura
}

/// The calendar a locale formats dates in.
pub fn locale_calendar(locale: Locale) -> Calendar {
  locale.calendar
}

/// Format dates in another calendar.
///
/// ```gleam
/// en_gb.locale()
/// |> glintl.with_calendar(glintl.Hebrew)
/// |> glintl.date_formatter(style: glintl.Long)
/// |> glintl.format(timestamp.system_time(), offset: duration.hours(1))
/// // -> "14 Heshvan 5787"
/// ```
pub fn with_calendar(locale: Locale, calendar: Calendar) -> Locale {
  Locale(..locale, calendar:)
}

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

/// Formats moments in time for one locale and style.
///
/// Make one and reuse it: making a formatter does the lookup work once, so
/// formatting is cheap.
pub opaque type Formatter {
  Formatter(compiled: Compiled)
}

/// Format only the date.
pub fn date_formatter(locale: Locale, style style: Style) -> Formatter {
  new(locale, style_index(style), 0)
}

/// Format only the time.
pub fn time_formatter(locale: Locale, style style: Style) -> Formatter {
  new(locale, 0, style_index(style))
}

/// Format both the date and the time.
pub fn date_time_formatter(
  locale: Locale,
  date date: Style,
  time time: Style,
) -> Formatter {
  new(locale, style_index(date), style_index(time))
}

/// Format a moment in time, as seen from a place `offset` ahead of UTC.
///
/// The offset is rounded down to whole minutes. Time zones are written as a
/// GMT offset, like `GMT+1`, as glintl knows the offset but not the zone's
/// name.
pub fn format(
  formatter: Formatter,
  timestamp: Timestamp,
  offset offset: Duration,
) -> String {
  let #(seconds, nanoseconds) =
    timestamp.to_unix_seconds_and_nanoseconds(timestamp)
  let #(offset_seconds, _) = duration.to_seconds_and_nanoseconds(offset)
  let offset_minutes = case int.floor_divide(offset_seconds, 60) {
    Ok(minutes) -> minutes
    Error(_) -> 0
  }
  do_format(formatter.compiled, seconds, nanoseconds, offset_minutes)
}

fn new(locale: Locale, date: Int, time: Int) -> Formatter {
  let Locale(tag:, calendar:, data:, calendars:) = locale
  let index = calendar_index(calendar)
  Formatter(compile(tag, data, calendars, index, date, time))
}

fn style_index(style: Style) -> Int {
  case style {
    Full -> 1
    Long -> 2
    Medium -> 3
    Short -> 4
  }
}

fn calendar_index(calendar: Calendar) -> Int {
  case calendar {
    Gregorian -> 0
    Iso8601 -> 1
    Buddhist -> 2
    Japanese -> 3
    RepublicOfChina -> 4
    Persian -> 5
    Indian -> 6
    Hebrew -> 7
    Chinese -> 8
    Dangi -> 9
    Coptic -> 10
    Ethiopic -> 11
    EthiopicAmeteAlem -> 12
    IslamicCivil -> 13
    IslamicTabular -> 14
    IslamicUmmAlQura -> 15
  }
}

// `date` and `time` are 0 for "not shown", or a `style_index`.
@external(javascript, "./glintl_ffi.mjs", "compile")
fn compile(
  _tag: String,
  data: Data,
  calendars: fn() -> Calendars,
  calendar: Int,
  date: Int,
  time: Int,
) -> Compiled {
  case data {
    NoData ->
      render.compile(empty(), data.Ascii, data.NoMath, 0, 0, render.NoFallback)
    Data(digits:, gregorian:) -> {
      let fallback =
        render.compile(
          gregorian,
          digits,
          gregorian_math,
          date,
          time,
          render.NoFallback,
        )
      case calendar {
        0 -> fallback
        _ ->
          case calendars() {
            Calendars(formats:) ->
              case list.drop(formats, calendar - 1) {
                [formats, ..] ->
                  render.compile(
                    formats,
                    digits,
                    math.math(calendar),
                    date,
                    time,
                    render.Fallback(fallback),
                  )
                [] -> fallback
              }
            NoCalendars -> fallback
          }
      }
    }
  }
}

fn empty() -> data.Formats {
  data.Formats(dates: [], times: [], glues: [], eras: [])
}

@external(javascript, "./glintl_ffi.mjs", "format")
fn do_format(
  compiled: Compiled,
  seconds: Int,
  _nanoseconds: Int,
  offset_minutes: Int,
) -> String {
  render.render(compiled, seconds, offset_minutes)
}
