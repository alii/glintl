//// Format dates and times for people, in their own language.
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
import glintl/internal/data.{type Data, Data, NoData}
import glintl/internal/render.{type Compiled}

/// A language and region to format for, such as British English.
///
/// Get one from a locale module, like `glintl/locale/en_gb`, or by tag from
/// `glintl/locales`.
pub opaque type Locale {
  Locale(tag: String, data: Data)
}

/// Make a locale. Used by the generated locale modules.
@internal
pub fn new_locale(tag: String, data: Data) -> Locale {
  Locale(tag:, data:)
}

/// The BCP 47 tag of a locale, such as `"en-GB"`.
pub fn locale_tag(locale: Locale) -> String {
  locale.tag
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
  let offset_minutes = int.floor_divide(offset_seconds, 60)
  let offset_minutes = case offset_minutes {
    Ok(minutes) -> minutes
    Error(_) -> 0
  }
  do_format(formatter.compiled, seconds, nanoseconds, offset_minutes)
}

fn new(locale: Locale, date: Int, time: Int) -> Formatter {
  Formatter(compile(locale.tag, locale.data, date, time))
}

fn style_index(style: Style) -> Int {
  case style {
    Full -> 1
    Long -> 2
    Medium -> 3
    Short -> 4
  }
}

// `date` and `time` are 0 for "not shown", or a `style_index`.
@external(javascript, "./glintl_ffi.mjs", "compile")
fn compile(_tag: String, data: Data, date: Int, time: Int) -> Compiled {
  case data {
    // The patterns are stored in order of date style then time style, with
    // the empty "no date, no time" pattern left out.
    Data(digits:, patterns:) ->
      case list.drop(patterns, date * 5 + time - 1) {
        [pattern, ..] -> render.compile(pattern, digits)
        [] -> render.compile([], digits)
      }
    NoData -> render.compile([], data.Ascii)
  }
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
