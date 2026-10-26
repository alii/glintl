//// Calendars with their own months, and ICU's week-based year. Kept apart
//// from `render` so that only people using them load them.

import gleam/int
import gleam/list
import glintl/internal/data.{
  type HomogenousUnknownLengthTuple, type Local, type YearRule, Local, YearRule,
}

pub fn table_local(
  cyclic cyclic: Bool,
  starts starts: HomogenousUnknownLengthTuple(Int),
  shapes shapes: HomogenousUnknownLengthTuple(Int),
  months months: HomogenousUnknownLengthTuple(List(#(Int, Int))),
  years years: List(YearRule),
  day_zero day_zero: List(#(Int, Int)),
  epoch_day epoch_day: Int,
  hour hour: Int,
  minute minute: Int,
  second second: Int,
  offset_minutes offset_minutes: Int,
  unix_seconds unix_seconds: Int,
) -> Result(Local, Nil) {
  let count = tuple_size(starts)
  let first = element(1, starts)
  let last = element(count, starts)
  case epoch_day < first || epoch_day >= last {
    True -> Error(Nil)
    False -> {
      // Guess the year from the average year length, then step to it.
      let guess = { epoch_day - first } * { count - 1 } / { last - first }
      let i = find_year(starts, int.clamp(guess, 0, count - 2), epoch_day)
      let start = element(i + 1, starts)
      let shape = element(element(i + 1, shapes) + 1, months)
      let #(month, day) = case day_zero {
        [] -> month_and_day(shape, epoch_day - start)
        _ ->
          case list.key_find(day_zero, epoch_day) {
            Ok(month) -> #(month, -1)
            Error(Nil) -> month_and_day(shape, epoch_day - start)
          }
      }
      let YearRule(from:, era:, year:, year_step:, extended:, related:, cycle:) =
        year_rule(years, i)
      let n = i - from
      let step = case cyclic {
        True -> n
        False -> 0
      }
      Ok(Local(
        epoch_day:,
        hour:,
        minute:,
        second:,
        offset_minutes:,
        unix_seconds:,
        era:,
        year: year + year_step * n,
        extended: extended + n,
        related: related + step,
        cycle: { cycle + step } % 60,
        month:,
        day: day + 1,
        year_start: start,
        next_year_start: element(i + 2, starts),
      ))
    }
  }
}

/// The rule for a table year. Rules are newest first, and the last starts at
/// year 0.
fn year_rule(years: List(YearRule), year: Int) -> YearRule {
  case years {
    [rule] -> rule
    [rule, ..rest] ->
      case rule.from <= year {
        True -> rule
        False -> year_rule(rest, year)
      }
    [] ->
      YearRule(
        from: 0,
        era: 0,
        year: 0,
        year_step: 1,
        extended: 0,
        related: 0,
        cycle: 0,
      )
  }
}

fn find_year(
  starts: HomogenousUnknownLengthTuple(Int),
  i: Int,
  epoch_day: Int,
) -> Int {
  case element(i + 1, starts) > epoch_day, element(i + 2, starts) <= epoch_day {
    True, _ -> find_year(starts, i - 1, epoch_day)
    _, True -> find_year(starts, i + 1, epoch_day)
    _, _ -> i
  }
}

fn month_and_day(shape: List(#(Int, Int)), rest: Int) -> #(Int, Int) {
  case shape {
    [#(_, length), ..others] if rest >= length && others != [] ->
      month_and_day(others, rest - length)
    [#(month, _), ..] -> #(month, rest)
    [] -> #(0, rest)
  }
}

/// ICU's week-based year: weeks start on `first_day` (1 is Monday), and a
/// year's first week is the first with at least `minimal_days` days in it.
pub fn week_year(
  m: Local,
  first_day: Int,
  minimal_days: Int,
  exceptions: List(#(Int, Int)),
) -> Int {
  // Calendars with Gregorian months start their years on 1 January.
  let #(year_start, next_year_start) = case m.next_year_start {
    0 -> #(
      days_from_civil(m.extended, 1, 1),
      days_from_civil(m.extended + 1, 1, 1),
    )
    next -> #(m.year_start, next)
  }
  let first_week = fn(year_start, extended) {
    case list.key_find(exceptions, extended) {
      Ok(day) -> day
      Error(_) -> {
        // 1970-01-01 was a Thursday, day 4.
        let weekday = modulo(year_start + 3, 7) + 1
        let week_start = year_start - modulo(weekday - first_day, 7)
        case 7 - { year_start - week_start } >= minimal_days {
          True -> week_start
          False -> week_start + 7
        }
      }
    }
  }
  case
    m.epoch_day >= first_week(next_year_start, m.extended + 1),
    m.epoch_day < first_week(year_start, m.extended)
  {
    True, _ -> m.extended + 1
    _, True -> m.extended - 1
    _, _ -> m.extended
  }
}

/// A proleptic Gregorian date to days since 1970-01-01.
/// From Howard Hinnant's `days_from_civil`.
fn days_from_civil(year: Int, month: Int, day: Int) -> Int {
  let year = case month <= 2 {
    True -> year - 1
    False -> year
  }
  let era = floor_divide(year, 400)
  let yoe = year - era * 400
  let mp = case month > 2 {
    True -> month - 3
    False -> month + 9
  }
  let doy = { 153 * mp + 2 } / 5 + day - 1
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  era * 146_097 + doe - 719_468
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

@external(erlang, "erlang", "element")
fn element(_index: Int, _tuple: HomogenousUnknownLengthTuple(a)) -> a {
  panic as "only used on Erlang"
}

@external(erlang, "erlang", "tuple_size")
fn tuple_size(_tuple: HomogenousUnknownLengthTuple(a)) -> Int {
  panic as "only used on Erlang"
}
