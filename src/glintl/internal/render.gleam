//// Only used on Erlang.

import gleam/int
import gleam/list
import gleam/string
import glintl/internal/calendar
import glintl/internal/data.{
  type Digits, type EraFormats, type Formats, type Local, type Math,
  type Pattern, type Token, Ascii, AsciiDigits, Day, DayName, DayPeriod, Digits,
  Era, EraFormats, EraRule, ExtendedYear, Formats, GlueDate, GlueText, GlueTime,
  H11, H12, H23, H24, Hour, Literal, Local, Minute, MonthName, MonthNumber,
  NoMath, Proleptic, RelatedYear, Second, Table, WeekYear, Weekday, Year,
  YearName, Zone,
}
import glintl/internal/math

/// A formatter's patterns, ready to render.
pub type Compiled {
  Compiled(
    main: Prepared,
    /// Patterns for eras that ICU formats differently.
    eras: List(#(Int, Prepared)),
    digits: Digits,
    math: Math,
    /// Used for days outside a table calendar's years.
    fallback: Fallback,
  )
}

pub type Fallback {
  Fallback(Compiled)
  NoFallback
}

pub type Prepared {
  Prepared(pattern: Pattern, has_minute: Bool, has_second: Bool)
}

/// `date` and `time` are 0 for "not shown", or 1 to 4 for full to short.
pub fn compile(
  formats: Formats,
  digits: Digits,
  math: Math,
  date: Int,
  time: Int,
  fallback: Fallback,
) -> Compiled {
  let Formats(dates:, times:, glues:, eras:) = formats
  let main = pattern(dates, times, glues, [], date, time)
  let eras = case date {
    0 -> []
    _ ->
      list.map(eras, fn(era: EraFormats) {
        let EraFormats(era:, dates:, combined:) = era
        #(era, prepare(pattern(dates, times, glues, combined, date, time)))
      })
  }
  Compiled(main: prepare(main), eras:, digits:, math:, fallback:)
}

fn pattern(
  dates: List(Pattern),
  times: List(Pattern),
  glues: List(data.Glue),
  combined: List(Pattern),
  date: Int,
  time: Int,
) -> Pattern {
  case date, time, combined {
    0, time, _ -> at(times, time - 1, [])
    date, 0, _ -> at(dates, date - 1, [])
    date, time, [] -> {
      let date_pattern = at(dates, date - 1, [])
      let time_pattern = at(times, time - 1, [])
      list.flat_map(at(glues, date - 1, []), fn(piece) {
        case piece {
          GlueText(text) -> [Literal(text)]
          GlueDate -> date_pattern
          GlueTime -> time_pattern
        }
      })
    }
    date, time, combined -> at(combined, { date - 1 } * 4 + time - 1, [])
  }
}

fn prepare(pattern: Pattern) -> Prepared {
  Prepared(
    pattern:,
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
  let seconds = unix_seconds + offset_minutes * 60
  let epoch_day = floor_divide(seconds, 86_400)
  let rest = seconds - epoch_day * 86_400
  case
    local(compiled.math, epoch_day, rest, offset_minutes, unix_seconds),
    compiled.fallback
  {
    Ok(local), _ -> {
      let Prepared(pattern:, has_minute:, has_second:) = case compiled.eras {
        [] -> compiled.main
        eras ->
          case list.key_find(eras, local.era) {
            Ok(prepared) -> prepared
            Error(Nil) -> compiled.main
          }
      }
      tokens(pattern, local, compiled.digits, has_minute, has_second, "")
    }
    Error(Nil), Fallback(gregorian) ->
      render(gregorian, unix_seconds, offset_minutes)
    Error(Nil), NoFallback -> ""
  }
}

fn tokens(
  pattern: Pattern,
  local: Local,
  digits: Digits,
  has_minute: Bool,
  has_second: Bool,
  acc: String,
) -> String {
  case pattern {
    [] -> acc
    [part, ..rest] ->
      tokens(
        rest,
        local,
        digits,
        has_minute,
        has_second,
        acc <> token(part, local, digits, has_minute, has_second),
      )
  }
}

fn token(
  part: Token,
  m: Local,
  digits: Digits,
  has_minute: Bool,
  has_second: Bool,
) -> String {
  case part {
    Literal(text) -> text
    AsciiDigits(inner) -> token(inner, m, Ascii, has_minute, has_second)
    Year(two_digit: True, minus:, first: _) -> {
      let sign = case m.year < 0 {
        True -> minus
        False -> ""
      }
      sign <> number(int.absolute_value(m.year) % 100, True, digits)
    }
    Year(two_digit: False, minus:, first:) ->
      case m.year, first {
        1, "" -> number(1, False, digits)
        1, first -> first
        year, _ -> signed(year, minus, digits)
      }
    WeekYear(minus:, first_day:, minimal_days:, exceptions:) ->
      signed(
        calendar.week_year(m, first_day, minimal_days, exceptions),
        minus,
        digits,
      )
    ExtendedYear(minus:) -> signed(m.extended, minus, digits)
    RelatedYear -> signed(m.related, "-", digits)
    YearName(names:) -> at(names, m.cycle, "")
    MonthNumber(pad:) -> number(m.month + 1, pad, digits)
    MonthName(names:) -> at(names, m.month, "")
    Day(pad:) -> number(m.day, pad, digits)
    DayName(names:) -> at(names, m.day, "")
    // 1970-01-01 was a Thursday, and Sunday is 0.
    Weekday(names:) -> at(names, modulo(m.epoch_day + 4, 7), "")
    Era(names:) -> at(names, m.era, "")
    Hour(pad:, cycle:) -> number(hour(m.hour, cycle), pad, digits)
    Minute(pad:) -> number(m.minute, pad, digits)
    Second(pad:) -> number(m.second, pad, digits)
    DayPeriod(by_hour:, midnight:, noon:) -> {
      let on_the_hour =
        { !has_minute || m.minute == 0 } && { !has_second || m.second == 0 }
      case m.hour, on_the_hour {
        0, True -> midnight
        12, True -> noon
        hour, _ -> at(by_hour, hour, "")
      }
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
      case m.offset_minutes, m.unix_seconds >= 0 {
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

// --- Calendars --------------------------------------------------------------

/// A day's era, year, extended year, related year, cycle year, month and day
/// in a calendar, or `[]` if the calendar doesn't cover it. For tests.
@internal
pub fn calendar_fields(calendar: Int, epoch_day: Int) -> List(Int) {
  case local(math.math(calendar), epoch_day, 0, 0, epoch_day * 86_400) {
    Ok(m) -> [m.era, m.year, m.extended, m.related, m.cycle, m.month, m.day]
    Error(Nil) -> []
  }
}

fn local(
  math: Math,
  epoch_day: Int,
  rest: Int,
  offset_minutes: Int,
  unix_seconds: Int,
) -> Result(Local, Nil) {
  let hour = rest / 3600
  let minute = rest % 3600 / 60
  let second = rest % 60
  case math {
    Proleptic(eras:) -> {
      let #(y, m, d) = civil_from_days(epoch_day)
      let EraRule(era:, base:, sign:, ..) = era_rule(eras, epoch_day)
      Ok(Local(
        epoch_day:,
        hour:,
        minute:,
        second:,
        offset_minutes:,
        unix_seconds:,
        era:,
        year: base + sign * y,
        extended: y,
        related: y,
        cycle: 0,
        month: m - 1,
        day: d,
        year_start: 0,
        next_year_start: 0,
      ))
    }
    Table(cyclic:, starts:, shapes:, months:, years:, day_zero:) ->
      calendar.table_local(
        cyclic:,
        starts:,
        shapes:,
        months:,
        years:,
        day_zero:,
        epoch_day:,
        hour:,
        minute:,
        second:,
        offset_minutes:,
        unix_seconds:,
      )
    NoMath -> Error(Nil)
  }
}

/// The era a day is in. Eras are newest first, and the last starts at the
/// start of time.
fn era_rule(eras: List(data.EraRule), epoch_day: Int) -> data.EraRule {
  case eras {
    [rule] -> rule
    [rule, ..rest] ->
      case rule.start <= epoch_day {
        True -> rule
        False -> era_rule(rest, epoch_day)
      }
    [] -> EraRule(start: 0, era: 0, base: 0, sign: 1)
  }
}

/// Days since 1970-01-01 to a proleptic Gregorian date.
/// From Howard Hinnant's `civil_from_days`.
fn civil_from_days(days: Int) -> #(Int, Int, Int) {
  let z = days + 719_468
  let era = floor_divide(z, 146_097)
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

// --- Numbers and lists -------------------------------------------------------

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

fn signed(n: Int, minus: String, digits: Digits) -> String {
  case n < 0 {
    True -> minus <> number(-n, False, digits)
    False -> number(n, False, digits)
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
          Ok(i) -> at(digits, i, c)
          Error(_) -> c
        }
      })
      |> string.concat
  }
}

fn at(items: List(a), index: Int, default: a) -> a {
  case items, index {
    [item, ..], 0 -> item
    [_, ..rest], _ -> at(rest, index - 1, default)
    [], _ -> default
  }
}

fn modulo(n: Int, by: Int) -> Int {
  { n % by + by } % by
}

fn floor_divide(n: Int, by: Int) -> Int {
  case int.floor_divide(n, by) {
    Ok(result) -> result
    Error(_) -> 0
  }
}
