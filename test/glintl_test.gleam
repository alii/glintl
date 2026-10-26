import gleam/int
import gleam/list
import gleam/string
import gleam/time/duration
import gleam/time/timestamp
import gleeunit
import glintl
import glintl/calendar_fixtures
import glintl/fixtures
import glintl/internal/render
import glintl/locale/en_gb
import glintl/locale/ja
import glintl/locale/th
import glintl/locale/zh
import glintl/locales

pub fn main() -> Nil {
  gleeunit.main()
}

// --- The API -----------------------------------------------------------------

pub fn example_test() {
  let formatter =
    glintl.date_time_formatter(
      en_gb.locale(),
      date: glintl.Long,
      time: glintl.Short,
    )
  let assert Ok(moment) = timestamp.parse_rfc3339("2026-10-25T22:40:58Z")
  assert glintl.format(formatter, moment, offset: duration.hours(1))
    == "25 October 2026 at 23:40"
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

pub fn calendar_test() {
  let assert Ok(moment) = timestamp.parse_rfc3339("2026-10-25T22:40:58Z")
  let format = fn(locale, moment) {
    glintl.date_formatter(locale, style: glintl.Long)
    |> glintl.format(moment, offset: duration.hours(1))
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
    == "2025乙巳年闰六月初八"
}

/// On Erlang, calendars with their own months cover the years 1 to 4000.
/// Other days are written in the Gregorian calendar.
pub fn outside_calendar_tables_test() {
  let assert Ok(year_5000) = timestamp.parse_rfc3339("5000-01-01T12:00:00Z")
  let hebrew =
    en_gb.locale()
    |> glintl.with_calendar(glintl.Hebrew)
    |> glintl.date_formatter(style: glintl.Long)
    |> glintl.format(year_5000, offset: duration.hours(0))
  let expected = case on_erlang() {
    True -> "1 January 5000"
    False -> "20 Kislev 8760"
  }
  assert hebrew == expected
}

// --- Generated fixtures --------------------------------------------------------
//
// Only the first failures are shown, as a broken pattern can fail thousands of
// cases at once.

/// Every locale, style and calendar, checked against `Intl.DateTimeFormat`.
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
        0, time -> glintl.time_formatter(locale, style: style(time))
        date, 0 -> glintl.date_formatter(locale, style: style(date))
        date, time ->
          glintl.date_time_formatter(
            locale,
            date: style(date),
            time: style(time),
          )
      }
      let actual =
        glintl.format(
          formatter,
          timestamp.from_unix_seconds(seconds),
          offset: duration.minutes(offset),
        )
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

/// The Erlang calendar maths, checked field by field. JavaScript uses `Intl`
/// for this, so there is nothing to check there.
pub fn calendar_fields_test() {
  case on_erlang() {
    False -> Nil
    True -> {
      let failures =
        calendar_fixtures.cases()
        |> list.filter(fn(case_) {
          let #(calendar, day, expected) = case_
          render.calendar_fields(calendar, day) != expected
        })
      assert list.take(failures, 30) == []
    }
  }
}

// --- Helpers -------------------------------------------------------------------

@external(erlang, "glintl_test_ffi", "on_erlang")
@external(javascript, "./glintl_test_ffi.mjs", "on_erlang")
fn on_erlang() -> Bool

fn result_tag(result: Result(glintl.Locale, Nil)) -> Result(String, Nil) {
  case result {
    Ok(locale) -> Ok(glintl.locale_tag(locale))
    Error(Nil) -> Error(Nil)
  }
}

/// ICU's name for a calendar, as the fixtures use.
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

/// A style as the fixtures write it: 1 to 4 for full to short.
fn style(index: Int) -> glintl.Style {
  case index {
    1 -> glintl.Full
    2 -> glintl.Long
    3 -> glintl.Medium
    4 -> glintl.Short
    _ -> panic as { "unknown style in the fixtures: " <> int.to_string(index) }
  }
}
