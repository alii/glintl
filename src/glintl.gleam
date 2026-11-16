//// This module is for choosing how a locale formats dates and times. You can
//// change its calendar, switch to a 24 hour clock or write numbers with other
//// digits.
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
import gleam/string
@target(erlang)
import glintl/internal/render

@target(erlang)
/// A language and region to format dates and times for.
///
/// Each locale has its own module in `glintl/locale`. To pick one while your
/// program is running, use `glintl/locales`.
pub opaque type Locale {
  Locale(
    tag: String,
    calendar: Calendar,
    hour_cycle: Option(HourCycle),
    numbering_system: Option(NumberingSystem),
    data: Int,
  )
}

@target(javascript)
pub opaque type Locale {
  Locale(
    tag: String,
    calendar: Calendar,
    hour_cycle: Option(HourCycle),
    numbering_system: Option(NumberingSystem),
  )
}

@target(erlang)
@internal
pub fn new_locale(tag: String, calendar: Calendar, data: Int) -> Locale {
  Locale(tag:, calendar:, hour_cycle: None, numbering_system: None, data:)
}

@target(javascript)
@internal
pub fn new_locale(tag: String, calendar: Calendar, _data: Int) -> Locale {
  Locale(tag:, calendar:, hour_cycle: None, numbering_system: None)
}

/// Get the BCP 47 tag of a locale.
///
/// ```gleam
/// glintl.locale_tag(en_gb.locale())
/// // -> "en-GB"
/// ```
///
/// The tag leaves out settings like the calendar. A locale from
/// `"ja-JP-u-ca-japanese"` has the tag `"ja"`.
pub fn locale_tag(locale: Locale) -> String {
  locale.tag
}

/// How long a name is.
///
/// Sunday in British English is "S" when `Narrow`, "Sun" when `Short` and
/// "Sunday" when `Long`.
pub type Width {
  Narrow
  Short
  Long
}

/// How many digits to write a number with.
///
/// `Numeric` uses as many digits as the number needs. `TwoDigit` pads a number
/// to two digits, so 5 becomes "05". For years, it keeps the last two digits, so
/// 2026 becomes "26".
pub type Digits {
  Numeric
  TwoDigit
}

/// A calendar system for numbering years, months and days.
///
/// Most locales use the Gregorian calendar, but some use another one by default.
/// For example, Thai uses the Buddhist calendar and Persian uses the Persian
/// calendar.
///
/// On Erlang, glintl can write Hebrew, Persian and other calendars with their
/// own months for the years 1 to 4000. Outside that range, it writes dates in the
/// Gregorian calendar instead.
pub type Calendar {
  Gregorian
  /// The Gregorian calendar with ISO 8601 weeks and dates like 2026-10-25.
  Iso8601
  /// The Thai calendar. It counts years from 543 BC, so 2026 is 2569.
  Buddhist
  /// The Gregorian calendar with years counted in Japanese eras, so 2026 is
  /// Reiwa 8.
  Japanese
  /// The Minguo calendar used in Taiwan. It counts years from 1912, so 2026 is
  /// 115.
  RepublicOfChina
  /// The Solar Hijri calendar used in Iran and Afghanistan.
  Persian
  /// The Indian national calendar.
  Indian
  Hebrew
  Chinese
  /// The Korean lunisolar calendar.
  Dangi
  Coptic
  /// The Ethiopian calendar with years in the Amete Mihret era.
  Ethiopic
  /// The Ethiopian calendar with years in the Amete Alem era.
  EthiopicAmeteAlem
  /// The tabular Islamic calendar counted from Friday 16 July 622 in the Julian
  /// calendar.
  IslamicCivil
  /// The tabular Islamic calendar counted from Thursday 15 July 622 in the Julian
  /// calendar.
  IslamicTabular
  /// The Umm al-Qura calendar used in Saudi Arabia.
  IslamicUmmAlQura
}

/// Get the calendar a locale writes dates in.
///
/// ```gleam
/// glintl.locale_calendar(th.locale())
/// // -> glintl.Buddhist
/// ```
pub fn locale_calendar(locale: Locale) -> Calendar {
  locale.calendar
}

/// Change the calendar a locale writes dates in.
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

/// How a clock counts the hours of the day.
///
/// This is how a quarter past midnight and a quarter to midnight look in British
/// English:
///
/// | Hour cycle | Hours    | Times              |
/// | ---------- | -------- | ------------------ |
/// | `H11`      | 0 to 11  | 00:15 am, 11:45 pm |
/// | `H12`      | 1 to 12  | 12:15 am, 11:45 pm |
/// | `H23`      | 0 to 23  | 00:15, 23:45       |
/// | `H24`      | 1 to 24  | 24:15, 23:45       |
pub type HourCycle {
  H11
  H12
  H23
  H24
}

/// Change the hour cycle a locale writes times in.
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

/// Get the hour cycle a locale writes times in.
///
/// ```gleam
/// glintl.locale_hour_cycle(en.locale())
/// // -> glintl.H12
/// ```
pub fn locale_hour_cycle(locale: Locale) -> HourCycle {
  case locale.hour_cycle {
    Some(hour_cycle) -> hour_cycle
    None -> default_hour_cycle(locale)
  }
}

/// The digits a locale writes numbers with.
///
/// Most locales write numbers with the digits 0 to 9. That's the `"latn"`
/// numbering system. Persian uses `"arabext"` and writes 1405 as ۱۴۰۵.
///
/// A numbering system only changes the digits. Words such as month names stay
/// the same.
pub opaque type NumberingSystem {
  NumberingSystem(name: String)
}

/// Get a numbering system from its Unicode name.
///
/// ```gleam
/// let assert Ok(arabic) = glintl.numbering_system("arab")
/// ```
///
/// Only numbering systems with ten digits of their own are supported, so
/// `"roman"` returns an error.
pub fn numbering_system(name: String) -> Result(NumberingSystem, Nil) {
  let name = string.lowercase(name)
  case is_numbering_system(name) {
    True -> Ok(NumberingSystem(name))
    False -> Error(Nil)
  }
}

/// Get the Unicode name of a numbering system.
pub fn numbering_system_name(numbering_system: NumberingSystem) -> String {
  numbering_system.name
}

/// Change the digits a locale writes numbers with.
///
/// ```gleam
/// let assert Ok(latin) = glintl.numbering_system("latn")
///
/// fa.locale()
/// |> glintl.with_numbering_system(latin)
/// |> date_time.date_formatter(style: date_time.Short)
/// |> date_time.format(timestamp.system_time(), zone: time_zone.utc)
/// // -> "1405/8/3"
/// ```
pub fn with_numbering_system(
  locale: Locale,
  numbering_system: NumberingSystem,
) -> Locale {
  Locale(..locale, numbering_system: Some(numbering_system))
}

/// Get the numbering system a locale writes numbers with.
pub fn locale_numbering_system(locale: Locale) -> NumberingSystem {
  case locale.numbering_system {
    Some(numbering_system) -> numbering_system
    None -> NumberingSystem(default_numbering_system(locale))
  }
}

@target(erlang)
fn is_numbering_system(name: String) -> Bool {
  case numbering_system_digits(name) {
    Ok(_) -> True
    Error(Nil) -> False
  }
}

@target(erlang)
@external(erlang, "glintl_generated_data", "numbering_system")
fn numbering_system_digits(name: String) -> Result(Int, Nil)

@target(erlang)
@external(erlang, "glintl_generated_data", "numbering_system_names")
fn numbering_system_names() -> render.Names

@target(erlang)
fn default_numbering_system(locale: Locale) -> String {
  render.name_at(numbering_system_names(), render.default_digits(locale.data))
}

@target(javascript)
@external(javascript, "./glintl_ffi.mjs", "isNumberingSystem")
fn is_numbering_system(name: String) -> Bool

@target(javascript)
fn default_numbering_system(locale: Locale) -> String {
  intl_numbering_system(locale.tag, calendar_name(locale.calendar))
}

@target(javascript)
@external(javascript, "./glintl_ffi.mjs", "numberingSystem")
fn intl_numbering_system(tag: String, calendar: String) -> String

@target(erlang)
@internal
pub fn numbering_system_number(locale: Locale) -> Option(Int) {
  case locale.numbering_system {
    None -> None
    Some(NumberingSystem(name)) ->
      case numbering_system_digits(name) {
        Ok(n) -> Some(n)
        Error(Nil) -> None
      }
  }
}

@internal
pub fn intl_numbering_system_option(locale: Locale) -> String {
  case locale.numbering_system {
    None -> ""
    Some(NumberingSystem(name)) -> name
  }
}

@target(erlang)
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
  case intl_hour_cycle(locale.tag, calendar_name(locale.calendar)) {
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
@internal
pub fn locale_data(locale: Locale) -> Int {
  locale.data
}

@target(erlang)
/// The packed data numbers hour cycles from 1, and uses 0 for the locale's
/// default.
@internal
pub fn hour_cycle_number(locale: Locale) -> Int {
  case locale.hour_cycle {
    None -> 0
    Some(hour_cycle) -> position(hour_cycles(), hour_cycle, 1)
  }
}

@target(erlang)
@internal
pub fn calendar_position(calendar: Calendar) -> Int {
  position(calendars(), calendar, 0)
}

@target(erlang)
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

/// Get a calendar from its Unicode name. These are the same names Intl uses.
///
/// ```gleam
/// glintl.calendar_from_name("hebrew")
/// // -> Ok(glintl.Hebrew)
/// ```
///
/// Old names such as `"islamic"` work too.
pub fn calendar_from_name(name: String) -> Result(Calendar, Nil) {
  case string.lowercase(name) {
    "gregory" -> Ok(Gregorian)
    "iso8601" -> Ok(Iso8601)
    "buddhist" -> Ok(Buddhist)
    "japanese" -> Ok(Japanese)
    "roc" -> Ok(RepublicOfChina)
    "persian" -> Ok(Persian)
    "indian" -> Ok(Indian)
    "hebrew" -> Ok(Hebrew)
    "chinese" -> Ok(Chinese)
    "dangi" -> Ok(Dangi)
    "coptic" -> Ok(Coptic)
    "ethiopic" -> Ok(Ethiopic)
    "ethioaa" | "ethiopic-amete-alem" -> Ok(EthiopicAmeteAlem)
    "islamic-civil" | "islamicc" -> Ok(IslamicCivil)
    "islamic-tbla" | "islamic" -> Ok(IslamicTabular)
    "islamic-umalqura" -> Ok(IslamicUmmAlQura)
    "islamic-rgsa" -> Ok(Gregorian)
    _ -> Error(Nil)
  }
}

/// Get the Unicode name of a calendar.
///
/// ```gleam
/// glintl.calendar_name(glintl.Hebrew)
/// // -> "hebrew"
/// ```
pub fn calendar_name(calendar: Calendar) -> String {
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
