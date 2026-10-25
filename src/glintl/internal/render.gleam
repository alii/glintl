//// Only used on Erlang.

import gleam/int
import gleam/list
import gleam/string
import glintl/internal/data.{
  type Digits, type Pattern, type Token, Ascii, Day, DayPeriod, Digits, Era, H11,
  H12, H23, H24, Hour, Literal, Minute, MonthName, MonthNumber, Second, Weekday,
  Year, Zone,
}

type Local {
  Local(
    year: Int,
    month: Int,
    day: Int,
    weekday: Int,
    hour: Int,
    minute: Int,
    second: Int,
    offset_minutes: Int,
    unix_seconds: Int,
  )
}

pub type Compiled {
  Compiled(pattern: Pattern, digits: Digits, has_minute: Bool, has_second: Bool)
}

pub fn compile(pattern: Pattern, digits: Digits) -> Compiled {
  Compiled(
    pattern:,
    digits:,
    has_minute: list.any(pattern, fn(t) {
      t == Minute(True) || t == Minute(False)
    }),
    has_second: list.any(pattern, fn(t) {
      t == Second(True) || t == Second(False)
    }),
  )
}

pub fn render(
  compiled: Compiled,
  unix_seconds: Int,
  offset_minutes: Int,
) -> String {
  let Compiled(pattern:, digits:, has_minute:, has_second:) = compiled
  let local = to_local(unix_seconds, offset_minutes)
  list.fold(pattern, "", fn(acc, t) {
    acc <> token(t, local, digits, has_minute, has_second)
  })
}

fn token(
  token: Token,
  local: Local,
  digits: Digits,
  has_minute: Bool,
  has_second: Bool,
) -> String {
  case token {
    Literal(text) -> text
    Year(two_digit:) -> {
      // There is no year zero: 0 is 1 BC, -1 is 2 BC, and so on.
      let year = case local.year <= 0 {
        True -> 1 - local.year
        False -> local.year
      }
      case two_digit {
        True -> number(year % 100, True, digits)
        False -> number(year, False, digits)
      }
    }
    MonthNumber(pad:) -> number(local.month, pad, digits)
    MonthName(names:) -> at(names, local.month - 1)
    Day(pad:) -> number(local.day, pad, digits)
    Weekday(names:) -> at(names, local.weekday)
    Hour(pad:, cycle:) -> number(hour(local.hour, cycle), pad, digits)
    Minute(pad:) -> number(local.minute, pad, digits)
    Second(pad:) -> number(local.second, pad, digits)
    DayPeriod(by_hour:, midnight:, noon:) -> {
      let on_the_hour =
        { !has_minute || local.minute == 0 }
        && { !has_second || local.second == 0 }
      case local.hour, on_the_hour {
        0, True -> midnight
        12, True -> noon
        hour, _ -> at(by_hour, hour)
      }
    }
    Era(bc:, ad:) ->
      case local.year <= 0 {
        True -> bc
        False -> ad
      }
    Zone(
      zero:,
      positive:,
      positive_suffix:,
      positive_whole_suffix:,
      negative:,
      negative_suffix:,
      negative_whole_suffix:,
      pad_hours:,
      separator:,
      optional_minutes:,
    ) ->
      // ICU only names the zero offset from 1970. Before then it writes it
      // like any other offset, such as `GMT+0`.
      case local.offset_minutes, local.unix_seconds >= 0 {
        0, True -> zero
        offset, _ -> {
          let #(sign, suffix, whole_suffix) = case offset < 0 {
            True -> #(negative, negative_suffix, negative_whole_suffix)
            False -> #(positive, positive_suffix, positive_whole_suffix)
          }
          let offset = int.absolute_value(offset)
          let hours = number(offset / 60, pad_hours, digits)
          case offset % 60, optional_minutes {
            0, True -> sign <> hours <> whole_suffix
            minutes, _ ->
              sign
              <> hours
              <> separator
              <> number(minutes, True, digits)
              <> suffix
          }
        }
      }
  }
}

fn hour(hour: Int, cycle: data.HourCycle) -> Int {
  case cycle {
    H23 -> hour
    H11 -> hour % 12
    H12 ->
      case hour % 12 {
        0 -> 12
        h -> h
      }
    H24 ->
      case hour {
        0 -> 24
        h -> h
      }
  }
}

fn number(n: Int, pad: Bool, digits: Digits) -> String {
  let text = case pad && n < 10 {
    True -> "0" <> int.to_string(n)
    False -> int.to_string(n)
  }
  case digits {
    Ascii -> text
    Digits(digits) ->
      text
      |> string.to_graphemes
      |> list.map(fn(c) {
        case int.parse(c) {
          Ok(i) -> at(digits, i)
          Error(_) -> c
        }
      })
      |> string.concat
  }
}

fn at(items: List(String), index: Int) -> String {
  case items, index {
    [item, ..], 0 -> item
    [_, ..rest], _ -> at(rest, index - 1)
    [], _ -> ""
  }
}

fn to_local(unix_seconds: Int, offset_minutes: Int) -> Local {
  let seconds = unix_seconds + offset_minutes * 60
  let days = int.floor_divide(seconds, 86_400) |> unwrap
  let rest = seconds - days * 86_400
  let #(year, month, day) = civil_from_days(days)
  // 1970-01-01 was a Thursday, and Sunday is 0.
  let weekday = { { days + 4 } % 7 + 7 } % 7
  Local(
    year:,
    month:,
    day:,
    weekday:,
    hour: rest / 3600,
    minute: rest % 3600 / 60,
    second: rest % 60,
    offset_minutes:,
    unix_seconds:,
  )
}

/// Days since 1970-01-01 to a proleptic Gregorian date.
/// From Howard Hinnant's `civil_from_days`.
fn civil_from_days(days: Int) -> #(Int, Int, Int) {
  let z = days + 719_468
  let era = int.floor_divide(z, 146_097) |> unwrap
  let doe = z - era * 146_097
  let yoe = { doe - doe / 1460 + doe / 36_524 - doe / 146_096 } / 365
  let doy = doe - { 365 * yoe + yoe / 4 - yoe / 100 }
  let mp = { 5 * doy + 2 } / 153
  let day = doy - { 153 * mp + 2 } / 5 + 1
  let month = case mp < 10 {
    True -> mp + 3
    False -> mp - 9
  }
  let year = yoe + era * 400
  let year = case month <= 2 {
    True -> year + 1
    False -> year
  }
  #(year, month, day)
}

fn unwrap(result: Result(Int, Nil)) -> Int {
  case result {
    Ok(n) -> n
    Error(_) -> 0
  }
}
