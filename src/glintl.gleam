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
import gleam/string
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
    /// `None` for the locale's own numbering system.
    numbering_system: Option(NumberingSystem),
    /// The locale's number in glintl's packed data.
    data: Int,
  )
}

@target(javascript)
/// On JavaScript a locale holds no data, because `Intl.DateTimeFormat` has it.
pub opaque type Locale {
  Locale(
    tag: String,
    calendar: Calendar,
    hour_cycle: Option(HourCycle),
    numbering_system: Option(NumberingSystem),
  )
}

@target(erlang)
/// Make a locale. Used by the generated locale modules.
@internal
pub fn new_locale(tag: String, calendar: Calendar, data: Int) -> Locale {
  Locale(tag:, calendar:, hour_cycle: None, numbering_system: None, data:)
}

@target(javascript)
/// Make a locale. Used by the generated locale modules.
@internal
pub fn new_locale(tag: String, calendar: Calendar, _data: Int) -> Locale {
  Locale(tag:, calendar:, hour_cycle: None, numbering_system: None)
}

/// The BCP 47 tag of a locale, such as `"en-GB"`.
pub fn locale_tag(locale: Locale) -> String {
  locale.tag
}

/// How wide a name is, like Intl's `"narrow"`, `"short"` and `"long"`. In
/// British English, a weekday is `Narrow` "S", `Short` "Sun" or `Long`
/// "Sunday".
pub type Width {
  Narrow
  Short
  Long
}

/// How a number is written, like Intl's `"numeric"` and `"2-digit"`.
/// `Numeric` has as many digits as it needs, and `TwoDigit` always has two,
/// like "05", or a year's last two, like "26".
pub type Digits {
  Numeric
  TwoDigit
}

/// A piece of a formatted date, like Intl's `formatToParts`. Each piece has
/// its text, so you can style one kind, like bold weekdays.
///
/// ```gleam
/// [Day("26"), Literal(" "), Month("October"), Literal(" "), Year("2026")]
/// ```
pub type DatePart {
  Era(String)
  Year(String)
  /// The Gregorian year in a calendar with cyclic years, like 2026 in the
  /// Chinese calendar.
  RelatedYear(String)
  /// A cyclic year's name, like 丙午 in the Chinese calendar.
  YearName(String)
  Month(String)
  Day(String)
  Weekday(String)
  /// Like "am" or "in the morning".
  DayPeriod(String)
  Hour(String)
  Minute(String)
  Second(String)
  FractionalSecond(String)
  TimeZoneName(String)
  /// Text that's the same for every date, like spaces and commas.
  Literal(String)
  /// A field Intl has no kind for, like the week-based year.
  Unknown(String)
}

/// The text of a part.
pub fn part_text(part: DatePart) -> String {
  case part {
    Era(text)
    | Year(text)
    | RelatedYear(text)
    | YearName(text)
    | Month(text)
    | Day(text)
    | Weekday(text)
    | DayPeriod(text)
    | Hour(text)
    | Minute(text)
    | Second(text)
    | FractionalSecond(text)
    | TimeZoneName(text)
    | Literal(text)
    | Unknown(text) -> text
  }
}

/// The calendars glintl can format dates in.
///
/// Each locale has its own calendar. Most use `Gregorian`. Thai uses
/// `Buddhist`, Persian uses `Persian`, and Saudi Arabic uses
/// `IslamicUmmAlQura`.
///
/// On Erlang, calendars with their own months cover the Gregorian years 1 to
/// 4000. glintl writes dates outside that range in the Gregorian calendar.
/// Every calendar has its own months except `Gregorian`, `Iso8601`,
/// `Buddhist`, `Japanese` and `RepublicOfChina`.
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

/// Which hours a clock shows, like the `hourCycle` option of JavaScript's
/// `Intl.DateTimeFormat`. British English shows a quarter past midnight and a
/// quarter to midnight like this in each hour cycle:
///
/// | Hour cycle | Hours    | Times              |
/// | ---------- | -------- | ------------------ |
/// | `H11`      | 0 to 11  | 0:15 am, 11:45 pm  |
/// | `H12`      | 1 to 12  | 12:15 am, 11:45 pm |
/// | `H23`      | 0 to 23  | 00:15, 23:45       |
/// | `H24`      | 1 to 24  | 24:15, 23:45       |
///
/// With `H11` and `H12`, each locale uses its own words for morning and
/// evening. Those words can move or change the rest of the time.
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

/// The hour cycle a locale shows. That's the one you set with
/// `with_hour_cycle`, or else the locale's own.
pub fn locale_hour_cycle(locale: Locale) -> HourCycle {
  case locale.hour_cycle {
    Some(hour_cycle) -> hour_cycle
    None -> default_hour_cycle(locale)
  }
}

/// The digits a locale writes numbers with, like the `numberingSystem` option
/// of JavaScript's `Intl.DateTimeFormat`. Most locales use `"latn"`, the
/// digits 0 to 9. Persian uses `"arabext"`, like ۱۴۰۵.
///
/// Names and words stay the same. Only the digits change.
pub opaque type NumberingSystem {
  NumberingSystem(name: String)
}

/// A numbering system by its Unicode name, like `"latn"` or `"arab"`, in any
/// case. It returns `Error(Nil)` for a name Intl doesn't support.
pub fn numbering_system(name: String) -> Result(NumberingSystem, Nil) {
  let name = string.lowercase(name)
  case is_numbering_system(name) {
    True -> Ok(NumberingSystem(name))
    False -> Error(Nil)
  }
}

/// The Unicode name of a numbering system, like `"arab"`.
pub fn numbering_system_name(numbering_system: NumberingSystem) -> String {
  numbering_system.name
}

/// Write numbers with other digits, like Arabic with the digits 0 to 9.
///
/// ```gleam
/// let assert Ok(latin) = glintl.numbering_system("latn")
///
/// fa.locale()
/// |> glintl.with_numbering_system(latin)
/// |> date_time.date_formatter(style: date_time.Short)
/// |> date_time.format(timestamp.system_time(), zone: time_zone.utc)
/// // -> "1405/8/4"
/// ```
pub fn with_numbering_system(
  locale: Locale,
  numbering_system: NumberingSystem,
) -> Locale {
  Locale(..locale, numbering_system: Some(numbering_system))
}

/// The numbering system a locale writes numbers with. That's the one you set
/// with `with_numbering_system`, or else the locale's own.
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
/// A numbering system's digits number in the packed data, by its name.
@external(erlang, "glintl_generated_data", "numbering_system")
fn numbering_system_digits(name: String) -> Result(Int, Nil)

@target(erlang)
/// Numbering system names by their digits number, plus 1.
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
  intl_numbering_system(locale.tag, icu_calendar(locale.calendar))
}

@target(javascript)
@external(javascript, "./glintl_ffi.mjs", "numberingSystem")
fn intl_numbering_system(tag: String, calendar: String) -> String

@target(erlang)
/// The packed data's digits number for the numbering system set with
/// `with_numbering_system`, or `None` for the locale's own.
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

/// The `numberingSystem` option of `Intl.DateTimeFormat`, or `""` for the
/// locale's own.
@internal
pub fn intl_numbering_system_option(locale: Locale) -> String {
  case locale.numbering_system {
    None -> ""
    Some(NumberingSystem(name)) -> name
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
