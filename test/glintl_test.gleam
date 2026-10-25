import gleam/int
import gleam/list
import gleam/string
import gleam/time/duration
import gleam/time/timestamp
import gleeunit
import glintl
import glintl/fixtures
import glintl/locale/en_gb
import glintl/locales

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn fixtures_test() {
  let failures =
    fixtures.cases()
    |> list.filter_map(fn(case_) {
      let #(tag, date, time, seconds, offset, expected) = case_
      let assert Ok(locale) = locales.from_tag(tag)
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
          Ok(string.join(
            [
              tag,
              int.to_string(date),
              int.to_string(time),
              int.to_string(seconds),
              int.to_string(offset),
              string.inspect(expected),
              string.inspect(actual),
            ],
            " ",
          ))
      }
    })
  assert failures == []
}

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

fn result_tag(result: Result(glintl.Locale, Nil)) -> Result(String, Nil) {
  case result {
    Ok(locale) -> Ok(glintl.locale_tag(locale))
    Error(Nil) -> Error(Nil)
  }
}

fn style(index: Int) -> glintl.Style {
  case index {
    1 -> glintl.Full
    2 -> glintl.Long
    3 -> glintl.Medium
    _ -> glintl.Short
  }
}
