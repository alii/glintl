//// Finds a named time zone's offset at a moment on Erlang, the same way as
//// ICU's `OlsonTimeZone`. `codegen/zones.ts` writes the data.

@target(erlang)
import glintl/internal/data

@target(erlang)
/// When a zone's offset changes, and what it changes to.
pub type Rules {
  Rules(
    /// Seconds since 1970, 64 bits each.
    transitions: BitArray,
    /// Standard and daylight saving seconds, 32 bits each. The first applies
    /// before any transition.
    types: BitArray,
    /// The type after each transition, a byte each.
    type_map: BitArray,
    final: Final,
  )
}

@target(erlang)
/// The yearly rule after the last transition, from ICU's `finalRule`.
pub type Final {
  NoFinal
  /// `rule` is ICU's eleven numbers for a `SimpleTimeZone`, in seconds.
  Final(raw: Int, year: Int, rule: Rule)
}

/// ICU's eleven numbers for a yearly summer time rule, in seconds.
pub type Rule =
  #(Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int)

@target(erlang)
type Table

@target(erlang)
/// The zone's name as ICU writes it, and its number, from a lowercase name.
@external(erlang, "glintl_generated_time_zones", "zone")
pub fn find(lowercase_name: String) -> Result(#(String, Int), Nil)

@target(erlang)
@external(erlang, "glintl_generated_time_zones", "rules")
fn table() -> Table

@target(erlang)
@external(erlang, "erlang", "element")
fn element(position: Int, table: Table) -> Rules

@target(erlang)
const transition_bits = 64

@target(erlang)
const type_bits = 64

@target(erlang)
const bits_per_byte = 8

@target(erlang)
const offset_bits = 32

@target(erlang)
const seconds_per_day = 86_400

@target(erlang)
const days_per_week = 7

@target(erlang)
/// How many seconds the zone is ahead of UTC at a moment.
pub fn offset_seconds(zone: Int, unix_seconds: Int) -> Int {
  let Rules(transitions:, types:, type_map:, final:) =
    element(zone + 1, table())
  case final {
    Final(raw:, year:, rule:) ->
      case unix_seconds >= data.days_from_civil(year, 1, 1) * seconds_per_day {
        True -> final_offset(raw, rule, unix_seconds)
        False -> historical(transitions, types, type_map, unix_seconds)
      }
    NoFinal -> historical(transitions, types, type_map, unix_seconds)
  }
}

// --- Before the final rule ---------------------------------------------------

@target(erlang)
fn historical(
  transitions: BitArray,
  types: BitArray,
  type_map: BitArray,
  unix_seconds: Int,
) -> Int {
  let count = bit_array_bytes(transitions) * bits_per_byte / transition_bits
  let type_ = case last_at_or_before(transitions, unix_seconds, 0, count) {
    -1 -> 0
    i -> byte(type_map, i)
  }
  let assert <<
    _:bits-size(type_ * type_bits),
    raw:signed-size(offset_bits),
    dst:signed-size(offset_bits),
    _:bits,
  >> = types
  raw + dst
}

@target(erlang)
/// The last transition at or before `seconds`, or -1 if there's none. It
/// searches `low` up to, but not including, `high`.
fn last_at_or_before(
  transitions: BitArray,
  seconds: Int,
  low: Int,
  high: Int,
) -> Int {
  case low >= high {
    True -> low - 1
    False -> {
      let middle = { low + high } / 2
      case transition(transitions, middle) <= seconds {
        True -> last_at_or_before(transitions, seconds, middle + 1, high)
        False -> last_at_or_before(transitions, seconds, low, middle)
      }
    }
  }
}

@target(erlang)
fn transition(transitions: BitArray, i: Int) -> Int {
  let assert <<
    _:bits-size(i * transition_bits),
    t:signed-size(transition_bits),
    _:bits,
  >> = transitions
  t
}

@target(erlang)
fn byte(bits: BitArray, i: Int) -> Int {
  let assert <<_:bytes-size(i), b, _:bits>> = bits
  b
}

@target(erlang)
@external(erlang, "erlang", "byte_size")
fn bit_array_bytes(bits: BitArray) -> Int

// --- The final rule ----------------------------------------------------------
//
// This follows ICU's `TimeZone::getOffset` and `SimpleTimeZone::getOffset`
// and `compareToRule`, in seconds rather than milliseconds.

@target(erlang)
type Mode {
  DayOfMonth
  DayOfWeekInMonth
  DayOfWeekOnOrAfter
  DayOfWeekOnOrBefore
}

@target(erlang)
/// ICU's `SimpleTimeZone::TimeMode`.
const utc_time = 2

@target(erlang)
const wall_time = 0

@target(erlang)
const seconds_per_hour = 3600

@target(erlang)
fn final_offset(raw: Int, rule: Rule, unix_seconds: Int) -> Int {
  let #(
    start_month,
    start_day,
    start_weekday,
    start_time,
    start_mode,
    end_month,
    end_day,
    end_weekday,
    end_time,
    end_mode,
    savings,
  ) = rule
  case start_day != 0 && end_day != 0 {
    False -> raw
    True -> {
      let savings = case savings {
        0 -> seconds_per_hour
        _ -> savings
      }
      // ICU compares the rules with the local standard time.
      let local = unix_seconds + raw
      let day = data.floor_divide(local, seconds_per_day)
      let time = local - day * seconds_per_day
      let #(year, month, day_of_month) = data.civil_from_days(day)
      let month = month - 1
      // ICU counts weekdays from 1 for Sunday.
      let weekday = data.weekday(day) % days_per_week + 1
      let length = month_length(year, month)
      let previous_length = month_length(year, month - 1)
      let southern = start_month > end_month
      let start_compare =
        compare_to_rule(
          month,
          length,
          previous_length,
          day_of_month,
          weekday,
          time,
          case start_mode == utc_time {
            True -> -raw
            False -> 0
          },
          start_month,
          start_day,
          start_weekday,
          start_time,
        )
      let end_compare = case southern != { start_compare >= 0 } {
        True ->
          compare_to_rule(
            month,
            length,
            previous_length,
            day_of_month,
            weekday,
            time,
            case end_mode {
              _ if end_mode == wall_time -> savings
              _ if end_mode == utc_time -> -raw
              _ -> 0
            },
            end_month,
            end_day,
            end_weekday,
            end_time,
          )
        False -> 0
      }
      case
        { !southern && start_compare >= 0 && end_compare < 0 }
        || { southern && { start_compare >= 0 || end_compare < 0 } }
      {
        True -> raw + savings
        False -> raw
      }
    }
  }
}

@target(erlang)
/// -1, 0 or 1 as the time is before, at or after the rule's moment in
/// `rule_month`.
fn compare_to_rule(
  month: Int,
  length: Int,
  previous_length: Int,
  day_of_month: Int,
  weekday: Int,
  time: Int,
  delta: Int,
  rule_month: Int,
  rule_day: Int,
  rule_weekday: Int,
  rule_time: Int,
) -> Int {
  let #(month, day_of_month, weekday, time) =
    roll(month, length, previous_length, day_of_month, weekday, time + delta)
  case month < rule_month, month > rule_month {
    True, _ -> -1
    _, True -> 1
    False, False -> {
      let #(mode, rule_day, rule_weekday) = decode(rule_day, rule_weekday)
      let rule_day = int_min(rule_day, length)
      let rule_day_of_month = case mode {
        DayOfMonth -> rule_day
        DayOfWeekInMonth ->
          case rule_day > 0 {
            True ->
              1
              + { rule_day - 1 }
              * 7
              + { 7 + rule_weekday - { weekday - day_of_month + 1 } }
              % 7
            False ->
              length
              + { rule_day + 1 }
              * 7
              - { 7 + { weekday + length - day_of_month } - rule_weekday }
              % 7
          }
        DayOfWeekOnOrAfter ->
          rule_day
          + { 49 + rule_weekday - rule_day - weekday + day_of_month }
          % 7
        DayOfWeekOnOrBefore ->
          rule_day
          - { 49 - rule_weekday + rule_day + weekday - day_of_month }
          % 7
      }
      case day_of_month < rule_day_of_month, day_of_month > rule_day_of_month {
        True, _ -> -1
        _, True -> 1
        False, False ->
          case time < rule_time, time > rule_time {
            True, _ -> -1
            _, True -> 1
            False, False -> 0
          }
      }
    }
  }
}

@target(erlang)
/// Moves a time that's past the end or before the start of its day into the
/// next or previous day, like ICU's `compareToRule`.
fn roll(
  month: Int,
  length: Int,
  previous_length: Int,
  day_of_month: Int,
  weekday: Int,
  time: Int,
) -> #(Int, Int, Int, Int) {
  case time >= seconds_per_day, time < 0 {
    True, _ -> {
      let #(month, day_of_month) = case day_of_month + 1 > length {
        True -> #(month + 1, 1)
        False -> #(month, day_of_month + 1)
      }
      roll(
        month,
        length,
        previous_length,
        day_of_month,
        1 + weekday % 7,
        time - seconds_per_day,
      )
    }
    _, True -> {
      let #(month, day_of_month) = case day_of_month - 1 < 1 {
        True -> #(month - 1, previous_length)
        False -> #(month, day_of_month - 1)
      }
      roll(
        month,
        length,
        previous_length,
        day_of_month,
        1 + { weekday + 5 } % 7,
        time + seconds_per_day,
      )
    }
    False, False -> #(month, day_of_month, weekday, time)
  }
}

@target(erlang)
/// ICU's `SimpleTimeZone::decodeStartRule`: how a rule's day and weekday
/// pick a day.
fn decode(day: Int, weekday: Int) -> #(Mode, Int, Int) {
  case weekday {
    0 -> #(DayOfMonth, day, weekday)
    _ if weekday > 0 -> #(DayOfWeekInMonth, day, weekday)
    _ if day > 0 -> #(DayOfWeekOnOrAfter, day, -weekday)
    _ -> #(DayOfWeekOnOrBefore, -day, -weekday)
  }
}

// --- Gregorian dates ---------------------------------------------------------

@target(erlang)
/// Days in a month, from 0 for January. -1 is the December before.
fn month_length(year: Int, month: Int) -> Int {
  case month {
    -1 -> 31
    1 ->
      case is_leap_year(year) {
        True -> 29
        False -> 28
      }
    3 | 5 | 8 | 10 -> 30
    _ -> 31
  }
}

@target(erlang)
fn is_leap_year(year: Int) -> Bool {
  year % 4 == 0 && { year % 100 != 0 || year % 400 == 0 }
}

@target(erlang)
fn int_min(a: Int, b: Int) -> Int {
  case a < b {
    True -> a
    False -> b
  }
}
