//// The generator writes each calendar's maths as Erlang terms of the types in
//// this module. If you change a type here, change `codegen/generate.ts` to match.
////
//// This module also works out dates in calendars with their own months, ICU's
//// week-based year and Julian dates.

@target(erlang)
import gleam/int
@target(erlang)
import gleam/list

/// A copy of `date_time.Style`, since this module can't import it.
pub type Style {
  Full
  Long
  Medium
  Short
}

@target(erlang)
/// How a calendar turns days into dates. Every locale uses the same maths for a
/// calendar.
pub type Math {
  /// Gregorian months with eras from `eras`, newest first. Days before
  /// `julian_before` use the Julian calendar, as they do in ICU.
  Proleptic(eras: List(EraRule), julian_before: Int)
  /// Years the generator reads from ICU, numbered from 0.
  Table(
    /// Chinese and Dangi years have related years and a 60 year cycle.
    cyclic: Bool,
    first_day: Int,
    /// The day after the last year in the table.
    end_day: Int,
    start_count: Int,
    /// The first day of each year, then the day after the last year.
    starts: HomogenousUnknownLengthTuple(Int),
    /// Which month layout each year uses.
    layouts: HomogenousUnknownLengthTuple(Int),
    /// Each layout has two bytes per month: its number, then its length in days.
    months: HomogenousUnknownLengthTuple(BitArray),
    /// Year rules, newest first.
    years: List(YearRule),
    /// ICU's Chinese calendar calls a few days day 0 of a month, where its astronomy
    /// goes wrong. Each is `#(day, month number)`.
    day_zero: List(#(Int, Int)),
  )
}

@target(erlang)
/// A day earlier than any glintl formats. It stands for the start of time, and
/// the generator uses the same number.
pub const start_of_time = -1_000_000_000_000

@target(erlang)
/// 1 January AD 1, in days since 1970.
pub const first_day_of_ad = -719_162

@target(erlang)
/// Eras are numbered newest first, so AD is 0.
const anno_domini = 0

@target(erlang)
const before_christ = 1

@target(erlang)
/// The Gregorian calendar's maths. AD years are astronomical years, and BC years
/// count back from 1 BC, which is year 0.
pub const gregorian =
  Proleptic(
    [gregorian_newest_era, gregorian_oldest_era],
    julian_before: start_of_time,
  )

@target(erlang)
pub const gregorian_newest_era =
  EraRule(start: first_day_of_ad, era: anno_domini, base: 0, sign: 1)

@target(erlang)
pub const gregorian_oldest_era =
  EraRule(start: start_of_time, era: before_christ, base: 1, sign: -1)

@target(erlang)
pub const gregorian_older_eras = [gregorian_oldest_era]

@target(erlang)
/// From `start` until the next era, the year is `base + sign * y`, where `y` is
/// the astronomical Gregorian year.
pub type EraRule {
  EraRule(start: Int, era: Int, base: Int, sign: Int)
}

@target(erlang)
/// From year `from` until the next rule, each year adds `year_step` to the year
/// and 1 to the extended year. Cyclic calendars also add 1 to the related year
/// and the cycle.
pub type YearRule {
  YearRule(
    from: Int,
    era: Int,
    year: Int,
    year_step: Int,
    extended: Int,
    related: Int,
    cycle: Int,
  )
}

@target(erlang)
/// An Erlang tuple where every item has the same type, so any position can be
/// read in constant time.
pub type HomogenousUnknownLengthTuple(a)

@target(erlang)
/// What a moment's zone can be called. Fixed offsets are `Unnamed`.
pub type ZoneNames {
  Unnamed
  /// `zone` is the zone's rules number, `key` finds its names, and `chain` is the
  /// locale's name bundles, most specific first.
  Named(
    key: Int,
    zone: Int,
    daylight: Bool,
    chain: List(Int),
    location: Location,
  )
}

@target(erlang)
/// What a locale needs for location names like "Los Angeles Time".
pub type Location {
  Location(
    regions: List(Int),
    region_format: String,
    fallback_format: String,
    region: Int,
  )
}

@target(erlang)
/// A moment's local date and time in a calendar. `month` counts from 0.
/// Calendars with Gregorian months leave `year_start` and `next_year_start` as
/// `start_of_time`, and `week_year` works them out when it needs them.
pub type Local {
  Local(
    epoch_day: Int,
    hour: Int,
    minute: Int,
    second: Int,
    offset_seconds: Int,
    unix_seconds: Int,
    names: ZoneNames,
    era: Int,
    year: Int,
    extended: Int,
    related: Int,
    cycle: Int,
    month: Int,
    day: Int,
    year_start: Int,
    next_year_start: Int,
  )
}

@target(erlang)
const years_in_cycle = 60

@target(erlang)
/// ICU counts Chinese and Dangi years from 2637 BC.
const cycle_epoch = 2637

@target(erlang)
/// ICU's era for a Chinese or Dangi date is the 60 year cycle it falls in,
/// counting from 1.
pub fn cycle_era(related: Int) -> Int {
  { related + cycle_epoch - 1 } / years_in_cycle + 1
}

@target(erlang)
pub const days_per_week = 7

@target(erlang)
/// 1970-01-01 was a Thursday, and weekdays here count from Monday like ICU's
/// week data.
const thursday_from_monday = 4

@target(erlang)
/// Hinnant's algorithms count from 1 March so leap days come at the end of a
/// year. This is the number of days from 0000-03-01 to 1970-01-01.
pub const days_from_march_of_year_zero = 719_468

@target(erlang)
pub const days_per_400_years = 146_097

@target(erlang)
const julian_day_of_unix_epoch = 2_440_588

@target(erlang)
pub fn table_local(
  cyclic cyclic: Bool,
  first_day first: Int,
  end_day end: Int,
  start_count count: Int,
  starts starts: HomogenousUnknownLengthTuple(Int),
  layouts layouts: HomogenousUnknownLengthTuple(Int),
  months months: HomogenousUnknownLengthTuple(BitArray),
  years years: List(YearRule),
  day_zero day_zero: List(#(Int, Int)),
  epoch_day epoch_day: Int,
  hour hour: Int,
  minute minute: Int,
  second second: Int,
  offset_seconds offset_seconds: Int,
  unix_seconds unix_seconds: Int,
  names names: ZoneNames,
) -> Result(Local, Nil) {
  // `starts` ends with the day after the last year.
  let last_year = count - 2
  case epoch_day < first || epoch_day >= end, years {
    True, _ | _, [] -> Error(Nil)
    False, [newest, ..older] -> {
      // Guess the year from the average year length, then step to it.
      let guess = { epoch_day - first } * { count - 1 } / { end - first }
      let #(i, start, next_start) =
        find_year(starts, int.clamp(guess, 0, last_year), epoch_day)
      let layout = nth(months, nth(layouts, i))
      let #(month, day) = case day_zero {
        [] -> month_and_day(layout, epoch_day - start)
        _ ->
          case list.key_find(day_zero, epoch_day) {
            Ok(month) -> #(month, 0)
            Error(Nil) -> month_and_day(layout, epoch_day - start)
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
        offset_seconds:,
        unix_seconds:,
        names:,
        era:,
        year: year + year_step * n,
        extended: extended + n,
        related: related + step,
        cycle: { cycle + step } % years_in_cycle,
        month:,
        day:,
        year_start: start,
        next_year_start: next_start,
      ))
    }
  }
}

@target(erlang)
/// Rules are newest first, and the oldest starts at the first year.
fn year_rule(rule: YearRule, older: List(YearRule), year: Int) -> YearRule {
  case older, rule.from <= year {
    [], _ | _, True -> rule
    [next, ..rest], False -> year_rule(next, rest, year)
  }
}

@target(erlang)
/// Steps from year `i` to the year that holds `epoch_day`. Returns that year
/// with its first day and the next year's.
fn find_year(
  starts: HomogenousUnknownLengthTuple(Int),
  i: Int,
  epoch_day: Int,
) -> #(Int, Int, Int) {
  let start = nth(starts, i)
  let next = nth(starts, i + 1)
  case start > epoch_day, next <= epoch_day {
    True, _ -> find_year(starts, i - 1, epoch_day)
    _, True -> find_year(starts, i + 1, epoch_day)
    _, _ -> #(i, start, next)
  }
}

@target(erlang)
fn month_and_day(layout: BitArray, days: Int) -> #(Int, Int) {
  case layout {
    <<month, length, others:bits>> ->
      case days >= length, others {
        True, <<_, _, _:bits>> -> month_and_day(others, days - length)
        _, _ -> #(month, days + 1)
      }
    _ -> #(0, days + 1)
  }
}

@target(erlang)
/// ICU's week-based year. Weeks start on `first_day`, where 1 is Monday, and a
/// year's first week is the first one with at least `minimal_days` days in it.
pub fn week_year(
  m: Local,
  first_day: Int,
  minimal_days: Int,
  exceptions: List(#(Int, Int)),
) -> Int {
  // Calendars with Gregorian months leave their year bounds for this function
  // to work out, because their years start on 1 January.
  let #(year_start, next_year_start) = case m.next_year_start == start_of_time {
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

@target(erlang)
/// Weekdays count from 1 for Monday to 7 for Sunday.
pub fn weekday(epoch_day: Int) -> Int {
  modulo(epoch_day + thursday_from_monday - 1, days_per_week) + 1
}

@target(erlang)
/// Howard Hinnant's `days_from_civil`. Its numbers come from the published algorithm
/// at <https://howardhinnant.github.io/date_algorithms.html>.
pub fn days_from_civil(year: Int, month: Int, day: Int) -> Int {
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

@target(erlang)
/// Howard Hinnant's `civil_from_days`. Its numbers come from the published algorithm
/// at <https://howardhinnant.github.io/date_algorithms.html>.
pub fn civil_from_days(days: Int) -> #(Int, Int, Int) {
  let z = days + days_from_march_of_year_zero
  let era = floor_divide(z, days_per_400_years)
  let doe = z - era * days_per_400_years
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

@target(erlang)
/// Converts days since 1970-01-01 to a Julian date, as `#(astronomical year,
/// month, day)`. This is Richards' algorithm from the Explanatory Supplement to
/// the Astronomical Almanac, which is where its numbers come from.
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

@target(erlang)
/// The reverse of `julian_from_days`.
fn days_from_julian(year: Int, month: Int, day: Int) -> Int {
  let a = floor_divide(14 - month, 12)
  let y = year + 4800 - a
  let m = month + 12 * a - 3
  let julian_day =
    day + floor_divide(153 * m + 2, 5) + 365 * y + floor_divide(y, 4) - 32_083
  julian_day - julian_day_of_unix_epoch
}

@target(erlang)
/// The first day of a year and of the next, in a calendar that's Julian before
/// `julian_before`.
pub fn year_bounds(year: Int, julian_before: Int) -> #(Int, Int) {
  #(new_year(year, julian_before), new_year(year + 1, julian_before))
}

@target(erlang)
fn new_year(year: Int, julian_before: Int) -> Int {
  let julian = days_from_julian(year, 1, 1)
  case julian < julian_before {
    True -> julian
    False -> days_from_civil(year, 1, 1)
  }
}

@target(erlang)
fn modulo(n: Int, by: Int) -> Int {
  { n % by + by } % by
}

@target(erlang)
pub fn floor_divide(n: Int, by: Int) -> Int {
  case int.floor_divide(n, by) {
    Ok(result) -> result
    Error(Nil) -> 0
  }
}

@target(erlang)
/// Counts from 0, while Erlang tuples count from 1.
fn nth(tuple: HomogenousUnknownLengthTuple(a), index: Int) -> a {
  element(index + 1, tuple)
}

@target(erlang)
@external(erlang, "erlang", "element")
fn element(
  index _index: Int,
  tuple _tuple: HomogenousUnknownLengthTuple(a),
) -> a {
  panic as "element(index, tuple) can only be used on Erlang"
}
