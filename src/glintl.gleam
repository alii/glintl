//// Pick the language, calendar and hour cycle that glintl formats in.
////
//// Format dates and times with `glintl/date_time`.
////
//// ```gleam
//// import glintl
//// import glintl/date_time
//// import glintl/locale/en
////
//// en.locale()
//// |> glintl.with_hour_cycle(glintl.H23)
//// |> date_time.time_formatter(style: date_time.Short)
//// ```

import gleam/option.{type Option, None, Some}
@target(erlang)
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
/// On JavaScript a locale holds no data, because `Intl.DateTimeFormat` has it.
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
  /// The Thai solar calendar, which is Gregorian with years counted from
  /// 543 BC.
  Buddhist
  /// The Gregorian calendar with years counted in Japanese eras.
  Japanese
  /// The Minguo calendar used in Taiwan, which is Gregorian with years
  /// counted from 1912.
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
  /// The tabular Islamic calendar that civil tables use. It counts from
  /// 16 July 622 in the Julian calendar.
  IslamicCivil
  /// The tabular Islamic calendar with the astronomical start. It counts
  /// from 15 July 622 in the Julian calendar.
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
/// |> date_time.date_formatter(style: date_time.Long)
/// |> date_time.format(timestamp.system_time(), zone: time_zone.utc)
/// // -> "14 Heshvan 5787"
/// ```
pub fn with_calendar(locale: Locale, calendar: Calendar) -> Locale {
  Locale(..locale, calendar:)
}

/// Which hours a clock shows. These are the same as the `hourCycle` option
/// of JavaScript's `Intl.DateTimeFormat`. This is how British English shows
/// a quarter past midnight and a quarter to midnight in each:
///
/// | Hour cycle | Hours    | Times              |
/// | ---------- | -------- | ------------------ |
/// | `H11`      | 0 to 11  | 0:15 am, 11:45 pm  |
/// | `H12`      | 1 to 12  | 12:15 am, 11:45 pm |
/// | `H23`      | 0 to 23  | 00:15, 23:45       |
/// | `H24`      | 1 to 24  | 24:15, 23:45       |
///
/// With `H11` and `H12`, each locale uses its own words for morning and
/// evening, and these can move or change the rest of the time.
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
/// |> date_time.time_formatter(style: date_time.Short)
/// |> date_time.format(timestamp.system_time(), zone: time_zone.utc)
/// // -> "22:40"
/// ```
pub fn with_hour_cycle(locale: Locale, hour_cycle: HourCycle) -> Locale {
  Locale(..locale, hour_cycle: Some(hour_cycle))
}

/// The hour cycle a locale shows. This is the one set with
/// `with_hour_cycle`, or the locale's own if none was set.
pub fn locale_hour_cycle(locale: Locale) -> HourCycle {
  case locale.hour_cycle {
    Some(hour_cycle) -> hour_cycle
    None -> default_hour_cycle(locale)
  }
}

@target(erlang)
/// Hour cycles in the order the packed data numbers them.
@external(erlang, "glintl_generated_data", "hour_cycles")
fn hour_cycles() -> List(HourCycle)

@target(erlang)
fn default_hour_cycle(locale: Locale) -> HourCycle {
  at(hour_cycles(), render.default_hour_cycle(locale.data), H23)
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

@target(erlang)
/// The locale's number in glintl's packed data.
@internal
pub fn locale_data(locale: Locale) -> Int {
  locale.data
}

@target(erlang)
/// 0 if the locale uses its own hour cycle. Otherwise, the packed data's
/// position for the cycle set with `with_hour_cycle`, plus 1.
@internal
pub fn hour_cycle_number(locale: Locale) -> Int {
  case locale.hour_cycle {
    None -> 0
    Some(hour_cycle) -> position(hour_cycles(), hour_cycle, 1)
  }
}

@target(erlang)
/// A calendar's position in each locale's formats in the packed data.
@internal
pub fn calendar_position(calendar: Calendar) -> Int {
  position(calendars(), calendar, 0)
}

@target(erlang)
/// Calendars in the order of each locale's formats in the packed data.
@external(erlang, "glintl_generated_data", "calendars")
fn calendars() -> List(Calendar)

@target(erlang)
fn position(items: List(a), item: a, index: Int) -> Int {
  case items {
    [first, ..] if first == item -> index
    [_, ..rest] -> position(rest, item, index + 1)
    [] -> index
  }
}

/// The `hourCycle` option of `Intl.DateTimeFormat`, or `""` for the
/// locale's own.
@internal
pub fn intl_hour_cycle_option(locale: Locale) -> String {
  case locale.hour_cycle {
    None -> ""
    Some(H11) -> "h11"
    Some(H12) -> "h12"
    Some(H23) -> "h23"
    Some(H24) -> "h24"
  }
}

/// ICU's name for a calendar.
@internal
pub fn icu_calendar(calendar: Calendar) -> String {
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
