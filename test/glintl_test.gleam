import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/duration
import gleam/time/timestamp
import gleeunit
import glintl
@target(erlang)
import glintl/calendar_fixtures
import glintl/date
import glintl/date_time
import glintl/field_fixtures
import glintl/fixtures
@target(erlang)
import glintl/internal/engine
@target(erlang)
import glintl/internal/render
import glintl/locale/en
import glintl/locale/en_gb
import glintl/locale/ja
import glintl/locale/th
import glintl/locale/zh
import glintl/locales
import glintl/time_zone

pub fn main() -> Nil {
  gleeunit.main()
}

// --- The API -----------------------------------------------------------------

pub fn example_test() {
  let formatter =
    date_time.date_time_formatter(
      en_gb.locale(),
      date: date_time.Long,
      time: date_time.Short,
    )
  let assert Ok(moment) = timestamp.parse_rfc3339("2026-10-25T22:40:58Z")
  let assert Ok(zone) = time_zone.offset(hours: 1, minutes: 0)
  assert date_time.format(formatter, moment, zone:)
    == "25 October 2026 at 23:40"
}

pub fn fields_example_test() {
  let formatter =
    date_time.new()
    |> date_time.weekday(glintl.Long)
    |> date_time.day(glintl.Numeric)
    |> date_time.month_name(glintl.Long)
    |> date_time.fields_formatter(en_gb.locale(), _)
  let sunday = timestamp.from_unix_seconds(1_792_929_600)
  assert date_time.format(formatter, sunday, zone: time_zone.utc)
    == "Sunday 25 October"
}

/// Like Intl, with no date or time part a formatter shows a numeric date.
pub fn default_fields_test() {
  let midday = timestamp.from_unix_seconds(1_792_929_600)
  let format = fn(fields) {
    date_time.fields_formatter(en_gb.locale(), fields)
    |> date_time.format(midday, zone: time_zone.utc)
  }
  assert format(date_time.new()) == "25/10/2026"
  assert format(date_time.new() |> date_time.era(glintl.Long))
    == "25/10/2026 Anno Domini"
}

pub fn fraction_test() {
  let formatter =
    date_time.new()
    |> date_time.second(glintl.Numeric)
    |> date_time.fraction(date_time.Hundredths)
    |> date_time.fields_formatter(en_gb.locale(), _)
  let moment =
    timestamp.from_unix_seconds(1_792_929_604)
    |> timestamp.add(duration.milliseconds(987))
  // Fractions are cut off, not rounded.
  assert date_time.format(formatter, moment, zone: time_zone.utc) == "4.98"
}

pub fn from_tag_test() {
  assert locales.from_tag("en_gb") |> result_tag == Ok("en-GB")
  assert locales.from_tag("EN-AU") |> result_tag == Ok("en-AU")
  assert locales.from_tag("en-XX") |> result_tag == Ok("en")
  assert locales.from_tag("zh-TW") |> result_tag == Ok("zh-Hant")
  assert locales.from_tag("fr-CA-x-mine") |> result_tag == Ok("fr-CA")
  assert locales.from_tag("as") |> result_tag == Ok("as")
  assert locales.from_tag("xx") == Error(Nil)
}

pub fn accept_language_test() {
  let tag = fn(result) { result |> result_tag }
  assert locales.from_accept_language("fr-CH, fr;q=0.9, en;q=0.8") |> tag
    == Ok("fr-CH")
  assert locales.from_accept_language("en;q=0.5, ja") |> tag == Ok("ja")
  assert locales.from_accept_language("xx, en-XX;q=0.1") |> tag == Ok("en")
  assert locales.from_accept_language("zh-TW") |> tag == Ok("zh-Hant")
  assert locales.from_accept_language("ja;q=0, *") == Error(Nil)
  assert locales.from_accept_language("") == Error(Nil)

  let supported = [en_gb.locale(), ja.locale(), zh.locale()]
  assert locales.negotiate("fr, en-AU;q=0.9", among: supported) |> tag
    == Ok("en-GB")
  assert locales.negotiate("ja-JP, en", among: supported) |> tag == Ok("ja")
  assert locales.negotiate("zh-TW", among: supported) |> tag == Ok("zh")
  assert locales.negotiate("de, fr", among: supported) == Error(Nil)
  let hebrew = glintl.with_calendar(en_gb.locale(), glintl.Hebrew)
  assert locales.negotiate("en-GB", among: [hebrew]) == Ok(hebrew)
}

pub fn hour_cycle_test() {
  let assert Ok(moment) = timestamp.parse_rfc3339("2026-10-26T22:40:00Z")
  let time = fn(locale) {
    date_time.time_formatter(locale, style: date_time.Short)
    |> date_time.format(moment, zone: time_zone.utc)
  }
  assert glintl.locale_hour_cycle(en_gb.locale()) == glintl.H23
  assert glintl.locale_hour_cycle(en.locale()) == glintl.H12
  assert en.locale() |> glintl.with_hour_cycle(glintl.H23) |> time == "22:40"
  assert en_gb.locale() |> glintl.with_hour_cycle(glintl.H12) |> time
    == "10:40 pm"
  assert ja.locale() |> glintl.with_hour_cycle(glintl.H12) |> time == "午後10:40"
  assert en_gb.locale()
    |> glintl.with_hour_cycle(glintl.H11)
    |> glintl.locale_hour_cycle
    == glintl.H11
  // Japanese writes the date differently next to a 12 hour time.
  assert ja.locale()
    |> glintl.with_hour_cycle(glintl.H12)
    |> date_time.date_time_formatter(
      date: date_time.Long,
      time: date_time.Short,
    )
    |> date_time.format(moment, zone: time_zone.utc)
    == "2026/10/26 午後10:40"
}

pub fn date_test() {
  let birthday = calendar.Date(2026, calendar.October, 26)
  let styled = fn(style) {
    date.date_formatter(en_gb.locale(), style:) |> date.format(birthday)
  }
  assert styled(date.Full) == "Monday, 26 October 2026"
  assert styled(date.Long) == "26 October 2026"
  assert styled(date.Medium) == "26 Oct 2026"
  assert styled(date.Short) == "26/10/2026"

  let options =
    date.new()
    |> date.weekday(glintl.Long)
    |> date.day(glintl.Numeric)
    |> date.month_name(glintl.Long)
  assert date.fields_formatter(en_gb.locale(), options) |> date.format(birthday)
    == "Monday 26 October"

  // Like Intl, an era on its own gets a numeric date.
  assert date.fields_formatter(
      en_gb.locale(),
      date.new() |> date.era(glintl.Long),
    )
    |> date.format(birthday)
    == "26/10/2026 Anno Domini"

  assert en_gb.locale()
    |> glintl.with_calendar(glintl.Hebrew)
    |> date.date_formatter(style: date.Long)
    |> date.format(birthday)
    == "15 Heshvan 5787"
}

pub fn from_name_test() {
  assert time_zone.from_name("Europe/London") |> result.is_ok
  assert time_zone.from_name("europe/london")
    == time_zone.from_name("Europe/London")
  assert time_zone.from_name("GB") |> result.is_ok
  assert time_zone.from_name("UTC") |> result.is_ok
  assert time_zone.from_name("Nowhere/Special") == Error(Nil)
  assert time_zone.from_name("+01:00") == Error(Nil)
  assert time_zone.from_name("") == Error(Nil)
}

pub fn local_test() {
  assert time_zone.local() |> result.is_ok
}

@target(erlang)
/// On Erlang, `TZ` wins over the system's settings, as a name or a path.
pub fn local_from_tz_test() {
  assert with_tz("Asia/Tokyo", time_zone.local)
    == time_zone.from_name("Asia/Tokyo")
  assert with_tz(":/usr/share/zoneinfo/Europe/Paris", time_zone.local)
    == time_zone.from_name("Europe/Paris")
  assert with_tz("Nowhere/Special", time_zone.local) == Error(Nil)
}

@target(erlang)
@external(erlang, "glintl_test_ffi", "with_tz")
fn with_tz(value: String, run: fn() -> a) -> a

/// A named zone's offset follows summer time, and old local mean time,
/// which can be off by seconds.
pub fn named_zone_test() {
  let time = fn(zone_name, rfc3339) {
    let assert Ok(zone) = time_zone.from_name(zone_name)
    let assert Ok(moment) = timestamp.parse_rfc3339(rfc3339)
    date_time.time_formatter(en_gb.locale(), style: date_time.Medium)
    |> date_time.format(moment, zone:)
  }
  assert time("Europe/London", "2026-01-15T12:00:00Z") == "12:00:00"
  assert time("Europe/London", "2026-07-15T12:00:00Z") == "13:00:00"
  // The clocks go forward at 01:00 UTC on the last Sunday of March.
  assert time("Europe/London", "2026-03-29T00:59:59Z") == "00:59:59"
  assert time("Europe/London", "2026-03-29T01:00:00Z") == "02:00:00"
  assert time("Europe/London", "2100-07-15T12:00:00Z") == "13:00:00"
  assert time("Europe/London", "1800-06-01T12:00:00Z") == "11:58:45"
  assert time("Australia/Sydney", "2026-01-15T00:00:00Z") == "11:00:00"
  assert time("Australia/Sydney", "2026-07-15T00:00:00Z") == "10:00:00"
  assert time("Asia/Kolkata", "2026-07-15T00:00:00Z") == "05:30:00"
}

/// Named zones show their names in the locale. Fixed offsets, and zones the
/// locale has no name for, show the offset.
pub fn zone_names_test() {
  let assert Ok(summer) = timestamp.parse_rfc3339("2026-07-15T12:00:00Z")
  let assert Ok(winter) = timestamp.parse_rfc3339("2026-01-15T12:00:00Z")
  let time = fn(locale, style, moment, name) {
    let assert Ok(zone) = time_zone.from_name(name)
    date_time.time_formatter(locale, style:)
    |> date_time.format(moment, zone:)
  }
  assert time(en_gb.locale(), date_time.Full, summer, "Europe/London")
    == "13:00:00 British Summer Time"
  assert time(en_gb.locale(), date_time.Long, summer, "Europe/London")
    == "13:00:00 BST"
  assert time(en_gb.locale(), date_time.Full, winter, "Europe/London")
    == "12:00:00 Greenwich Mean Time"
  assert time(en.locale(), date_time.Long, summer, "America/New_York")
    == "8:00:00 AM EDT"
  // English has no short name for Western European Time.
  assert time(en.locale(), date_time.Long, winter, "Europe/Lisbon")
    == "12:00:00 PM GMT+0"
  assert time(en_gb.locale(), date_time.Full, summer, "Etc/GMT-5")
    == "17:00:00 GMT+05:00"
  let assert Ok(plus_one) = time_zone.offset(hours: 1, minutes: 0)
  assert date_time.time_formatter(en_gb.locale(), style: date_time.Full)
    |> date_time.format(summer, zone: plus_one)
    == "13:00:00 GMT+01:00"
}

/// Offsets must be under 24 hours either way, because that's all JavaScript's
/// `Intl` allows.
pub fn offset_test() {
  assert time_zone.offset(hours: 5, minutes: 30) |> result.is_ok
  assert time_zone.offset(hours: -3, minutes: -30) |> result.is_ok
  assert time_zone.offset(hours: 23, minutes: 59) |> result.is_ok
  assert time_zone.offset(hours: -23, minutes: -59) |> result.is_ok
  assert time_zone.offset(hours: 24, minutes: 0)
    == Error(time_zone.OffsetTooLarge)
  assert time_zone.offset(hours: -24, minutes: 0)
    == Error(time_zone.OffsetTooLarge)
  assert time_zone.offset(hours: 1, minutes: 60)
    == Error(time_zone.MinutesTooLarge)
  assert time_zone.offset(hours: -3, minutes: 30) == Error(time_zone.MixedSigns)
  assert time_zone.from_duration(duration.hours(1)) == Ok(hours(1))
  assert time_zone.from_duration(duration.seconds(-1))
    == time_zone.offset(hours: 0, minutes: -1)
  assert time_zone.from_duration(duration.hours(24))
    == Error(time_zone.OffsetTooLarge)
  assert time_zone.from_duration(duration.hours(-25))
    == Error(time_zone.OffsetTooLarge)
}

/// Locales can be compared and used as `Dict` keys on both targets.
pub fn locale_equality_test() {
  let hebrew = glintl.with_calendar(en_gb.locale(), glintl.Hebrew)
  assert en_gb.locale() == en_gb.locale()
  assert locales.from_tag("en-GB") == Ok(en_gb.locale())
  assert hebrew == glintl.with_calendar(en_gb.locale(), glintl.Hebrew)
  assert hebrew != en_gb.locale()
  assert en_gb.locale() != ja.locale()
}

pub fn calendar_test() {
  let assert Ok(moment) = timestamp.parse_rfc3339("2026-10-25T22:40:58Z")
  let format = fn(locale, moment) {
    date_time.date_formatter(locale, style: date_time.Long)
    |> date_time.format(moment, zone: hours(1))
  }
  assert glintl.locale_calendar(en_gb.locale()) == glintl.Gregorian
  assert glintl.locale_calendar(th.locale()) == glintl.Buddhist
  assert format(th.locale(), moment) == "25 ตุลาคม 2569"
  assert en_gb.locale()
    |> glintl.with_calendar(glintl.Hebrew)
    |> format(moment)
    == "14 Heshvan 5787"
  let assert Ok(reiwa) = timestamp.parse_rfc3339("2019-05-01T12:00:00Z")
  assert ja.locale()
    |> glintl.with_calendar(glintl.Japanese)
    |> format(reiwa)
    == "令和元年5月1日"
  let assert Ok(leap_month) = timestamp.parse_rfc3339("2025-08-01T12:00:00Z")
  assert zh.locale()
    |> glintl.with_calendar(glintl.Chinese)
    |> format(leap_month)
    == "2025乙巳年闰六月8"
}

/// On Erlang, calendars with their own months cover the years 1 to 4000.
/// Other days are written in the Gregorian calendar.
pub fn outside_calendar_tables_test() {
  let assert Ok(year_5000) = timestamp.parse_rfc3339("5000-01-01T12:00:00Z")
  let hebrew =
    en_gb.locale()
    |> glintl.with_calendar(glintl.Hebrew)
    |> date_time.date_formatter(style: date_time.Long)
    |> date_time.format(year_5000, zone: time_zone.utc)
  let expected = case on_erlang() {
    True -> "1 January 5000"
    False -> "20 Kislev 8760"
  }
  assert hebrew == expected
}

// --- Generated fixtures --------------------------------------------------------
//
// Only the first failures are shown, because a broken pattern can fail
// thousands of cases at once.

/// Checks every locale, style and calendar against `Intl.DateTimeFormat`.
pub fn fixtures_test() {
  let failures =
    fixtures.cases()
    |> list.filter_map(fn(case_) {
      let #(tag, calendar, date, time, seconds, offset, expected) = case_
      let assert Ok(locale) = locales.from_tag(tag)
      let locale = case calendar {
        "" -> locale
        id -> glintl.with_calendar(locale, calendar_from_id(id))
      }
      let formatter = case date, time {
        0, time -> date_time.time_formatter(locale, style: style(time))
        date, 0 -> date_time.date_formatter(locale, style: style(date))
        date, time ->
          date_time.date_time_formatter(
            locale,
            date: style(date),
            time: style(time),
          )
      }
      let assert Ok(zone) = time_zone.from_duration(duration.minutes(offset))
      let actual =
        date_time.format(formatter, timestamp.from_unix_seconds(seconds), zone:)
      case actual == expected {
        True -> Error(Nil)
        False ->
          Ok(
            [tag, calendar]
            |> list.append(list.map(
              [date, time, seconds, offset],
              int.to_string,
            ))
            |> list.append([string.inspect(expected), string.inspect(actual)])
            |> string.join(" "),
          )
      }
    })
  assert list.take(failures, 30) == []
}

/// Checks fields in every locale and calendar against `Intl.DateTimeFormat`.
pub fn field_fixtures_test() {
  let failures =
    field_fixtures.cases()
    |> list.filter_map(fn(case_) {
      let #(
        tag,
        calendar,
        hour_cycle,
        shown,
        seconds,
        milliseconds,
        offset,
        expected,
      ) = case_
      let assert Ok(locale) = locales.from_tag(tag)
      let locale = case calendar {
        "" -> locale
        id -> glintl.with_calendar(locale, calendar_from_id(id))
      }
      let locale = case hour_cycle {
        "" -> locale
        "h11" -> glintl.with_hour_cycle(locale, glintl.H11)
        "h12" -> glintl.with_hour_cycle(locale, glintl.H12)
        "h23" -> glintl.with_hour_cycle(locale, glintl.H23)
        _ -> glintl.with_hour_cycle(locale, glintl.H24)
      }
      let formatter = date_time.fields_formatter(locale, parse_fields(shown))
      let assert Ok(zone) = time_zone.from_duration(duration.minutes(offset))
      let moment =
        timestamp.from_unix_seconds(seconds)
        |> timestamp.add(duration.milliseconds(milliseconds))
      let actual = date_time.format(formatter, moment, zone:)
      case actual == expected {
        True -> Error(Nil)
        False ->
          Ok(
            [tag, calendar, hour_cycle, shown]
            |> list.append(list.map(
              [seconds, milliseconds, offset],
              int.to_string,
            ))
            |> list.append([string.inspect(expected), string.inspect(actual)])
            |> string.join(" "),
          )
      }
    })
  assert list.take(failures, 30) == []
}

/// Reads fields from a fixture, like `day=numeric,month=short`.
fn parse_fields(text: String) -> date_time.Fields {
  text
  |> string.split(",")
  |> list.fold(date_time.new(), fn(f, option) {
    let assert [name, value] = string.split(option, "=")
    case name, value {
      "weekday", _ -> date_time.weekday(f, width(value))
      "era", _ -> date_time.era(f, width(value))
      "year", _ -> date_time.year(f, digits(value))
      "month", "numeric" | "month", "2-digit" ->
        date_time.month(f, digits(value))
      "month", _ -> date_time.month_name(f, width(value))
      "day", _ -> date_time.day(f, digits(value))
      "dayPeriod", _ -> date_time.day_period(f, width(value))
      "hour", _ -> date_time.hour(f, digits(value))
      "minute", _ -> date_time.minute(f, digits(value))
      "second", _ -> date_time.second(f, digits(value))
      "fractionalSecondDigits", "1" -> date_time.fraction(f, date_time.Tenths)
      "fractionalSecondDigits", "2" ->
        date_time.fraction(f, date_time.Hundredths)
      "fractionalSecondDigits", _ ->
        date_time.fraction(f, date_time.Thousandths)
      "timeZoneName", "short" ->
        date_time.time_zone_name(f, date_time.ShortName)
      "timeZoneName", "long" -> date_time.time_zone_name(f, date_time.LongName)
      "timeZoneName", "shortOffset" ->
        date_time.time_zone_name(f, date_time.ShortOffset)
      "timeZoneName", _ -> date_time.time_zone_name(f, date_time.LongOffset)
      _, _ -> panic as { "unknown field in the fixtures: " <> name }
    }
  })
}

fn width(value: String) -> glintl.Width {
  case value {
    "narrow" -> glintl.Narrow
    "short" -> glintl.Short
    _ -> glintl.Long
  }
}

fn digits(value: String) -> glintl.Digits {
  case value {
    "numeric" -> glintl.Numeric
    _ -> glintl.TwoDigit
  }
}

@target(erlang)
/// Checks the Erlang calendar maths field by field. JavaScript uses `Intl`
/// for this, so there's nothing to check there.
pub fn calendar_fields_test() {
  let failures =
    calendar_fixtures.cases()
    |> list.filter(fn(case_) {
      let #(calendar, day, expected) = case_
      render.calendar_fields(
        engine.calendar_math(calendar_from_id(calendar)),
        day,
      )
      != expected
    })
  assert list.take(failures, 30) == []
}

// --- Helpers -------------------------------------------------------------------

fn hours(hours: Int) -> time_zone.TimeZone {
  let assert Ok(zone) = time_zone.offset(hours:, minutes: 0)
  zone
}

@external(erlang, "glintl_test_ffi", "on_erlang")
@external(javascript, "./glintl_test_ffi.mjs", "on_erlang")
fn on_erlang() -> Bool

fn result_tag(result: Result(glintl.Locale, Nil)) -> Result(String, Nil) {
  case result {
    Ok(locale) -> Ok(glintl.locale_tag(locale))
    Error(Nil) -> Error(Nil)
  }
}

/// The calendar for an ICU calendar name, which the fixtures use.
fn calendar_from_id(id: String) -> glintl.Calendar {
  case id {
    "gregory" -> glintl.Gregorian
    "iso8601" -> glintl.Iso8601
    "buddhist" -> glintl.Buddhist
    "japanese" -> glintl.Japanese
    "roc" -> glintl.RepublicOfChina
    "persian" -> glintl.Persian
    "indian" -> glintl.Indian
    "hebrew" -> glintl.Hebrew
    "chinese" -> glintl.Chinese
    "dangi" -> glintl.Dangi
    "coptic" -> glintl.Coptic
    "ethiopic" -> glintl.Ethiopic
    "ethioaa" -> glintl.EthiopicAmeteAlem
    "islamic-civil" -> glintl.IslamicCivil
    "islamic-tbla" -> glintl.IslamicTabular
    "islamic-umalqura" -> glintl.IslamicUmmAlQura
    _ -> panic as { "unknown calendar in the fixtures: " <> id }
  }
}

/// Reads a style from a fixture, where 1 is full and 4 is short.
fn style(index: Int) -> date_time.Style {
  case index {
    1 -> date_time.Full
    2 -> date_time.Long
    3 -> date_time.Medium
    4 -> date_time.Short
    _ -> panic as { "unknown style in the fixtures: " <> int.to_string(index) }
  }
}
