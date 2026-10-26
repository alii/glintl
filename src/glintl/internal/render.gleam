//// Only used on Erlang.

import gleam/int
import gleam/list
import gleam/string
import glintl/internal/calendar
import glintl/internal/data.{
  type Combined, type Digits, type EraFormats, type EraRule, type Formats,
  type Glue, type Local, type Math, type Pattern, type Shown, type Style,
  type Styles, type Token, Ascii, AsciiDigits, Combined, DateAndTime, DateOnly,
  Day, DayName, DayPeriod, Digits, Era, EraFormats, EraRule, ExtendedYear,
  Formats, Full, GlueDate, GlueText, GlueTime, H11, H12, H23, H24, Hour, Joined,
  Literal, Local, Long, Medium, Minute, MonthName, MonthNumber, NoMath,
  Proleptic, RelatedYear, Second, Short, Styles, Table, TimeOnly, WeekYear,
  Weekday, Year, YearName, Zone,
}

pub const seconds_per_minute = 60

const minutes_per_hour = 60

const seconds_per_hour = 3600

pub const seconds_per_day = 86_400

const hours_per_half_day = 12

const hours_per_day = 24

/// 1970-01-01 was a Thursday, and weekdays are numbered from Sunday.
const thursday = 4

/// Two digit years show the year modulo this.
const two_digit_years = 100

/// Numbers below this have one digit, so are padded to two.
const ten = 10

/// The longest a year can be in a calendar with Gregorian months.
const days_in_longest_year = 366

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

pub fn compile(
  formats: Formats,
  digits: Digits,
  math: Math,
  shown: Shown,
  fallback: Fallback,
) -> Compiled {
  let Formats(dates:, times:, glues:, eras:) = formats
  let main = pattern(dates, times, glues, Joined, shown)
  let eras = case shown {
    TimeOnly(_) -> []
    DateOnly(_) | DateAndTime(..) ->
      list.map(eras, fn(era: EraFormats) {
        let EraFormats(era:, dates:, combined:) = era
        #(era, prepare(pattern(dates, times, glues, combined, shown)))
      })
  }
  Compiled(main: prepare(main), eras:, digits:, math:, fallback:)
}

fn pattern(
  dates: Styles(Pattern),
  times: Styles(Pattern),
  glues: Styles(Glue),
  combined: Combined,
  shown: Shown,
) -> Pattern {
  case shown, combined {
    TimeOnly(time), _ -> pick(times, time)
    DateOnly(date), _ -> pick(dates, date)
    DateAndTime(date:, time:), Combined(both) -> pick(pick(both, date), time)
    DateAndTime(date:, time:), Joined -> {
      let date_pattern = pick(dates, date)
      let time_pattern = pick(times, time)
      list.flat_map(pick(glues, date), fn(piece) {
        case piece {
          GlueText(text) -> [Literal(text)]
          GlueDate -> date_pattern
          GlueTime -> time_pattern
        }
      })
    }
  }
}

fn pick(styles: Styles(a), style: Style) -> a {
  let Styles(full:, long:, medium:, short:) = styles
  case style {
    Full -> full
    Long -> long
    Medium -> medium
    Short -> short
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
  let seconds = unix_seconds + offset_minutes * seconds_per_minute
  let epoch_day = floor_divide(seconds, seconds_per_day)
  let rest = seconds - epoch_day * seconds_per_day
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
    Year(two_digit: True, minus:, ..) -> {
      let sign = case m.year < 0 {
        True -> minus
        False -> ""
      }
      sign <> number(int.absolute_value(m.year) % two_digit_years, True, digits)
    }
    Year(two_digit: False, minus:, first:, minus_first:) ->
      case m.year, first, minus_first {
        1, "", _ | -1, _, "" -> signed(m.year, minus, digits)
        1, first, _ -> first
        -1, _, minus_first -> minus_first
        year, _, _ -> signed(year, minus, digits)
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
    Weekday(names:) ->
      at(names, modulo(m.epoch_day + thursday, calendar.days_per_week), "")
    Era(names:) -> at(names, m.era, "")
    Hour(pad:, cycle:) -> number(hour(m.hour, cycle), pad, digits)
    Minute(pad:) -> number(m.minute, pad, digits)
    Second(pad:) -> number(m.second, pad, digits)
    DayPeriod(by_hour:, midnight:, noon:) -> {
      let on_the_hour =
        { !has_minute || m.minute == 0 } && { !has_second || m.second == 0 }
      case m.hour, on_the_hour {
        0, True -> midnight
        hour, True if hour == hours_per_half_day -> noon
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
          let hours = number(offset / minutes_per_hour, pad_hours, digits)
          case offset % minutes_per_hour, optional_minutes {
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
pub fn calendar_fields(math: Math, epoch_day: Int) -> List(Int) {
  case local(math, epoch_day, 0, 0, epoch_day * seconds_per_day) {
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
  let hour = rest / seconds_per_hour
  let minute = rest % seconds_per_hour / seconds_per_minute
  let second = rest % seconds_per_minute
  case math {
    Proleptic(eras: [newest, ..older], julian_before:) -> {
      let #(y, m, d) = case epoch_day < julian_before {
        True -> calendar.julian_from_days(epoch_day)
        False -> civil_from_days(epoch_day)
      }
      // Near the Julian switch a year can start in one calendar and end in
      // the other, so its bounds are worked out here. Elsewhere `week_year`
      // works them out only if needed.
      let #(year_start, next_year_start) = case
        epoch_day < julian_before + days_in_longest_year
      {
        True -> calendar.year_bounds(y, julian_before)
        False -> #(data.start_of_time, data.start_of_time)
      }
      let EraRule(era:, base:, sign:, ..) = era_rule(newest, older, epoch_day)
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
        year_start:,
        next_year_start:,
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
    Proleptic(eras: [], ..) | NoMath -> Error(Nil)
  }
}

/// The era a day is in. Eras are newest first, and the oldest starts at the
/// start of time.
fn era_rule(rule: EraRule, older: List(EraRule), epoch_day: Int) -> EraRule {
  case older, rule.start <= epoch_day {
    [], _ | _, True -> rule
    [next, ..rest], False -> era_rule(next, rest, epoch_day)
  }
}

/// Days since 1970-01-01 to a proleptic Gregorian date. From Howard Hinnant's
/// `civil_from_days`, whose other numbers are part of the published
/// algorithm: <https://howardhinnant.github.io/date_algorithms.html>.
fn civil_from_days(days: Int) -> #(Int, Int, Int) {
  let z = days + calendar.days_from_march_of_year_zero
  let era = floor_divide(z, calendar.days_per_400_years)
  let doe = z - era * calendar.days_per_400_years
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
    H11 -> hour % hours_per_half_day
    H12 ->
      case hour % hours_per_half_day {
        0 -> hours_per_half_day
        h -> h
      }
    H24 ->
      case hour {
        0 -> hours_per_day
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
  let text = case pad && n < ten {
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
          Error(Nil) -> c
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
    Error(Nil) -> 0
  }
}
