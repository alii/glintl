//// Calendars with their own months, ICU's week-based year, and the Julian
//// calendar.

import gleam/int
import gleam/list
import glintl/internal/data.{
  type HomogenousUnknownLengthTuple, type Local, type YearRule, Local, YearRule,
}

/// The Chinese and Dangi calendars name years in a cycle of this many.
const years_in_cycle = 60

pub const days_per_week = 7

/// Weekdays here are numbered from Monday, as ICU's week data does, and
/// 1970-01-01 was a Thursday.
const thursday_from_monday = 4

/// Days from 0000-03-01 to 1970-01-01. Hinnant's algorithms count from
/// 1 March, so leap days fall at the end of their years.
pub const days_from_march_of_year_zero = 719_468

pub const days_per_400_years = 146_097

/// The Julian day number of 1970-01-01.
const julian_day_of_unix_epoch = 2_440_588

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
  // `starts` ends with the day after the last year.
  let count = size(starts)
  let first = nth(starts, 0)
  let end = nth(starts, count - 1)
  let last_year = count - 2
  case epoch_day < first || epoch_day >= end, years {
    True, _ | _, [] -> Error(Nil)
    False, [newest, ..older] -> {
      // Guess the year from the average year length, then step to it.
      let guess = { epoch_day - first } * { count - 1 } / { end - first }
      let i = find_year(starts, int.clamp(guess, 0, last_year), epoch_day)
      let start = nth(starts, i)
      let shape = nth(months, nth(shapes, i))
      let #(month, day) = case day_zero {
        [] -> month_and_day(shape, epoch_day - start)
        _ ->
          case list.key_find(day_zero, epoch_day) {
            Ok(month) -> #(month, 0)
            Error(Nil) -> month_and_day(shape, epoch_day - start)
          }
      }
      let YearRule(from:, era:, year:, year_step:, extended:, related:, cycle:) =
        year_rule(newest, older, i)
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
        cycle: { cycle + step } % years_in_cycle,
        month:,
        day:,
        year_start: start,
        next_year_start: nth(starts, i + 1),
      ))
    }
  }
}

/// The rule for a table year. Rules are newest first, and the oldest starts
/// at the first year.
fn year_rule(rule: YearRule, older: List(YearRule), year: Int) -> YearRule {
  case older, rule.from <= year {
    [], _ | _, True -> rule
    [next, ..rest], False -> year_rule(next, rest, year)
  }
}

fn find_year(
  starts: HomogenousUnknownLengthTuple(Int),
  i: Int,
  epoch_day: Int,
) -> Int {
  case nth(starts, i) > epoch_day, nth(starts, i + 1) <= epoch_day {
    True, _ -> find_year(starts, i - 1, epoch_day)
    _, True -> find_year(starts, i + 1, epoch_day)
    _, _ -> i
  }
}

/// The month and day of the month, `days` days into a year.
fn month_and_day(shape: List(#(Int, Int)), days: Int) -> #(Int, Int) {
  case shape {
    [#(_, length), ..others] if days >= length && others != [] ->
      month_and_day(others, days - length)
    [#(month, _), ..] -> #(month, days + 1)
    [] -> #(0, days + 1)
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
  // Calendars with Gregorian months leave their year bounds to here, as
  // their years start on 1 January.
  let #(year_start, next_year_start) = case
    m.next_year_start == data.start_of_time
  {
    True -> #(
      days_from_civil(m.extended, 1, 1),
      days_from_civil(m.extended + 1, 1, 1),
    )
    False -> #(m.year_start, m.next_year_start)
  }
  let first_week = fn(year_start, extended) {
    case list.key_find(exceptions, extended) {
      Ok(day) -> day
      Error(Nil) -> {
        let week_start =
          year_start - modulo(weekday(year_start) - first_day, days_per_week)
        case days_per_week - { year_start - week_start } >= minimal_days {
          True -> week_start
          False -> week_start + days_per_week
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

/// A day's weekday, from 1 for Monday to 7 for Sunday.
fn weekday(epoch_day: Int) -> Int {
  modulo(epoch_day + thursday_from_monday - 1, days_per_week) + 1
}

/// A proleptic Gregorian date to days since 1970-01-01. From Howard
/// Hinnant's `days_from_civil`, whose other numbers are part of the published
/// algorithm: <https://howardhinnant.github.io/date_algorithms.html>.
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
  era * days_per_400_years + doe - days_from_march_of_year_zero
}

/// A Julian date, as #(astronomical year, month, day), for days since
/// 1970-01-01. From Richards' algorithm in the Explanatory Supplement to the
/// Astronomical Almanac, whose other numbers are part of the algorithm.
pub fn julian_from_days(days: Int) -> #(Int, Int, Int) {
  let c = days + julian_day_of_unix_epoch + 32_082
  let d = floor_divide(4 * c + 3, 1461)
  let e = c - floor_divide(1461 * d, 4)
  let m = floor_divide(5 * e + 2, 153)
  #(
    d - 4800 + floor_divide(m, 10),
    m + 3 - 12 * floor_divide(m, 10),
    e - floor_divide(153 * m + 2, 5) + 1,
  )
}

/// The inverse of `julian_from_days`, from the same algorithm.
fn days_from_julian(year: Int, month: Int, day: Int) -> Int {
  let a = floor_divide(14 - month, 12)
  let y = year + 4800 - a
  let m = month + 12 * a - 3
  let julian_day =
    day + floor_divide(153 * m + 2, 5) + 365 * y + floor_divide(y, 4) - 32_083
  julian_day - julian_day_of_unix_epoch
}

/// The first day of a year and of the next, in a calendar that is Julian
/// before `julian_before`.
pub fn year_bounds(year: Int, julian_before: Int) -> #(Int, Int) {
  #(new_year(year, julian_before), new_year(year + 1, julian_before))
}

fn new_year(year: Int, julian_before: Int) -> Int {
  let julian = days_from_julian(year, 1, 1)
  case julian < julian_before {
    True -> julian
    False -> days_from_civil(year, 1, 1)
  }
}

fn modulo(n: Int, by: Int) -> Int {
  { n % by + by } % by
}

fn floor_divide(n: Int, by: Int) -> Int {
  case int.floor_divide(n, by) {
    Ok(result) -> result
    Error(Nil) -> 0
  }
}

/// The item at `index`, counting from 0. Erlang tuples count from 1.
fn nth(tuple: HomogenousUnknownLengthTuple(a), index: Int) -> a {
  element(index + 1, tuple)
}

@external(erlang, "erlang", "element")
fn element(
  index _index: Int,
  tuple _tuple: HomogenousUnknownLengthTuple(a),
) -> a {
  panic as "element(index, tuple) can only be used on Erlang"
}

@external(erlang, "erlang", "tuple_size")
fn size(tuple _tuple: HomogenousUnknownLengthTuple(a)) -> Int {
  panic as "size(tuple) can only be used on Erlang"
}
