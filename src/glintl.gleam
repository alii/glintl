//// Format dates and times in many languages, on Erlang and JavaScript.
////
//// ```gleam
//// import glintl
//// import glintl/locale/en_gb
//// import gleam/time/timestamp
////
//// let formatter =
////   glintl.date_time_formatter(en_gb.locale(), date: glintl.Long, time: glintl.Short)
////
//// let assert Ok(offset) = glintl.offset(hours: 1, minutes: 0)
////
//// glintl.format(formatter, timestamp.system_time(), offset:)
//// // -> "25 October 2026 at 23:40"
//// ```
////
//// On Erlang the formats come from data baked into this package, made from
//// ICU when the package is built. On JavaScript the runtime's own
//// `Intl.DateTimeFormat` is used, so the output can differ slightly between
//// targets and between JavaScript runtimes.

import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/time/calendar
import gleam/time/duration.{type Duration}
import gleam/time/timestamp.{type Timestamp}
import glintl/internal/data.{gregorian as gregorian_math}
import glintl/internal/math
import glintl/internal/render

@target(erlang)
/// A language and region to format for, such as British English.
///
/// Get one from a locale module, like `glintl/locale/en_gb`, or by tag from
/// `glintl/locales`.
pub opaque type Locale {
  Locale(
    tag: String,
    calendar: Calendar,
    /// `None` for the locale's own hour cycle.
    hour_cycle: Option(HourCycle),
    /// The locale's number in glintl's packed data.
    data: Int,
  )
}

@target(javascript)
/// On JavaScript, `Intl.DateTimeFormat` has the data.
pub opaque type Locale {
  Locale(tag: String, calendar: Calendar, hour_cycle: Option(HourCycle))
}

@target(erlang)
/// Make a locale. Used by the generated locale modules.
@internal
pub fn new_locale(tag: String, calendar: Calendar, data: Int) -> Locale {
  Locale(tag:, calendar:, hour_cycle: None, data:)
}

@target(javascript)
/// Make a locale. Used by the generated locale modules.
@internal
pub fn new_locale(tag: String, calendar: Calendar, _data: Int) -> Locale {
  Locale(tag:, calendar:, hour_cycle: None)
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
/// |> glintl.format(timestamp.system_time(), offset: glintl.utc)
/// // -> "14 Heshvan 5787"
/// ```
pub fn with_calendar(locale: Locale, calendar: Calendar) -> Locale {
  Locale(..locale, calendar:)
}

/// Which hours a clock shows, the same as the `hourCycle` option of
/// JavaScript's `Intl.DateTimeFormat`. In British English, at a quarter past
/// midnight and a quarter to midnight:
///
/// | Hour cycle | Hours    | Times              |
/// | ---------- | -------- | ------------------ |
/// | `H11`      | 0 to 11  | 0:15 am, 11:45 pm  |
/// | `H12`      | 1 to 12  | 12:15 am, 11:45 pm |
/// | `H23`      | 0 to 23  | 00:15, 23:45       |
/// | `H24`      | 1 to 24  | 24:15, 23:45       |
///
/// Locales show the 12 hour ones with their own words for morning and
/// evening, which can move or change the rest of the time.
pub type HourCycle {
  H11
  H12
  H23
  H24
}

/// Show hours in another hour cycle, like 24 hour time in American English.
///
/// ```gleam
/// en.locale()
/// |> glintl.with_hour_cycle(glintl.H23)
/// |> glintl.time_formatter(style: glintl.Short)
/// |> glintl.format(timestamp.system_time(), offset: glintl.utc)
/// // -> "22:40"
/// ```
pub fn with_hour_cycle(locale: Locale, hour_cycle: HourCycle) -> Locale {
  Locale(..locale, hour_cycle: Some(hour_cycle))
}

/// The hour cycle a locale shows: one set with `with_hour_cycle`, or the
/// locale's own.
pub fn locale_hour_cycle(locale: Locale) -> HourCycle {
  case locale.hour_cycle {
    Some(hour_cycle) -> hour_cycle
    None -> default_hour_cycle(locale)
  }
}

@target(erlang)
/// In the order of `HOUR_CYCLES` in `codegen/patterns.ts`.
const hour_cycles = [H11, H12, H23, H24]

@target(erlang)
fn default_hour_cycle(locale: Locale) -> HourCycle {
  at(hour_cycles, render.default_hour_cycle(locale.data), H23)
}

@target(erlang)
fn at(items: List(a), index: Int, otherwise: a) -> a {
  case items, index {
    [item, ..], 0 -> item
    [_, ..rest], _ -> at(rest, index - 1, otherwise)
    [], _ -> otherwise
  }
}

@target(javascript)
fn default_hour_cycle(locale: Locale) -> HourCycle {
  case intl_hour_cycle(locale.tag, icu_calendar(locale.calendar)) {
    "h11" -> H11
    "h12" -> H12
    "h24" -> H24
    _ -> H23
  }
}

@target(javascript)
@external(javascript, "./glintl_ffi.mjs", "hourCycle")
fn intl_hour_cycle(tag: String, calendar: String) -> String

@target(javascript)
/// The `hourCycle` option of `Intl.DateTimeFormat`, or `""` for the
/// locale's own.
fn intl_hour_cycle_option(hour_cycle: Option(HourCycle)) -> String {
  case hour_cycle {
    None -> ""
    Some(H11) -> "h11"
    Some(H12) -> "h12"
    Some(H23) -> "h23"
    Some(H24) -> "h24"
  }
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

@target(erlang)
/// Formats moments in time for one locale and style.
///
/// Make one and reuse it: making a formatter does the lookup work once, so
/// formatting is cheap.
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
  new(locale, data.DateOnly(internal_style(style)))
}

/// Format only the time.
pub fn time_formatter(locale: Locale, style style: Style) -> Formatter {
  new(locale, data.TimeOnly(internal_style(style)))
}

/// Format both the date and the time.
pub fn date_time_formatter(
  locale: Locale,
  date date: Style,
  time time: Style,
) -> Formatter {
  new(
    locale,
    data.DateAndTime(date: internal_style(date), time: internal_style(time)),
  )
}

/// How far a place's clocks are ahead of UTC, in whole minutes, and under
/// 24 hours either way.
pub opaque type Offset {
  Offset(minutes: Int)
}

/// No offset: UTC itself.
pub const utc = Offset(minutes: 0)

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
    { seconds % render.seconds_per_minute + render.seconds_per_minute }
    % render.seconds_per_minute
  from_minutes({ seconds - remainder } / render.seconds_per_minute)
}

fn from_minutes(minutes: Int) -> Result(Offset, OffsetError) {
  case int.absolute_value(minutes) < hours_per_day * minutes_per_hour {
    True -> Ok(Offset(minutes:))
    False -> Error(OffsetTooLarge)
  }
}

/// Format a moment in time, as seen from a place `offset` ahead of UTC.
///
/// Time zones are written as a GMT offset, like `GMT+1`, as glintl knows the
/// offset but not the zone's name.
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
/// glintl.date_formatter(en_gb.locale(), style: glintl.Long)
/// |> glintl.format_date(calendar.Date(2026, calendar.October, 26))
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
fn new(locale: Locale, shown: data.Shown) -> Formatter {
  let Locale(calendar:, data:, hour_cycle:, ..) = locale
  // 0 for the locale's own hour cycle, then 1 more than its position.
  let cycle = case hour_cycle {
    None -> 0
    Some(hour_cycle) -> position(hour_cycles, hour_cycle, 1)
  }
  Formatter(case calendar {
    Gregorian -> render.compile(data, cycle, shown)
    _ ->
      render.compile_other(
        data,
        position(calendar_order, calendar, 0),
        cycle,
        fn() { calendar_math(calendar) },
        shown,
      )
  })
}

@target(erlang)
/// The order of each locale's formats in the packed data, the same as
/// `CALENDARS` in `codegen/calendars.ts`.
const calendar_order = [
  Gregorian,
  Iso8601,
  Buddhist,
  Japanese,
  RepublicOfChina,
  Persian,
  Indian,
  Hebrew,
  Chinese,
  Dangi,
  Coptic,
  Ethiopic,
  EthiopicAmeteAlem,
  IslamicCivil,
  IslamicTabular,
  IslamicUmmAlQura,
]

@target(erlang)
fn position(items: List(a), item: a, index: Int) -> Int {
  case items {
    [first, ..] if first == item -> index
    [_, ..rest] -> position(rest, item, index + 1)
    [] -> index
  }
}

@target(javascript)
fn new(locale: Locale, shown: data.Shown) -> Formatter {
  let #(date_style, time_style) = case shown {
    data.DateOnly(date) -> #(intl_style(date), "")
    data.TimeOnly(time) -> #("", intl_style(time))
    data.DateAndTime(date:, time:) -> #(intl_style(date), intl_style(time))
  }
  Formatter(intl_formatter(
    locale.tag,
    icu_calendar(locale.calendar),
    date_style,
    time_style,
    intl_hour_cycle_option(locale.hour_cycle),
  ))
}

@target(javascript)
/// `""` means no style.
@external(javascript, "./glintl_ffi.mjs", "formatter")
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

@target(javascript)
/// ICU's name for a calendar.
fn icu_calendar(calendar: Calendar) -> String {
  case calendar {
    Gregorian -> "gregory"
    Iso8601 -> "iso8601"
    Buddhist -> "buddhist"
    Japanese -> "japanese"
    RepublicOfChina -> "roc"
    Persian -> "persian"
    Indian -> "indian"
    Hebrew -> "hebrew"
    Chinese -> "chinese"
    Dangi -> "dangi"
    Coptic -> "coptic"
    Ethiopic -> "ethiopic"
    EthiopicAmeteAlem -> "ethioaa"
    IslamicCivil -> "islamic-civil"
    IslamicTabular -> "islamic-tbla"
    IslamicUmmAlQura -> "islamic-umalqura"
  }
}

/// How a calendar maps days to its own dates. Used by the tests.
@internal
pub fn calendar_math(calendar: Calendar) -> data.Math {
  case calendar {
    Gregorian -> gregorian_math
    Iso8601 -> math.iso8601()
    Buddhist -> math.buddhist()
    Japanese -> math.japanese()
    RepublicOfChina -> math.republic_of_china()
    Persian -> math.persian()
    Indian -> math.indian()
    Hebrew -> math.hebrew()
    Chinese -> math.chinese()
    Dangi -> math.dangi()
    Coptic -> math.coptic()
    Ethiopic -> math.ethiopic()
    EthiopicAmeteAlem -> math.ethiopic_amete_alem()
    IslamicCivil -> math.islamic_civil()
    IslamicTabular -> math.islamic_tabular()
    IslamicUmmAlQura -> math.islamic_umm_al_qura()
  }
}

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
@external(javascript, "./glintl_ffi.mjs", "format")
fn do_format(
  formatter: IntlFormatter,
  seconds: Int,
  nanoseconds: Int,
  offset_minutes: Int,
) -> String
